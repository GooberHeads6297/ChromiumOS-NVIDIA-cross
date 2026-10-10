#!/bin/bash
# Pull nvidia-debug / shim logs from ChromiumOS H-STATE into the repo.
#
#   sudo ./tools/pull-nvidia-debug-logs.sh
#   sudo ./tools/pull-nvidia-debug-logs.sh /dev/nvme0n1
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

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
  echo "re-run as root: sudo $0 ${1:-}" >&2
  exit 1
fi

if [ "${1:-}" != "" ]; then
  DEV="$1"
else
  DEV="$(pick_cros_disk)" || {
    echo "pass ChromiumOS disk (ROOT-A + H-STATE)" >&2
    lsblk -o NAME,LABEL,PARTLABEL >&2
    exit 1
  }
fi

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

MNT="$(mktemp -d /tmp/pull-nvidia-logs-XXXXXX)"
cleanup() {
  umount "$MNT" 2>/dev/null || true
  rmdir "$MNT" 2>/dev/null || true
}
trap cleanup EXIT

mount -o ro "$STATE" "$MNT"

# Prefer the largest usable nvidia-debug.log (early snap to unencrypted is often tiny).
mapfile -t CANDS < <(find "$MNT/unencrypted" "$MNT/dev_image/tmp" \
  -name 'nvidia-debug.log' 2>/dev/null || true)
SRC=""
BEST=0
for c in "${CANDS[@]:-}"; do
  [ -f "$c" ] || continue
  sz=$(stat -c '%s' "$c")
  # skip empty/null-padded stubs under 2KiB if a bigger copy exists
  if [ "$sz" -gt "$BEST" ]; then
    BEST=$sz
    SRC=$c
  fi
done
if [ -z "$SRC" ]; then
  echo "no nvidia-debug.log under ${STATE}" >&2
  echo "looked in: unencrypted/ and dev_image/tmp/" >&2
  find "$MNT" -name 'nvidia-debug.log' 2>/dev/null | head || true
  exit 1
fi

echo "source: $SRC"
echo "mtime:  $(stat -c '%y' "$SRC")  size=$BEST"
echo "--- header ---"
head -5 "$SRC"
echo "---------------"
# strip trailing NUL padding from interrupted snaps
tr -d '\000' < "$SRC" > "${REPO_ROOT}/nvidia-debug.log"

for name in drm-addfb.log gbm-compat.log nvidia-auto-debug-upstart.log chrome.log; do
  BESTF=""
  BESTMT=0
  BESTSZ=0
  for cand in "$MNT/dev_image/tmp/$name" "$MNT/unencrypted/$name"; do
    [ -f "$cand" ] || continue
    # Prefer newest mtime so a stale multi-MB gbm-compat.log cannot win.
    mt=$(stat -c '%Y' "$cand")
    sz=$(stat -c '%s' "$cand")
    if [ "$mt" -gt "$BESTMT" ] || { [ "$mt" -eq "$BESTMT" ] && [ "$sz" -gt "$BESTSZ" ]; }; then
      BESTMT=$mt
      BESTSZ=$sz
      BESTF=$cand
    fi
  done
  if [ -n "$BESTF" ]; then
    tr -d '\000' < "$BESTF" > "${REPO_ROOT}/$name"
    echo "copied $name from $BESTF (mtime=$BESTMT size=$BESTSZ)"
  else
    echo "missing $name"
  fi
done

# Soft-capture notes from capture-chrome-logs.sh
mapfile -t NOTES < <(find "$MNT/unencrypted" -maxdepth 1 -name 'chrome-capture-*.txt' 2>/dev/null | sort -r | head -3)
for n in "${NOTES[@]:-}"; do
  [ -f "$n" ] || continue
  base=$(basename "$n")
  tr -d '\000' < "$n" > "${REPO_ROOT}/$base"
  echo "copied $base"
done

for f in nvidia-debug.log drm-addfb.log gbm-compat.log nvidia-auto-debug-upstart.log chrome.log; do
  [ -f "${REPO_ROOT}/$f" ] || continue
  chown --reference="${REPO_ROOT}/tools/pull-nvidia-debug-logs.sh" "${REPO_ROOT}/$f" 2>/dev/null || true
done
chown --reference="${REPO_ROOT}/tools/pull-nvidia-debug-logs.sh" \
  "${REPO_ROOT}"/chrome-capture-*.txt 2>/dev/null || true

echo
if grep -q 'drm-modeset-test' "${REPO_ROOT}/nvidia-debug.log"; then
  echo "OK: log contains drm-modeset-test (debug.sh ran)"
else
  echo "NOTE: no drm-modeset-test in log — arm with tools/arm-nvidia-auto-debug.sh and reboot"
fi
if [ -f "${REPO_ROOT}/nvidia-auto-debug-upstart.log" ]; then
  echo "--- auto-debug upstart (tail) ---"
  tail -20 "${REPO_ROOT}/nvidia-auto-debug-upstart.log" || true
fi
if grep -qE 'SetCrtc OK|PAGE_FLIP|ioctl SETCRTC' "${REPO_ROOT}/nvidia-debug.log" \
   "${REPO_ROOT}/drm-addfb.log" 2>/dev/null; then
  echo "OK: modeset/pageflip activity present"
fi
echo "done -> ${REPO_ROOT}/nvidia-debug.log"
