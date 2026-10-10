#!/bin/bash
# Arm headless Stage-3 debug on a ChromiumOS disk (no VT2 needed).
#
#   sudo ./tools/arm-nvidia-auto-debug.sh /dev/nvme1n1
#   sudo ./tools/arm-nvidia-auto-debug.sh /dev/nvme1n1 --hold-ui   # also pause Ash for VT2
#
# Then boot CrOS, wait ~90s, power off (or SSH), and:
#   sudo ./tools/pull-nvidia-debug-logs.sh /dev/nvme1n1 && ./tools/verify-modeset-from-logs.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOLD=0
DEV=""
for arg in "$@"; do
  case "$arg" in
    --hold-ui) HOLD=1 ;;
    /dev/*) DEV="$arg" ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
  esac
done

pick_cros_disk() {
  local d
  for d in /dev/nvme0n1 /dev/nvme1n1 /dev/sda /dev/sdb; do
    [ -b "$d" ] || continue
    if lsblk -npo LABEL,PARTLABEL "$d" 2>/dev/null | grep -qE 'H-STATE|^STATE' &&
       lsblk -npo LABEL,PARTLABEL "$d" 2>/dev/null | grep -q ROOT-A; then
      printf '%s\n' "$d"
      return 0
    fi
  done
  return 1
}

if [ "$(id -u)" -ne 0 ]; then
  echo "re-run as root: sudo $0 ${DEV:-/dev/nvme1n1}" >&2
  exit 1
fi

if [ -z "$DEV" ]; then
  DEV="$(pick_cros_disk)" || {
    echo "pass ChromiumOS disk (ROOT-A + H-STATE)" >&2
    lsblk -o NAME,LABEL,PARTLABEL >&2
    exit 1
  }
fi

# Refresh scripts + upstart job on ROOT + stateful.
"${REPO_ROOT}/tools/copy-sbin-scripts-to-disk.sh" "$DEV"

label_of() {
  local l
  l=$(lsblk -no LABEL "$1" 2>/dev/null | sed '/^$/d' | head -n1)
  if [ -n "$l" ]; then
    printf '%s\n' "$l"
    return
  fi
  lsblk -no PARTLABEL "$1" 2>/dev/null | sed '/^$/d' | head -n1
}

STATE=""
shopt -s nullglob
for part in "${DEV}"p* "${DEV}"[0-9]*; do
  [ -b "$part" ] || continue
  case "$(label_of "$part")" in
    STATE|H-STATE) STATE="$part" ;;
  esac
done
shopt -u nullglob
[ -n "$STATE" ] || { echo "no STATE/H-STATE on ${DEV}" >&2; exit 1; }

MNT="$(mktemp -d /tmp/arm-nvidia-auto-XXXXXX)"
cleanup() {
  umount "$MNT" 2>/dev/null || true
  rmdir "$MNT" 2>/dev/null || true
}
trap cleanup EXIT

mount "$STATE" "$MNT"
mkdir -p "$MNT/unencrypted"
: >"$MNT/unencrypted/nvidia-auto-debug"
# Clear stale logs so pull sees this run.
: >"$MNT/unencrypted/nvidia-debug.log"
: >"$MNT/unencrypted/drm-addfb.log"
: >"$MNT/unencrypted/gbm-compat.log"
: >"$MNT/unencrypted/nvidia-auto-debug-upstart.log"
if [ "$HOLD" -eq 1 ]; then
  : >"$MNT/unencrypted/nvidia-hold-ui"
  echo "armed: nvidia-auto-debug + nvidia-hold-ui on ${STATE}"
else
  rm -f "$MNT/unencrypted/nvidia-hold-ui"
  echo "armed: nvidia-auto-debug on ${STATE}"
fi
sync
echo "boot CrOS, wait ~90s (no VT2 needed), power off, then pull logs:"
echo "  sudo ./tools/pull-nvidia-debug-logs.sh ${DEV} && ./tools/verify-modeset-from-logs.sh"
