#!/bin/bash
# safety/thermal-log.sh -- Stage 5 sustained validation.
#
# Logs GPU telemetry to CSV under load, then summarises whether the card behaved. This
# is what turns "it seemed fine" into evidence, and specifically answers the question
# that decides whether the conservative bring-up caps can be relaxed:
#
#   Does the GSP firmware manage fans and power correctly under sustained load?
#
# Run this alongside a game, not instead of one. It is a passive observer; gpu-guard.sh
# is the thing that intervenes. Run both.
#
# Usage:
#   ./safety/thermal-log.sh --duration 1800            # 30 minutes
#   ./safety/thermal-log.sh --duration 1800 --out run1.csv
#   ./safety/thermal-log.sh --analyse run1.csv         # summarise an existing log

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "${REPO_ROOT}/safety/lib-common.sh"
load_limits

DURATION=1800
INTERVAL=2
OUT=""
ANALYSE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --duration) DURATION="${2:?}"; shift ;;
        --interval) INTERVAL="${2:?}"; shift ;;
        --out)      OUT="${2:?}"; shift ;;
        --analyse)  ANALYSE="${2:?}"; shift ;;
        -h|--help)  sed -n '1,20p' "$0"; exit 0 ;;
        *)          die "unknown argument: $1" ;;
    esac
    shift
done

# ---------------------------------------------------------------------------
# Analysis. Separated so a log captured on the device can be analysed anywhere.
# ---------------------------------------------------------------------------
analyse() {
    local f="$1"
    [ -r "$f" ] || die "cannot read ${f}"

    banner "thermal analysis: ${f}"

    awk -F',' -v warn="$TEMP_WARN" -v soft="$TEMP_SOFT" -v hard="$TEMP_HARD" \
             -v crit="$TEMP_CRITICAL" -v stall_t="$FAN_STALL_TEMP" -v cap="$POWER_CAP_W" '
    NR==1 { next }                        # skip header
    {
        n++
        t=$2+0; f=$3+0; p=$4+0; c=$5+0; u=$6+0
        tsum+=t; psum+=p; csum+=c; usum+=u
        if (t>tmax) tmax=t
        if (p>pmax) pmax=p
        if (c>cmax) cmax=c
        if (f>fmax) fmax=f
        if (t>=warn) n_warn++
        if (t>=soft) n_soft++
        if (t>=hard) n_hard++
        if (t>=crit) n_crit++
        if (f==0 && t>=stall_t) n_stall++
        if (p>cap+5) n_overcap++
        # Count samples where the card was under real load, so idle time does not
        # flatter the averages.
        if (u>50) { n_load++; tload+=t; pload+=p; if (f>0) n_load_fan++ }
    }
    END {
        if (n==0) { print "no samples"; exit 1 }
        printf "samples              : %d over ~%d s\n", n, n*2
        printf "\n-- temperature --\n"
        printf "mean                 : %.1f C\n", tsum/n
        printf "peak                 : %d C\n", tmax
        printf "  >= warn (%d C)     : %d samples (%.1f%%)\n", warn, n_warn, 100*n_warn/n
        printf "  >= soft (%d C)     : %d samples (%.1f%%)\n", soft, n_soft, 100*n_soft/n
        printf "  >= hard (%d C)     : %d samples (%.1f%%)\n", hard, n_hard, 100*n_hard/n
        printf "  >= crit (%d C)     : %d samples (%.1f%%)\n", crit, n_crit, 100*n_crit/n
        printf "\n-- power --\n"
        printf "mean                 : %.1f W\n", psum/n
        printf "peak                 : %.1f W\n", pmax
        printf "  above cap (%d W)   : %d samples\n", cap, n_overcap
        printf "\n-- clocks / utilisation --\n"
        printf "mean clock           : %.0f MHz (peak %d)\n", csum/n, cmax
        printf "mean utilisation     : %.0f %%\n", usum/n
        printf "\n-- fan --\n"
        printf "peak fan             : %d %%\n", fmax
        printf "stall condition      : %d samples (0%% fan at >= %d C)\n", n_stall, stall_t
        printf "\n-- under load (utilisation > 50%%) --\n"
        if (n_load>0) {
            printf "load samples         : %d\n", n_load
            printf "mean temp under load : %.1f C\n", tload/n_load
            printf "mean power under load: %.1f W\n", pload/n_load
            printf "fans spinning        : %d/%d load samples (%.1f%%)\n", n_load_fan, n_load, 100*n_load_fan/n_load
        } else {
            printf "no samples with utilisation above 50%% -- was anything actually running?\n"
        }
        printf "\n-- verdict --\n"
        bad=0
        if (n_crit>0) { printf "FAIL reached the critical threshold (%d C)\n", crit; bad=1 }
        if (n_hard>0) { printf "FAIL reached the hard threshold (%d C)\n", hard; bad=1 }
        if (n_stall>0){ printf "FAIL fan stall condition observed -- investigate before further load\n"; bad=1 }
        if (n_overcap>0){ printf "WARN power exceeded the configured cap; the cap may not have been applied\n" }
        if (n_load>0 && n_load_fan < n_load*0.9) {
            printf "WARN fans were stopped during some load samples; check the GSP fan curve\n"
        }
        if (bad==0) {
            printf "PASS stayed within every configured threshold\n"
            if (n_load>0 && tload/n_load < soft-8) {
                printf "     Sustained load ran %.1f C below the soft threshold.\n", soft-tload/n_load
                printf "     Thermals have headroom: raising POWER_CAP_W toward stock %d W is reasonable.\n", 285
            }
        }
    }' "$f"
}

if [ -n "$ANALYSE" ]; then
    analyse "$ANALYSE"
    exit $?
fi

# ---------------------------------------------------------------------------
# Capture.
# ---------------------------------------------------------------------------
need_cmd nvidia-smi
assert_expected_gpu

OUT="${OUT:-${REPO_ROOT}/thermal-$(date '+%Y%m%dT%H%M%S').csv}"

banner "thermal logging for ${DURATION}s every ${INTERVAL}s"
log "output: ${OUT}"
log ""
log "Run a game or benchmark now. This process only observes."
log "gpu-guard.sh is what intervenes -- make sure it is also running."
log ""

# Warn rather than refuse: there are legitimate reasons to log without the guard, such
# as capturing a baseline. But say so loudly.
if ! pgrep -f 'gpu-guard.sh' >/dev/null 2>&1; then
    warn "gpu-guard.sh does not appear to be running. Logging records damage; it does not prevent it."
fi

printf 'timestamp,temp_c,fan_pct,power_w,clock_mhz,util_pct\n' > "$OUT"

end=$(( $(date +%s) + DURATION ))
samples=0
while [ "$(date +%s)" -lt "$end" ]; do
    row="$(nvidia-smi \
        --query-gpu=temperature.gpu,fan.speed,power.draw,clocks.gr,utilization.gpu \
        --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')"
    if [ -n "$row" ]; then
        printf '%s,%s\n' "$(date +%s)" "$row" >> "$OUT"
        samples=$(( samples + 1 ))
        # Light progress output so a long run does not look hung.
        if [ $(( samples % 30 )) -eq 0 ]; then
            log "${samples} samples, latest: ${row}"
        fi
    fi
    sleep "$INTERVAL"
done

log "captured ${samples} samples"
printf '\n'
analyse "$OUT"
