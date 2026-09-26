#!/bin/bash
# safety/gpu-guard.sh -- thermal / power / fan watchdog for the RTX 4070 Ti SUPER.
#
# Runs on the Ubuntu host during driver work and ships into the ChromiumOS image as
# an upstart job (see overlay/.../gpu-guard.conf). Polls the card once per tick and
# escalates through a ladder of increasingly blunt responses.
#
# Design rules, in order of importance:
#
#   1. The hardware is the real backstop. This card slows down at 92 C and shuts
#      off at 97 C in silicon, and on Ada the GSP firmware owns the fan curve
#      independently of the host driver. Every threshold here fires BELOW those
#      points, so the guard's job is to stop us before the hardware has to.
#
#   2. Never act on a single reading. Sensor reads glitch; poweroff is rude. Every
#      level must be confirmed over N consecutive polls.
#
#   3. Never depend on a sensor this card does not have. temperature.memory reads
#      N/A on this consumer board, so no logic references it.
#
#   4. Zero fan at low temperature is CORRECT. This card stops its fans when idle
#      (measured: 0% at 41 C). A stall only matters once it is hot.
#
# Usage:
#   sudo ./safety/gpu-guard.sh                 # arm the watchdog (applies caps)
#   sudo ./safety/gpu-guard.sh --dry-run       # log actions, never execute them
#   sudo ./safety/gpu-guard.sh --no-caps       # monitor only, do not touch limits
#   sudo ./safety/gpu-guard.sh --print-once    # one sample to stdout, then exit
#        ./safety/gpu-guard.sh --self-test     # drive the ladder with fake samples
#
# --self-test needs no GPU and no root; it is how we verify the ladder.

set -uo pipefail

. "$(dirname "$0")/lib-common.sh"

load_limits

DRY_RUN=0
APPLY_CAPS=1
SELF_TEST=0
PRINT_ONCE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)    DRY_RUN=1 ;;
        --no-caps)    APPLY_CAPS=0 ;;
        --self-test)  SELF_TEST=1; DRY_RUN=1; APPLY_CAPS=0 ;;
        --print-once) PRINT_ONCE=1 ;;
        -h|--help)    sed -n '1,40p' "$0"; exit 0 ;;
        *)            die "unknown argument: $1" ;;
    esac
    shift
done

# ---------------------------------------------------------------------------
# Escalation state. One confirmation counter per level.
# ---------------------------------------------------------------------------
n_soft=0
n_hard=0
n_crit=0
n_fan=0
soft_applied=0

# Set by the ladder so --self-test can assert on it.
LAST_ACTION=""

# ---------------------------------------------------------------------------
# Actions. Each honours DRY_RUN so the ladder can be exercised safely.
# ---------------------------------------------------------------------------
do_run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        log "WOULD RUN: $*"
        return 0
    fi
    "$@" >/dev/null 2>&1
}

apply_caps() {
    [ "$APPLY_CAPS" -eq 1 ] || { log "caps not applied (--no-caps)"; return 0; }
    assert_caps_sane
    log "applying bring-up caps: power ${POWER_CAP_W} W, graphics clock ceiling ${CLOCK_CEIL_MHZ} MHz"
    # -pl sets the board power limit; -lgc pins the graphics clock range. Both stay
    # inside the card's stock envelope; assert_caps_sane() already refused anything
    # that would raise a limit.
    do_run nvidia-smi -pm 1
    do_run nvidia-smi -pl "$POWER_CAP_W"
    do_run nvidia-smi -lgc "0,${CLOCK_CEIL_MHZ}"
}

action_soft() {
    LAST_ACTION="soft"
    [ "$soft_applied" -eq 1 ] && return 0
    soft_applied=1
    local floor=$(( CLOCK_CEIL_MHZ / 2 ))
    warn "SOFT trip: dropping graphics clock ceiling to ${floor} MHz"
    do_run nvidia-smi -lgc "0,${floor}"
}

# Collect PIDs holding the GPU. nvidia-smi reports compute clients directly;
# graphics clients are found via the device nodes, which catches Chrome's GPU
# process and anything in the Steam container.
gpu_pids() {
    nvidia-smi --query-compute-apps=pid --format=csv,noheader 2>/dev/null | tr -d ' '
    if command -v fuser >/dev/null 2>&1; then
        fuser /dev/nvidia[0-9]* /dev/nvidiactl 2>/dev/null | tr ' ' '\n'
    fi
}

action_hard() {
    LAST_ACTION="hard"
    local pids
    pids="$(gpu_pids | grep -E '^[0-9]+$' | sort -u | grep -v "^$$\$" || true)"
    if [ -z "$pids" ]; then
        warn "HARD trip: no GPU client processes found to stop"
        return 0
    fi
    warn "HARD trip: terminating GPU clients: $(echo "$pids" | tr '\n' ' ')"
    local p
    for p in $pids; do
        do_run kill -TERM "$p"
    done
    [ "$DRY_RUN" -eq 1 ] || sleep 2
    for p in $pids; do
        if [ "$DRY_RUN" -eq 0 ] && kill -0 "$p" 2>/dev/null; then
            warn "client ${p} ignored SIGTERM; sending SIGKILL"
            kill -KILL "$p" 2>/dev/null || true
        fi
    done
}

action_critical() {
    LAST_ACTION="critical"
    banner "CRITICAL TRIP -- POWERING OFF"
    err "sustained condition beyond safe limits; hardware slowdown is at 92 C and we do not want to rely on it"
    action_hard
    LAST_ACTION="critical"
    do_run sync
    do_run poweroff -f
}

action_fan_stall() {
    LAST_ACTION="fan_stall"
    banner "FAN STALL DETECTED -- POWERING OFF"
    err "fan reported 0% while GPU at or above ${FAN_STALL_TEMP} C for ${FAN_STALL_CONFIRM} consecutive polls."
    err "This is the one software-reachable state that can actually damage the card."
    action_hard
    LAST_ACTION="fan_stall"
    do_run sync
    do_run poweroff -f
}

# ---------------------------------------------------------------------------
# The ladder. Pure function of (temp, fan, power) plus the confirmation counters,
# which is what makes --self-test meaningful.
# ---------------------------------------------------------------------------
evaluate() {
    local temp="$1" fan="$2" power="$3"
    LAST_ACTION=""

    # A missing temperature reading is itself suspicious, but it is not evidence of
    # heat. Log and wait rather than escalating on absent data.
    if [ -z "$temp" ]; then
        warn "no temperature reading available; holding"
        return 0
    fi

    # Fan stall: only meaningful once the card is hot enough that fans should run.
    if [ -n "$fan" ] && [ "$fan" -eq 0 ] && [ "$temp" -ge "$FAN_STALL_TEMP" ]; then
        n_fan=$(( n_fan + 1 ))
        warn "fan 0% at ${temp} C (${n_fan}/${FAN_STALL_CONFIRM})"
        if [ "$n_fan" -ge "$FAN_STALL_CONFIRM" ]; then
            action_fan_stall
            return 0
        fi
    else
        n_fan=0
    fi

    if [ "$temp" -ge "$TEMP_CRITICAL" ]; then
        n_crit=$(( n_crit + 1 ))
        err "temp ${temp} C >= critical ${TEMP_CRITICAL} C (${n_crit}/${CONFIRM_SAMPLES})"
        if [ "$n_crit" -ge "$CONFIRM_SAMPLES" ]; then
            action_critical
            return 0
        fi
    else
        n_crit=0
    fi

    if [ "$temp" -ge "$TEMP_HARD" ]; then
        n_hard=$(( n_hard + 1 ))
        warn "temp ${temp} C >= hard ${TEMP_HARD} C (${n_hard}/${CONFIRM_SAMPLES})"
        if [ "$n_hard" -ge "$CONFIRM_SAMPLES" ]; then
            action_hard
            return 0
        fi
    else
        n_hard=0
    fi

    if [ "$temp" -ge "$TEMP_SOFT" ]; then
        n_soft=$(( n_soft + 1 ))
        warn "temp ${temp} C >= soft ${TEMP_SOFT} C (${n_soft}/${CONFIRM_SAMPLES})"
        if [ "$n_soft" -ge "$CONFIRM_SAMPLES" ]; then
            action_soft
            return 0
        fi
    else
        n_soft=0
    fi

    if [ "$temp" -ge "$TEMP_WARN" ]; then
        LAST_ACTION="warn"
        warn "temp ${temp} C >= warn ${TEMP_WARN} C (power ${power:-?} W, fan ${fan:-?}%)"
    fi
    return 0
}

reset_counters() { n_soft=0; n_hard=0; n_crit=0; n_fan=0; soft_applied=0; }

# ---------------------------------------------------------------------------
# Self-test: drive the ladder with synthetic samples and assert each level fires
# where it should. No GPU, no root, no heat required.
# ---------------------------------------------------------------------------
self_test() {
    local failures=0

    check() {
        local want="$1" got="$2" desc="$3"
        if [ "$want" = "$got" ]; then
            printf 'PASS  %-46s -> %s\n' "$desc" "${got:-none}"
        else
            printf 'FAIL  %-46s -> want %s, got %s\n' "$desc" "$want" "${got:-none}"
            failures=$(( failures + 1 ))
        fi
    }

    banner "gpu-guard self-test (synthetic samples, dry-run)"
    printf 'thresholds: warn=%s soft=%s hard=%s critical=%s fan_stall=%s@%s confirm=%s\n\n' \
        "$TEMP_WARN" "$TEMP_SOFT" "$TEMP_HARD" "$TEMP_CRITICAL" \
        "0%" "${FAN_STALL_TEMP}C" "$CONFIRM_SAMPLES"

    # Idle must be completely silent. This is the regression that matters most:
    # the card's real idle state is 0% fan at 41 C and must never trip anything.
    reset_counters
    evaluate 41 0 19 >/dev/null 2>&1
    check "" "$LAST_ACTION" "idle 41C, fan 0% (zero-RPM) is silent"

    # Normal gaming load, fans spinning: silent.
    reset_counters
    evaluate 72 55 190 >/dev/null 2>&1
    check "" "$LAST_ACTION" "load 72C, fan 55% is silent"

    # Warn is advisory only and fires on the first sample.
    reset_counters
    evaluate 79 60 195 >/dev/null 2>&1
    check "warn" "$LAST_ACTION" "79C raises a warning"

    # Soft must NOT fire before confirmation. It still warns, since 84C is above the
    # warn threshold -- "warn" here is the proof that soft did not fire.
    reset_counters
    evaluate 84 60 195 >/dev/null 2>&1
    check "warn" "$LAST_ACTION" "84C once warns but does not trip soft"

    # ...and must fire on the Nth consecutive sample.
    reset_counters
    local i
    for i in $(seq 1 "$CONFIRM_SAMPLES"); do evaluate 84 60 195 >/dev/null 2>&1; done
    check "soft" "$LAST_ACTION" "84C x${CONFIRM_SAMPLES} trips soft (clock drop)"

    # A single cool sample must clear the counter.
    reset_counters
    evaluate 84 60 195 >/dev/null 2>&1
    evaluate 60 60 195 >/dev/null 2>&1
    for i in $(seq 1 $(( CONFIRM_SAMPLES - 1 ))); do evaluate 84 60 195 >/dev/null 2>&1; done
    check "warn" "$LAST_ACTION" "a cool sample resets the soft counter"

    reset_counters
    for i in $(seq 1 "$CONFIRM_SAMPLES"); do evaluate 88 80 200 >/dev/null 2>&1; done
    check "hard" "$LAST_ACTION" "88C x${CONFIRM_SAMPLES} trips hard (kill clients)"

    reset_counters
    for i in $(seq 1 "$CONFIRM_SAMPLES"); do evaluate 91 100 200 >/dev/null 2>&1; done
    check "critical" "$LAST_ACTION" "91C x${CONFIRM_SAMPLES} trips critical (poweroff)"

    # Fan stall needs its own longer confirmation and must beat the thermal ladder
    # to the punch, because a stalled fan at 70 C is heading somewhere bad fast.
    reset_counters
    for i in $(seq 1 $(( FAN_STALL_CONFIRM - 1 ))); do evaluate 75 0 200 >/dev/null 2>&1; done
    check "" "$LAST_ACTION" "fan 0% at 75C below confirm count holds"

    reset_counters
    for i in $(seq 1 "$FAN_STALL_CONFIRM"); do evaluate 75 0 200 >/dev/null 2>&1; done
    check "fan_stall" "$LAST_ACTION" "fan 0% at 75C x${FAN_STALL_CONFIRM} trips stall"

    # Absent sensor data must not escalate.
    reset_counters
    evaluate "" "" "" >/dev/null 2>&1
    check "" "$LAST_ACTION" "missing temperature does not escalate"

    # Every threshold must sit below the silicon slowdown point.
    reset_counters
    if [ "$TEMP_CRITICAL" -lt 92 ] && [ "$TEMP_HARD" -lt "$TEMP_CRITICAL" ] \
       && [ "$TEMP_SOFT" -lt "$TEMP_HARD" ] && [ "$TEMP_WARN" -lt "$TEMP_SOFT" ]; then
        printf 'PASS  %-46s -> %s\n' "ladder is ordered and below 92C slowdown" "ok"
    else
        printf 'FAIL  %-46s\n' "ladder ordering/bounds"
        failures=$(( failures + 1 ))
    fi

    printf '\n'
    if [ "$failures" -eq 0 ]; then
        banner "self-test PASSED"
        return 0
    fi
    banner "self-test FAILED (${failures} failure(s))"
    return 1
}

# ---------------------------------------------------------------------------
# Entry points.
# ---------------------------------------------------------------------------
if [ "$SELF_TEST" -eq 1 ]; then
    self_test
    exit $?
fi

need_cmd nvidia-smi
assert_expected_gpu

if [ "$PRINT_ONCE" -eq 1 ]; then
    s="$(gpu_sample)"
    printf 'temp=%s fan=%s power=%s clock=%s util=%s\n' \
        "$(sample_field "$s" 1)" "$(sample_field "$s" 2)" \
        "$(sample_field "$s" 3)" "$(sample_field "$s" 4)" \
        "$(sample_field "$s" 5)"
    exit 0
fi

require_root
assert_no_flash_tools
apply_caps

banner "gpu-guard armed"
log "poll ${POLL_INTERVAL}s | warn ${TEMP_WARN} | soft ${TEMP_SOFT} | hard ${TEMP_HARD} | critical ${TEMP_CRITICAL}"
log "fan stall: 0% at >= ${FAN_STALL_TEMP} C for ${FAN_STALL_CONFIRM} polls"
log "hardware backstop (not ours): slowdown 92 C, shutdown 97 C"
[ "$DRY_RUN" -eq 1 ] && warn "DRY RUN: actions will be logged, not executed"

trap 'log "gpu-guard stopping"; exit 0' INT TERM

while :; do
    sample="$(gpu_sample)"
    if [ -z "$sample" ]; then
        warn "nvidia-smi returned nothing; driver may have fallen over"
    else
        evaluate \
            "$(sample_field "$sample" 1)" \
            "$(sample_field "$sample" 2)" \
            "$(sample_field "$sample" 3)"
    fi
    sleep "$POLL_INTERVAL"
done
