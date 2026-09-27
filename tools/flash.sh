#!/bin/bash
# tools/flash.sh -- write a built image to a spare disk, with the Ubuntu disk blocked.
#
# `cros flash` and `dd` will both cheerfully destroy whatever you point them at. This
# wrapper exists so that the disk name is checked against an allowlist by something
# other than the operator's attention at 2am.
#
# Five independent refusals protect your data:
#   1. the target must appear in ALLOWED_TARGET_DISKS
#   2. the target must not appear in FORBIDDEN_TARGET_DISKS
#   3. the target must not be the disk currently carrying /
#   4. the target must have nothing mounted
#   5. a protected filesystem label requires typing that label to confirm
#
# Check 5 exists because check 4 stops working the moment someone unmounts a disk in
# order to flash it. A label survives unmounting, so it covers precisely that gap.
#
# Usage:
#   ./tools/flash.sh --board amd64-generic  --target usb --dry-run
#   ./tools/flash.sh --board amd64-generic  --target usb              # baseline test
#   ./tools/flash.sh --board nvidia-generic --target usb              # the real thing
#   ./tools/flash.sh --board nvidia-generic --target usb --device /dev/sdc
#
# Do NOT wrap this in sudo. cros flash refuses to run as root and sudoes for itself when
# it needs to write the device. If you did use sudo, the script drops back to SUDO_USER
# before calling it.
# With --target usb the device is auto-detected when exactly one removable device is
# present, and --device names it explicitly otherwise. Fixed disks are refused outright on
# this path, so it cannot be aimed at sda, sdb or nvme1n1.
#
# USB is the normal target. For an internal disk the documented route is to boot the USB
# and run tools/install-to-disk.sh there, which sizes the stateful partition to the disk;
# writing an image straight to a disk does not. See docs/INSTALL.md.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "${REPO_ROOT}/safety/lib-common.sh"

load_limits

# Under sudo, HOME becomes /root. The checkout lives in the invoking user's home
# (SUDO_USER), not root's. Without this, `sudo ./tools/flash.sh` dies looking for
# /root/chromiumos even when ~/chromiumos is fine.
if [ -n "${SUDO_USER:-}" ] && [ "$(id -u)" -eq 0 ]; then
    INVOKER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    [ -n "$INVOKER_HOME" ] || INVOKER_HOME="$HOME"
else
    INVOKER_HOME="$HOME"
fi
CROS_CHECKOUT="${CROS_CHECKOUT:-${INVOKER_HOME}/chromiumos}"
BOARD=nvidia-generic
TARGET=""
DRY_RUN=0
IMAGE=""
USB_DEVICE=""

# cros flash dies with "This script cannot be run as root" and sudoes for itself when it
# needs device write access. If this wrapper was started under sudo, drop back to the
# invoking user before calling it; the safety checks above do not need root.
run_as_invoker() {
    if [ "$(id -u)" -eq 0 ]; then
        [ -n "${SUDO_USER:-}" ] || die "running as root with no SUDO_USER; cannot call cros flash as root"
        sudo -u "$SUDO_USER" -H -- "$@"
    else
        "$@"
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        --board)   BOARD="${2:?}"; shift ;;
        --target)  TARGET="${2:?}"; shift ;;
        --image)   IMAGE="${2:?}"; shift ;;
        --device)  USB_DEVICE="${2:?}"; shift ;;
        --dry-run) DRY_RUN=1 ;;
        -h|--help) sed -n '1,18p' "$0"; exit 0 ;;
        *)         die "unknown argument: $1" ;;
    esac
    shift
done

[ -n "$TARGET" ] || die "--target is required (e.g. nvme1n1, or 'usb' for cros flash usb://)"

# ---------------------------------------------------------------------------
# The USB path.
#
# Resolve and validate a specific removable device here (never ask cros to pick one).
# Writing is done with dd, not `cros flash`: on this host chromite dies with
# "cannot pickle 'FileIO' instances" under the current system Python, before it writes
# anything. A raw image write is the documented local-dev alternative and avoids that
# entirely. Auto-detection only accepts removable=1, so this branch cannot hit sda/sdb/nvme.
# ---------------------------------------------------------------------------
if [ "$TARGET" = "usb" ]; then
    banner "flashing ${BOARD}/latest to USB"

    if [ -z "$USB_DEVICE" ]; then
        candidates=""
        for d in /sys/block/*; do
            n="$(basename "$d")"
            [ "$(cat "${d}/removable" 2>/dev/null || echo 0)" = "1" ] || continue
            # Skip empty card readers and the like, which report removable=1 with no media.
            [ "$(cat "${d}/size" 2>/dev/null || echo 0)" -gt 0 ] || continue
            candidates="${candidates}${n} "
        done
        set -- $candidates
        case $# in
            0) die "no removable device found. Plug the USB stick in, or pass --device /dev/sdX" ;;
            1) USB_DEVICE="/dev/$1"; log "auto-detected the only removable device: ${USB_DEVICE}" ;;
            *) err "more than one removable device present:"
               for n in $candidates; do
                   printf '       /dev/%-8s %s  %s\n' "$n" \
                       "$(lsblk -dno SIZE "/dev/$n" 2>/dev/null | tr -d ' ')" \
                       "$(lsblk -dno MODEL "/dev/$n" 2>/dev/null | sed 's/ *$//')" >&2
               done
               die "refusing to guess; pass --device /dev/sdX" ;;
        esac
    fi

    USB_NAME="$(basename "$USB_DEVICE")"
    [ -b "$USB_DEVICE" ] || die "not a block device: ${USB_DEVICE}"
    [ -d "/sys/block/${USB_NAME}" ] || die "${USB_DEVICE} is a partition; pass the whole disk"

    # Removable is the load-bearing check here: it is what makes it impossible to aim this
    # branch at sda, sdb or nvme1n1, all of which report removable=0 on this machine.
    if [ "$(cat "/sys/block/${USB_NAME}/removable" 2>/dev/null || echo 0)" != "1" ]; then
        err "${USB_DEVICE} is a FIXED disk, not removable media."
        err "The USB target refuses fixed disks. To install to an internal disk, boot the"
        err "USB image and use tools/install-to-disk.sh there -- see docs/INSTALL.md."
        die "refusing to flash a fixed disk via --target usb"
    fi

    root_src="$(findmnt -no SOURCE / 2>/dev/null || true)"
    root_disk="$(lsblk -no PKNAME "$root_src" 2>/dev/null | head -1 || true)"
    [ -n "$root_disk" ] && [ "$root_disk" = "$USB_NAME" ] && \
        die "${USB_DEVICE} is the disk carrying your root filesystem. Absolutely not."

    log "target ${USB_DEVICE} ($(lsblk -dno SIZE "$USB_DEVICE" 2>/dev/null | tr -d ' ')$(
        m="$(lsblk -dno MODEL "$USB_DEVICE" 2>/dev/null | sed 's/ *$//')"; [ -n "$m" ] && printf ', %s' "$m")), removable"
    lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$USB_DEVICE" 2>/dev/null | sed 's/^/       /'

    # Locate the image before confirming, so a missing build fails without touching the stick.
    if [ -z "$IMAGE" ]; then
        latest="${CROS_CHECKOUT}/src/build/images/${BOARD}/latest"
        for candidate in chromiumos_test_image.bin chromiumos_image.bin chromiumos_base_image.bin; do
            if [ -f "${latest}/${candidate}" ]; then
                IMAGE="${latest}/${candidate}"
                break
            fi
        done
    fi
    [ -n "$IMAGE" ] && [ -f "$IMAGE" ] || die "no image found for ${BOARD}.

     Build one with:  ./sdk/build.sh --board ${BOARD} all
     Currently looking under: ${CROS_CHECKOUT}/src/build/images/${BOARD}/latest/"

    if [ "$DRY_RUN" -eq 1 ]; then
        labels="$(disk_fs_labels "$USB_DEVICE" | tr '\n' ' ')"
        [ -n "$labels" ] && warn "carries filesystem label(s): ${labels}"
        log "all USB safety checks passed; nothing was written"
        log "WOULD RUN: dd if=${IMAGE} of=${USB_DEVICE} bs=4M status=progress conv=fsync"
        exit 0
    fi

    confirm_if_labelled "$USB_DEVICE" || die "aborted at the label confirmation"

    warn "everything on ${USB_DEVICE} will be destroyed."
    log "image: ${IMAGE} ($(du -h "$IMAGE" | cut -f1))"
    printf '\nType the device name (%s) to confirm: ' "$USB_NAME" >&2
    read -r reply
    [ "$reply" = "$USB_NAME" ] || die "confirmation did not match; nothing was written"

    # Unmount any partitions still held by the desktop; dd refuses a busy device.
    while read -r mp; do
        [ -n "$mp" ] || continue
        log "unmounting ${mp}"
        udisksctl unmount -b "$mp" 2>/dev/null || sudo umount "$mp" 2>/dev/null || true
    done < <(lsblk -lnpo NAME,MOUNTPOINT "$USB_DEVICE" | awk 'NF==2 {print $1}')

    log "writing image with dd (cros flash is broken on this host's Python; see HANDOFF)"
    # dd needs root for the raw device. Prefer the caller's sudo so the password prompt is
    # normal; if already root, just run it.
    if [ "$(id -u)" -eq 0 ]; then
        dd if="$IMAGE" of="$USB_DEVICE" bs=4M status=progress conv=fsync
    else
        sudo dd if="$IMAGE" of="$USB_DEVICE" bs=4M status=progress conv=fsync
    fi || die "dd failed; ${USB_DEVICE} may be partially written. Re-run this command."

    sync
    banner "flash complete"
    log "${USB_DEVICE} now holds ${BOARD} from ${IMAGE}"
    cat <<EOF

Next: reboot, enter BIOS, boot the USB stick.
Keep Primary Display on the iGPU / CPU Graphics. Monitor on the motherboard.
SSH (test image): root / test0000
EOF
    exit 0
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

# ---- refusal 5: protected filesystem label -------------------------------
# Deliberately after the mount check, because this is the one that still applies once
# the disk has been unmounted.
if [ "$DRY_RUN" -eq 0 ]; then
    confirm_if_labelled "$DEV" || die "aborted at the label confirmation"
else
    labels="$(disk_fs_labels "$DEV" | tr '\n' ' ')"
    [ -n "$labels" ] && warn "target carries filesystem label(s): ${labels}" \
                     || log "target has no filesystem labels"
fi

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

NOTE: for an internal disk, the documented route is USB first, then
tools/install-to-disk.sh from the booted image -- see docs/INSTALL.md.
Writing the image straight to a disk leaves the partition table sized for the
image rather than for ${SIZE_H:-the disk}, so the stateful partition does not grow into the
free space. chromeos-install sizes it correctly. This path is fine for a
re-flash, but it is not the recommended first install.
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
if run_as_invoker ./chromite/bin/cros flash "$DEV" "$IMAGE"; then
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
