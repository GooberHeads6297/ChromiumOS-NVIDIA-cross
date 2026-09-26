#!/bin/bash
# tools/flash.sh -- write a built image to a spare disk, with the Ubuntu disk blocked.
#
# `cros flash` and `dd` will both cheerfully destroy whatever you point them at. This
# wrapper exists so that the disk name is checked against an allowlist by something
# other than the operator's attention at 2am.
#
# Four independent refusals protect sda:
#   1. the target must appear in ALLOWED_TARGET_DISKS
#   2. the target must not appear in FORBIDDEN_TARGET_DISKS
#   3. the target must not be the disk currently carrying /
#   4. the target must have nothing mounted
#
# Usage:
#   sudo ./tools/flash.sh --board nvidia-generic --target nvme1n1
#   sudo ./tools/flash.sh --board amd64-generic --target usb      # cros flash usb://
#   sudo ./tools/flash.sh --board nvidia-generic --target nvme1n1 --dry-run

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "${REPO_ROOT}/safety/lib-common.sh"

load_limits

CROS_CHECKOUT="${CROS_CHECKOUT:-${HOME}/chromiumos}"
BOARD=nvidia-generic
TARGET=""
DRY_RUN=0
IMAGE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --board)   BOARD="${2:?}"; shift ;;
        --target)  TARGET="${2:?}"; shift ;;
        --image)   IMAGE="${2:?}"; shift ;;
        --dry-run) DRY_RUN=1 ;;
        -h|--help) sed -n '1,18p' "$0"; exit 0 ;;
        *)         die "unknown argument: $1" ;;
    esac
    shift
done

[ -n "$TARGET" ] || die "--target is required (e.g. nvme1n1, or 'usb' for cros flash usb://)"

# ---------------------------------------------------------------------------
# The USB path delegates to cros flash, which prompts for the device itself and
# never touches an internal disk.
# ---------------------------------------------------------------------------
if [ "$TARGET" = "usb" ]; then
    banner "flashing ${BOARD}/latest to USB via cros flash"
    warn "cros flash will completely replace the contents of the USB device it prompts for."
    if [ "$DRY_RUN" -eq 1 ]; then
        log "WOULD RUN: cros flash usb:// ${BOARD}/latest"
        exit 0
    fi
    cd "$CROS_CHECKOUT" || die "no checkout at ${CROS_CHECKOUT}"
    exec ./chromite/bin/cros flash "usb://" "${BOARD}/latest"
fi

TGT="${TARGET#/dev/}"
DEV="/dev/${TGT}"

banner "target validation for ${DEV}"

# ---- refusal 1 and 2: the lists ------------------------------------------
for d in $FORBIDDEN_TARGET_DISKS; do
    if [ "$TGT" = "$d" ]; then
        die "${TGT} is in FORBIDDEN_TARGET_DISKS. Ubuntu lives there. Refusing."
    fi
done

allowed=0
for d in $ALLOWED_TARGET_DISKS; do
    [ "$TGT" = "$d" ] && allowed=1
done
if [ "$allowed" -eq 0 ]; then
    die "${TGT} is not in ALLOWED_TARGET_DISKS (${ALLOWED_TARGET_DISKS}).

     If you genuinely mean to use a different disk, add it to safety/limits.conf
     deliberately rather than passing it here."
fi
log "target is in the allowlist"

# ---- refusal 3: never the running root disk -------------------------------
root_src="$(findmnt -n -o SOURCE / 2>/dev/null)"
root_disk="$(lsblk -no PKNAME "$root_src" 2>/dev/null | head -1)"
if [ -n "$root_disk" ] && [ "$TGT" = "$root_disk" ]; then
    die "${TGT} carries the running root filesystem (${root_src}). Refusing."
fi
log "target is not the running root disk (that is ${root_disk:-unknown})"

# ---- refusal 4: nothing mounted ------------------------------------------
[ -b "$DEV" ] || die "${DEV} is not a block device"

mounts="$(lsblk -no MOUNTPOINT "$DEV" 2>/dev/null | grep . || true)"
if [ -n "$mounts" ]; then
    err "mounted partitions on ${DEV}:"
    printf '%s\n' "$mounts" | sed 's/^/       /' >&2
    die "unmount them first"
fi
log "nothing mounted on ${DEV}"

# ---------------------------------------------------------------------------
# Locate the image.
# ---------------------------------------------------------------------------
if [ -z "$IMAGE" ]; then
    latest="${CROS_CHECKOUT}/src/build/images/${BOARD}/latest"
    for candidate in chromiumos_test_image.bin chromiumos_image.bin chromiumos_base_image.bin; do
        if [ -f "${latest}/${candidate}" ]; then
            IMAGE="${latest}/${candidate}"
            break
        fi
    done
fi
[ -n "$IMAGE" ] && [ -f "$IMAGE" ] || die "no image found. Build one with ./sdk/build.sh --board ${BOARD} image"

SIZE_H="$(lsblk -dno SIZE "$DEV" 2>/dev/null | tr -d ' ')"
MODEL="$(lsblk -dno MODEL "$DEV" 2>/dev/null | sed 's/ *$//')"

banner "about to overwrite ${DEV}"
cat >&2 <<EOF
  device : ${DEV}  (${SIZE_H}${MODEL:+, ${MODEL}})
  image  : ${IMAGE}
  board  : ${BOARD}

Everything currently on ${DEV} will be destroyed.
EOF

if [ "$DRY_RUN" -eq 1 ]; then
    log "WOULD RUN: cros flash ${DEV} ${IMAGE}"
    exit 0
fi

require_root

printf '\nType the device name (%s) to confirm: ' "$TGT" >&2
read -r reply
[ "$reply" = "$TGT" ] || die "confirmation did not match; nothing was written"

cd "$CROS_CHECKOUT" || die "no checkout at ${CROS_CHECKOUT}"

log "flashing..."
if ./chromite/bin/cros flash "$DEV" "$IMAGE"; then
    sync
    banner "flash complete"
    cat <<EOF
Before rebooting into it, confirm in BIOS:

  Primary Display    -> CPU / iGPU      (so a broken NVIDIA modeset cannot lock you out)
  Boot order         -> ${TGT}
  AMD SVM            -> Enabled
  IOMMU              -> Enabled

For the first NVIDIA-enabled boot, consider physically disconnecting sda. It is the
cheapest possible insurance for your Ubuntu install.
EOF
else
    die "cros flash failed; ${DEV} may be in an inconsistent state (your system disk was never touched)"
fi
