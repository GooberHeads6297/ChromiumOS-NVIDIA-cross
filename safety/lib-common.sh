#!/bin/bash
# safety/lib-common.sh -- shared helpers for the safety scripts.
#
# Sourced, never executed directly. Deliberately dependency-free beyond coreutils
# and nvidia-smi so it works identically on the Ubuntu host and inside a
# ChromiumOS test image.

# shellcheck shell=bash

SAFETY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SAFETY_DIR}/.." && pwd)"

# ---------------------------------------------------------------------------
# Logging. Everything goes to stderr so stdout stays clean for machine-readable
# output, which matters for the guard's --print-once mode.
# ---------------------------------------------------------------------------
_ts() { date '+%Y-%m-%dT%H:%M:%S%z'; }

log()  { printf '[%s] %s\n'        "$(_ts)" "$*" >&2; }
warn() { printf '[%s] WARN  %s\n'  "$(_ts)" "$*" >&2; }
err()  { printf '[%s] ERROR %s\n'  "$(_ts)" "$*" >&2; }
die()  { err "$*"; exit 1; }

# A visually distinct banner for the things that must not be missed.
banner() {
    printf '\n' >&2
    printf '================================================================\n' >&2
    printf '  %s\n' "$*" >&2
    printf '================================================================\n' >&2
}

load_limits() {
    local conf="${SAFETY_DIR}/limits.conf"
    [ -r "$conf" ] || die "cannot read ${conf}"
    # shellcheck source=/dev/null
    . "$conf"
    : "${GPU_PCI_ADDR:?limits.conf missing GPU_PCI_ADDR}"
    : "${TEMP_CRITICAL:?limits.conf missing TEMP_CRITICAL}"
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

is_root() { [ "$(id -u)" -eq 0 ]; }

require_root() {
    is_root || die "must run as root (needs PCI sysfs and nvidia-smi control access)"
}

# ---------------------------------------------------------------------------
# GPU identity and telemetry.
# ---------------------------------------------------------------------------

# Confirm we are talking to the card the thresholds were tuned for. A different
# GPU must never silently inherit AD103 limits.
assert_expected_gpu() {
    need_cmd nvidia-smi
    local name
    name="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 | sed 's/^ *//;s/ *$//')"
    [ -n "$name" ] || die "nvidia-smi returned no GPU; is the driver loaded?"
    if [ "$name" != "$GPU_EXPECT_NAME" ]; then
        die "GPU mismatch: found '${name}', limits.conf expects '${GPU_EXPECT_NAME}'.
     Refusing to apply thresholds tuned for a different card.
     If the hardware genuinely changed, re-measure and update safety/limits.conf."
    fi
    log "GPU confirmed: ${name}"
}

# Single nvidia-smi invocation per poll. Returns comma-separated:
#   temp,fan,power_draw,clock_gr,util
# Fields the card does not expose come back as [N/A]; callers must tolerate that.
# Note: temperature.memory is deliberately absent -- this consumer card reports
# N/A for it, so no guard logic may depend on it.
gpu_sample() {
    nvidia-smi \
        --query-gpu=temperature.gpu,fan.speed,power.draw,clocks.gr,utilization.gpu \
        --format=csv,noheader,nounits 2>/dev/null | head -1
}

# Extract field $2 (1-based) from a comma-separated sample $1, trimmed.
# Non-numeric or N/A values become the empty string.
sample_field() {
    local sample="$1" idx="$2" v
    v="$(printf '%s' "$sample" | awk -F',' -v i="$idx" '{gsub(/^[ \t]+|[ \t]+$/,"",$i); print $i}')"
    case "$v" in
        ''|*[!0-9.]*) printf '' ;;
        *)            printf '%s' "${v%%.*}" ;;
    esac
}

# ---------------------------------------------------------------------------
# Hard prohibitions. These encode the only operations that can actually destroy
# the card, so they are checked rather than merely documented.
#
# Note on the sysfs `rom` attribute: writing to it CANNOT flash the card. The
# kernel's pci_write_rom() handler only toggles an internal read-enable flag
# (see drivers/pci/pci-sysfs.c), which is why vbios-backup.sh is safe. Real
# danger comes from vendor flashing tools that drive the EEPROM directly.
# ---------------------------------------------------------------------------
FLASH_TOOLS="nvflash nvflash64 nvidia-vbios-flash amdvbflash"

assert_no_flash_tools() {
    local t found=""
    for t in $FLASH_TOOLS; do
        if command -v "$t" >/dev/null 2>&1; then
            found="${found} ${t}"
        fi
    done
    if [ -n "$found" ]; then
        die "VBIOS flashing tool(s) present on PATH:${found}
     This project never flashes firmware. Remove them before continuing."
    fi
    log "no VBIOS flashing tools on PATH"
}

# Report the filesystem labels found on a disk's partitions, one per line.
disk_fs_labels() {
    local dev="$1"
    lsblk -no LABEL "$dev" 2>/dev/null | sed 's/^ *//;s/ *$//' | grep -v '^$' || true
}

# Warn, and demand an explicit typed confirmation, when the target disk carries a
# filesystem label we have flagged as worth protecting.
#
# This exists to cover a specific hole. Checking "is anything mounted?" is a good guard
# right up until someone unmounts the disk to prepare it for flashing, at which point the
# guard silently stops guarding. A label survives unmounting, so it keeps working exactly
# when the mount check stops.
#
# Returns 0 to proceed, non-zero to abort.
confirm_if_labelled() {
    local dev="$1" auto_yes="${2:-0}"
    local labels found="" l p
    labels="$(disk_fs_labels "$dev")"
    [ -n "$labels" ] || return 0

    for l in $labels; do
        for p in ${PROTECTED_FS_LABELS:-}; do
            [ "$l" = "$p" ] && found="$l"
        done
    done

    if [ -z "$found" ]; then
        log "target ${dev} has filesystem label(s) [$(echo "$labels" | tr '\n' ' ')] -- none protected"
        return 0
    fi

    banner "target ${dev} carries protected filesystem label '${found}'"
    err "This disk is formatted and labelled. Everything on it will be destroyed,"
    err "and not just that partition -- the entire disk is repartitioned."
    printf '\n' >&2
    lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$dev" 2>/dev/null | sed 's/^/     /' >&2
    printf '\n' >&2

    if [ "$auto_yes" = "1" ]; then
        warn "proceeding without prompting (--yes given)"
        return 0
    fi

    printf 'Type the label (%s) to confirm you mean to destroy it: ' "$found" >&2
    local reply
    read -r reply
    if [ "$reply" != "$found" ]; then
        err "confirmation did not match; nothing was written"
        return 1
    fi
    log "confirmed destruction of '${found}' on ${dev}"
    return 0
}

# Assert the caps we are about to apply are inside the card's own legal range and
# never above stock. Guards against a typo in limits.conf becoming an overclock.
assert_caps_sane() {
    if [ "$POWER_CAP_W" -gt "$POWER_STOCK_W" ]; then
        die "POWER_CAP_W=${POWER_CAP_W} exceeds stock ${POWER_STOCK_W} W. Refusing to raise power limits."
    fi
    if [ "$POWER_CAP_W" -lt "$POWER_MIN_W" ]; then
        die "POWER_CAP_W=${POWER_CAP_W} is below the card's minimum ${POWER_MIN_W} W; nvidia-smi would reject it."
    fi
    if [ "$CLOCK_CEIL_MHZ" -gt "$CLOCK_STOCK_MAX_MHZ" ]; then
        die "CLOCK_CEIL_MHZ=${CLOCK_CEIL_MHZ} exceeds stock ${CLOCK_STOCK_MAX_MHZ} MHz. Refusing to overclock."
    fi
    if [ "$TEMP_CRITICAL" -ge 92 ]; then
        die "TEMP_CRITICAL=${TEMP_CRITICAL} is at or above the hardware slowdown point (92 C); it would never fire in time."
    fi
    log "caps sane: ${POWER_CAP_W} W (stock ${POWER_STOCK_W}), ${CLOCK_CEIL_MHZ} MHz (stock ${CLOCK_STOCK_MAX_MHZ})"
}
