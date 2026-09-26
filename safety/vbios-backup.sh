#!/bin/bash
# safety/vbios-backup.sh -- take a read-only copy of the card's VBIOS.
#
# This is insurance, not a step in the build. Nothing in this project ever writes
# the VBIOS back; the backup exists purely so that the question "could I restore
# it?" has a boring answer.
#
# Why this is safe: the only write performed here is `echo 1 > .../rom`, and the
# kernel's pci_write_rom() handler treats that attribute as a read-enable toggle,
# not a programming interface (drivers/pci/pci-sysfs.c). It physically cannot
# reach the card's EEPROM. Actual flashing requires a vendor tool driving the
# flash controller, which assert_no_flash_tools() refuses to allow near this repo.
#
# The backup is written OUTSIDE the repo by default so a 512 KiB binary blob never
# lands in git.
#
# Usage: sudo ./safety/vbios-backup.sh [output-dir]

set -euo pipefail

. "$(dirname "$0")/lib-common.sh"

load_limits
require_root
need_cmd sha256sum

OUT_DIR="${1:-${HOME}/.local/share/chromiumos-nvidia-cross/vbios}"
ROM_SYSFS="/sys/bus/pci/devices/${GPU_PCI_ADDR}/rom"

[ -e "$ROM_SYSFS" ] || die "no ROM attribute at ${ROM_SYSFS}; is ${GPU_PCI_ADDR} the right device?"

assert_expected_gpu

VBIOS_VERSION="$(nvidia-smi --query-gpu=vbios_version --format=csv,noheader | head -1 | tr -d ' ')"
STAMP="$(date '+%Y%m%dT%H%M%S')"
OUT_FILE="${OUT_DIR}/vbios-${VBIOS_VERSION}-${STAMP}.rom"

mkdir -p "$OUT_DIR"

log "card VBIOS version: ${VBIOS_VERSION}"
log "enabling ROM read access (read-enable toggle only, not a flash operation)"

# Enable, read, then always disable again -- even if the read fails.
cleanup() {
    echo 0 > "$ROM_SYSFS" 2>/dev/null || true
    log "ROM read access disabled again"
}
trap cleanup EXIT

echo 1 > "$ROM_SYSFS"

log "reading ${ROM_SYSFS} -> ${OUT_FILE}"
if ! cat "$ROM_SYSFS" > "$OUT_FILE" 2>/dev/null; then
    die "ROM read failed. This is harmless -- nothing was modified. On some boards the
     ROM BAR is only readable before the driver binds; you can retry from a live USB
     with the nvidia module blacklisted. The backup is optional insurance."
fi

SIZE="$(stat -c %s "$OUT_FILE")"
if [ "$SIZE" -eq 0 ]; then
    rm -f "$OUT_FILE"
    die "ROM read produced 0 bytes (nothing was modified). See the retry note above."
fi

sha256sum "$OUT_FILE" > "${OUT_FILE}.sha256"

# A valid PCI option ROM starts with the 0x55 0xAA signature. If that is missing
# the dump is truncated or the BAR was shadowed; say so rather than pretending the
# backup is good.
SIG="$(head -c 2 "$OUT_FILE" | od -An -tx1 | tr -d ' \n')"
if [ "$SIG" != "55aa" ]; then
    warn "dump does not start with the expected 55aa PCI option ROM signature (got ${SIG})."
    warn "Treat this backup as unverified. Nothing was written to the card."
else
    log "PCI option ROM signature 55aa verified"
fi

banner "VBIOS backup complete"
log "file:   ${OUT_FILE}"
log "size:   ${SIZE} bytes"
log "sha256: $(cut -d' ' -f1 < "${OUT_FILE}.sha256")"
log ""
log "This project will never write this file back to the card."
log "It exists only so that restoring is possible in principle."
