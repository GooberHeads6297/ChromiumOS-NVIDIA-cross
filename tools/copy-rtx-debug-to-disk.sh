#!/bin/bash
# Copy nvidia-rtx-debug onto a ChromiumOS disk without rebuilding.
#
#   sudo ./tools/copy-rtx-debug-to-disk.sh /dev/nvme0n1
#   sudo ./tools/copy-rtx-debug-to-disk.sh /dev/sdc

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${REPO_ROOT}/overlay/overlay-nvidia-generic/chromeos-base/chromeos-bsp-nvidia-generic/files/nvidia-rtx-debug.py"
DEV="${1:-/dev/nvme0n1}"

if [ "$(id -u)" -ne 0 ]; then
    echo "re-run as root: sudo $0 ${DEV}" >&2
    exit 1
fi
[ -f "$SRC" ] || { echo "missing $SRC" >&2; exit 1; }
[ -b "$DEV" ] || { echo "not a block device: $DEV" >&2; exit 1; }

label_of() { lsblk -no LABEL "$1" 2>/dev/null | head -n1; }

MNT="$(mktemp -d /tmp/cros-rtx-XXXXXX)"
cleanup() {
    umount "$MNT" 2>/dev/null || true
    rmdir "$MNT" 2>/dev/null || true
}
trap cleanup EXIT

install_scripts() {
    local dest="$1"
    mkdir -p "$dest"
    install -m 0755 "$SRC" "${dest}/nvidia-rtx-debug"
    install -m 0755 "$SRC" "${dest}/nvidia-rtx-debug.py"
    ls -l "${dest}/nvidia-rtx-debug" "${dest}/nvidia-rtx-debug.py"
}

ROOTS=()
STATE=""
for part in "${DEV}"*; do
    [ -b "$part" ] || continue
    case "$(label_of "$part")" in
        ROOT-A) ROOTS+=("$part") ;;
        STATE|H-STATE) STATE="$part" ;;
    esac
done
[ "${#ROOTS[@]}" -ge 1 ] || { echo "no ROOT-A on ${DEV}" >&2; exit 1; }

for root in "${ROOTS[@]}"; do
    echo "=== ${root} ROOT-A ==="
    umount "$MNT" 2>/dev/null || true
    mount -o rw "$root" "$MNT" || mount -o rw,noload "$root" "$MNT"
    install_scripts "${MNT}/usr/sbin"
    sync
    umount "$MNT"
done

if [ -n "$STATE" ]; then
    echo "=== ${STATE} stateful ==="
    mount -o rw "$STATE" "$MNT"
    mkdir -p "${MNT}/dev_image/sbin"
    install_scripts "${MNT}/dev_image/sbin"
    sync
    umount "$MNT"
fi

echo
echo "copied. On ChromiumOS VT2:"
echo "  nvidia-rtx-debug"
echo "  python3 /usr/sbin/nvidia-rtx-debug.py --out /tmp/rtx-debug.txt"
echo "  python3 /usr/local/sbin/nvidia-rtx-debug.py"
