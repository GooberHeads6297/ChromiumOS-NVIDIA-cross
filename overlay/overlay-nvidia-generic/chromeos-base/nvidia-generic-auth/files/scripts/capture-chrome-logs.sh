#!/bin/sh
# Soft capture — copy Chrome/shim logs to stateful WITHOUT stop ui / debug.sh.
# Use when login UI is up or just froze (SSH or brief VT2).
#
#   /usr/sbin/scripts/capture-chrome-logs.sh
#   # or: /usr/sbin/capture-chrome-logs
#
# Then from Ubuntu (power off or keep running if SSH):
#   sudo ./tools/pull-nvidia-debug-logs.sh /dev/nvme1n1
set -eu

DEST=/mnt/stateful_partition/unencrypted
TMP=/usr/local/tmp
mkdir -p "$DEST" "$TMP" 2>/dev/null || true

stamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
note="$DEST/chrome-capture-$stamp.txt"

{
  echo "==== capture-chrome-logs $stamp ===="
  echo "ui: $(status ui 2>/dev/null || true)"
  echo "frecon: $(pgrep -x frecon | tr '\n' ' ')"
  echo "chrome: $(pgrep -c chrome 2>/dev/null || echo 0)"
  echo "gpu: $(pgrep -a -f 'chrome --type=gpu' 2>/dev/null | head -2 || true)"
  echo "dri holders:"
  for c in /dev/dri/card*; do
    echo -n "  $c: "
    fuser -v "$c" 2>&1 | tr '\n' ' ' || true
    echo
  done
} >"$note" 2>&1

if [ -f /var/log/chrome/chrome ]; then
  cp -f /var/log/chrome/chrome "$DEST/chrome.log"
  cp -f /var/log/chrome/chrome "$TMP/chrome.log" 2>/dev/null || true
  echo "copied /var/log/chrome/chrome -> $DEST/chrome.log ($(wc -c </var/log/chrome/chrome) bytes)"
else
  echo "MISSING /var/log/chrome/chrome"
fi

for name in drm-addfb.log gbm-compat.log nvidia-debug.log; do
  if [ -f "$TMP/$name" ]; then
    cp -f "$TMP/$name" "$DEST/$name"
    echo "copied $TMP/$name -> $DEST/$name"
  fi
done

# Compact counters into the note file for quick VT2 readback.
if [ -f "$DEST/chrome.log" ]; then
  {
    echo "---- chrome counts ----"
    for pat in 'forcing legacy' 'Modeset succeeded' 'GetDisplays:' \
               'SchedulePageFlip' 'eglCreateImage failed' '0x00008CD6' \
               'Unable to initialize SkSurface' 'Restarting GPU' \
               'drmSetMaster' 'Page flip' 'Failed to authenticate'; do
      n=$(grep -cF "$pat" "$DEST/chrome.log" 2>/dev/null || echo 0)
      echo "  $n	$pat"
    done
    echo "---- last ERROR/WARNING (40) ----"
    grep -E 'ERROR|WARNING' "$DEST/chrome.log" 2>/dev/null | tail -40 || true
  } >>"$note"
fi

sync
echo "done. note=$note"
echo "Ubuntu: sudo ./tools/pull-nvidia-debug-logs.sh /dev/nvme1n1"
