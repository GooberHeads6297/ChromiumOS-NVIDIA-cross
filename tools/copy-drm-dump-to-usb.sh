#!/bin/bash
# Copy nvidia-drm-dump onto a flashed ChromiumOS USB without rebuilding.
#
#   sudo ./tools/copy-drm-dump-to-usb.sh
#   sudo ./tools/copy-drm-dump-to-usb.sh /dev/sdc
#
# Writes ROOT-A:/usr/sbin/nvidia-drm-dump and STATE:/dev_image/sbin/nvidia-drm-dump
# (the latter is /usr/local/sbin after boot on test images).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${REPO_ROOT}/overlay/overlay-nvidia-generic/chromeos-base/chromeos-bsp-nvidia-generic/files/nvidia-drm-dump.py"
DEV="${1:-/dev/sdc}"

if [ "$(id -u)" -ne 0 ]; then
    echo "re-run as root: sudo $0 ${DEV}" >&2
    exit 1
fi

[ -f "$SRC" ] || { echo "missing $SRC" >&2; exit 1; }
[ -b "$DEV" ] || { echo "not a block device: $DEV" >&2; exit 1; }

ROOT_PART="${DEV}3"
STATE_PART="${DEV}1"

label_of() {
    lsblk -no LABEL "$1" 2>/dev/null | head -n1
}

root_label="$(label_of "$ROOT_PART")"
state_label="$(label_of "$STATE_PART")"
if [ "$root_label" != "ROOT-A" ]; then
    echo "refusing: ${ROOT_PART} label is '${root_label}', expected ROOT-A" >&2
    exit 1
fi
if [ "$state_label" != "STATE" ]; then
    echo "refusing: ${STATE_PART} label is '${state_label}', expected STATE" >&2
    exit 1
fi

MNT="$(mktemp -d /tmp/cros-usb-XXXXXX)"
cleanup() {
    umount "$MNT" 2>/dev/null || true
    rmdir "$MNT" 2>/dev/null || true
}
trap cleanup EXIT

copy_into() {
    local dest_dir="$1"
    mkdir -p "$dest_dir"
    install -m 0755 "$SRC" "${dest_dir}/nvidia-drm-dump"
    # Keep a .py name too so `python3 /usr/sbin/nvidia-drm-dump.py` works.
    install -m 0755 "$SRC" "${dest_dir}/nvidia-drm-dump.py"
    ls -l "${dest_dir}/nvidia-drm-dump" "${dest_dir}/nvidia-drm-dump.py"
}

echo "mounting ${ROOT_PART} (ROOT-A) rw"
if ! mount -o rw "$ROOT_PART" "$MNT"; then
    echo "retrying ROOT-A with noload" >&2
    mount -o rw,noload "$ROOT_PART" "$MNT"
fi
copy_into "${MNT}/usr/sbin"
sync
umount "$MNT"

echo "mounting ${STATE_PART} (STATE) rw"
mount -o rw "$STATE_PART" "$MNT"
if [ -d "${MNT}/dev_image" ]; then
    copy_into "${MNT}/dev_image/sbin"
else
    mkdir -p "${MNT}/dev_image/sbin"
    copy_into "${MNT}/dev_image/sbin"
fi
sync
umount "$MNT"

echo
echo "copied. Boot the USB and run:"
echo "  nvidia-drm-dump"
echo "or:"
echo "  python3 /usr/sbin/nvidia-drm-dump.py"
echo "or:"
echo "  python3 /usr/local/sbin/nvidia-drm-dump.py"
