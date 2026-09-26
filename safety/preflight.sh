#!/bin/bash
# safety/preflight.sh -- gate that must pass before any bare-metal test.
#
# Checks the conditions that keep a failed experiment cheap:
#   - we are talking to the card the thresholds were tuned for
#   - the iGPU still owns the console, so a broken NVIDIA modeset cannot lock us out
#   - no VBIOS flashing tool is anywhere near this machine
#   - the install target is a spare disk and provably not the Ubuntu disk
#   - a VBIOS backup exists
#
# Exit status 0 means it is reasonable to proceed. Anything else means stop.
#
# Usage:
#   sudo ./safety/preflight.sh                # checks without a disk target
#   sudo ./safety/preflight.sh nvme1n1        # also validate an install target

set -uo pipefail

. "$(dirname "$0")/lib-common.sh"

load_limits

TARGET_DISK="${1:-}"
FAILURES=0
WARNINGS=0

pass() { printf '  [ OK ]  %s\n' "$*"; }
fail() { printf '  [FAIL]  %s\n' "$*"; FAILURES=$(( FAILURES + 1 )); }
soft() { printf '  [WARN]  %s\n' "$*"; WARNINGS=$(( WARNINGS + 1 )); }

banner "preflight checks"

# ---------------------------------------------------------------------------
printf '\nGPU identity\n'
# ---------------------------------------------------------------------------
if ! command -v nvidia-smi >/dev/null 2>&1; then
    fail "nvidia-smi not found"
else
    name="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 | sed 's/^ *//;s/ *$//')"
    if [ -z "$name" ]; then
        soft "nvidia-smi found no GPU. Expected if the module is deliberately blacklisted."
    elif [ "$name" = "$GPU_EXPECT_NAME" ]; then
        pass "card is ${name}"
        vbios="$(nvidia-smi --query-gpu=vbios_version --format=csv,noheader | head -1 | tr -d ' ')"
        pass "VBIOS ${vbios}"
    else
        fail "card is '${name}', limits.conf expects '${GPU_EXPECT_NAME}'"
    fi
fi

if [ -d "/sys/bus/pci/devices/${GPU_PCI_ADDR}" ]; then
    pass "GPU present at ${GPU_PCI_ADDR}"
else
    fail "no PCI device at ${GPU_PCI_ADDR}"
fi

# ---------------------------------------------------------------------------
printf '\nDisplay ownership (the lockout safeguard)\n'
# ---------------------------------------------------------------------------
igpu_sys="/sys/bus/pci/devices/${IGPU_PCI_ADDR}"
if [ -d "$igpu_sys" ]; then
    igpu_drv="$(basename "$(readlink -f "${igpu_sys}/driver" 2>/dev/null)" 2>/dev/null || echo none)"
    if [ "$igpu_drv" = "$IGPU_DRIVER" ]; then
        pass "iGPU ${IGPU_PCI_ADDR} bound to ${IGPU_DRIVER}: a console survives any NVIDIA failure"
    else
        fail "iGPU ${IGPU_PCI_ADDR} is bound to '${igpu_drv}', expected '${IGPU_DRIVER}'.
          Enable the iGPU and set it as primary display in BIOS before bare-metal testing."
    fi
else
    fail "iGPU not present at ${IGPU_PCI_ADDR}. Enable it in BIOS: it is the recovery path."
fi

# ---------------------------------------------------------------------------
printf '\nProhibited tooling\n'
# ---------------------------------------------------------------------------
found=""
for t in $FLASH_TOOLS; do
    command -v "$t" >/dev/null 2>&1 && found="${found} ${t}"
done
if [ -n "$found" ]; then
    fail "VBIOS flashing tool(s) on PATH:${found} -- remove them"
else
    pass "no VBIOS flashing tools on PATH"
fi

# ---------------------------------------------------------------------------
printf '\nCap sanity (never above stock)\n'
# ---------------------------------------------------------------------------
if [ "$POWER_CAP_W" -le "$POWER_STOCK_W" ] && [ "$POWER_CAP_W" -ge "$POWER_MIN_W" ]; then
    pass "power cap ${POWER_CAP_W} W within [${POWER_MIN_W}, stock ${POWER_STOCK_W}]"
else
    fail "power cap ${POWER_CAP_W} W outside the safe range [${POWER_MIN_W}, ${POWER_STOCK_W}]"
fi
if [ "$CLOCK_CEIL_MHZ" -le "$CLOCK_STOCK_MAX_MHZ" ]; then
    pass "clock ceiling ${CLOCK_CEIL_MHZ} MHz at or below stock ${CLOCK_STOCK_MAX_MHZ} MHz"
else
    fail "clock ceiling ${CLOCK_CEIL_MHZ} MHz exceeds stock ${CLOCK_STOCK_MAX_MHZ} MHz"
fi
if [ "$TEMP_CRITICAL" -lt 92 ] && [ "$TEMP_HARD" -lt "$TEMP_CRITICAL" ] \
   && [ "$TEMP_SOFT" -lt "$TEMP_HARD" ] && [ "$TEMP_WARN" -lt "$TEMP_SOFT" ]; then
    pass "thermal ladder ${TEMP_WARN}/${TEMP_SOFT}/${TEMP_HARD}/${TEMP_CRITICAL} ordered and below 92 C slowdown"
else
    fail "thermal ladder is misordered or reaches the 92 C hardware slowdown"
fi

# ---------------------------------------------------------------------------
printf '\nInstall target\n'
# ---------------------------------------------------------------------------
root_src="$(findmnt -n -o SOURCE / 2>/dev/null || echo unknown)"
root_disk="$(lsblk -no PKNAME "$root_src" 2>/dev/null | head -1 || echo unknown)"
pass "root filesystem lives on ${root_src} (disk ${root_disk:-unknown})"

if [ -z "$TARGET_DISK" ]; then
    soft "no install target given; pass one (e.g. nvme1n1) to validate it"
else
    tgt="${TARGET_DISK#/dev/}"
    if [ "$tgt" = "$root_disk" ]; then
        fail "target ${tgt} is the disk carrying your root filesystem. Absolutely not."
    fi
    blocked=0
    for d in $FORBIDDEN_TARGET_DISKS; do
        [ "$tgt" = "$d" ] && blocked=1
    done
    if [ "$blocked" -eq 1 ]; then
        fail "target ${tgt} is hard-blocked by FORBIDDEN_TARGET_DISKS (Ubuntu lives there)"
    fi
    allowed=0
    for d in $ALLOWED_TARGET_DISKS; do
        [ "$tgt" = "$d" ] && allowed=1
    done
    # ALLOWED_TARGET_DISKS governs INTERNAL disks. Removable media is judged on the
    # removable flag instead, because the USB phase writes to a stick that has no reason
    # to be in the allowlist, and a removable device is a safer target than any internal
    # disk by definition: it cannot be Ubuntu and it cannot be a data disk we care about.
    removable="$(cat "/sys/block/${tgt}/removable" 2>/dev/null || echo 0)"
    if [ "$allowed" -eq 1 ]; then
        pass "target ${tgt} is in the allowlist"
    elif [ "$removable" = "1" ]; then
        pass "target ${tgt} is removable media: valid for the USB phase, not an internal install"
    else
        fail "target ${tgt} is a fixed disk and not in ALLOWED_TARGET_DISKS (${ALLOWED_TARGET_DISKS})"
    fi
    if [ -b "/dev/${tgt}" ]; then
        pass "/dev/${tgt} exists ($(lsblk -dno SIZE "/dev/${tgt}" 2>/dev/null | tr -d ' '))"
        mounted="$(lsblk -no MOUNTPOINT "/dev/${tgt}" 2>/dev/null | grep -c . || true)"
        if [ "${mounted:-0}" -gt 0 ]; then
            fail "/dev/${tgt} has mounted partitions; unmount before flashing"
        else
            pass "/dev/${tgt} has nothing mounted"
        fi
    else
        fail "/dev/${tgt} is not a block device"
    fi
fi

# ---------------------------------------------------------------------------
printf '\nVBIOS backup\n'
# ---------------------------------------------------------------------------
vbios_dir="${HOME}/.local/share/chromiumos-nvidia-cross/vbios"
if ls "${vbios_dir}"/vbios-*.rom >/dev/null 2>&1; then
    pass "backup present in ${vbios_dir}"
else
    soft "no VBIOS backup found. Run: sudo ./safety/vbios-backup.sh
          Optional insurance, but cheap. Nothing here ever writes firmware."
fi

# ---------------------------------------------------------------------------
printf '\nEnvironment\n'
# ---------------------------------------------------------------------------
if [ -d /sys/kernel/iommu_groups ]; then
    pass "IOMMU active ($(ls /sys/kernel/iommu_groups 2>/dev/null | wc -l) groups)"
else
    soft "IOMMU not active (only matters if you later want VM passthrough)"
fi
avail="$(df -BG --output=avail / 2>/dev/null | tail -1 | tr -dc '0-9')"
if [ -n "$avail" ] && [ "$avail" -ge 200 ]; then
    pass "${avail} GB free on / (ChromiumOS checkout plus build needs 150-300 GB)"
else
    soft "only ${avail:-?} GB free on /; a full ChromiumOS build wants 150-300 GB"
fi

# ---------------------------------------------------------------------------
printf '\n'
if [ "$FAILURES" -eq 0 ]; then
    banner "preflight PASSED (${WARNINGS} warning(s))"
    printf 'Safe to proceed. Arm the watchdog before applying load:\n'
    printf '  sudo ./safety/gpu-guard.sh\n\n'
    exit 0
fi
banner "preflight FAILED (${FAILURES} failure(s), ${WARNINGS} warning(s))"
printf 'Do not start a bare-metal test until the failures above are resolved.\n\n'
exit 1
