#!/bin/sh
# Every-boot GPU → Ash GUI path (persistent; no Ubuntu re-arm, no debug.sh).
#
# Does the parts of debug.sh that make RTX login work:
#   nodes, frecon master release/kill, modeset-target, chrome-nvidia-egl.
# Does NOT stop ui for probing, does NOT consume nvidia-auto-debug.
#
# Installed as /usr/sbin/nvidia-gui-bringup; Upstart runs it on starting ui.
set -eu

LOG=/mnt/stateful_partition/unencrypted/nvidia-gui-bringup.log
mkdir -p /mnt/stateful_partition/unencrypted /usr/local/tmp 2>/dev/null || true
# Truncate each boot so the log stays small.
: >"$LOG" 2>/dev/null || true
chmod 644 "$LOG" 2>/dev/null || true

log() {
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "?")
  echo "$ts $*" >>"$LOG" 2>/dev/null || true
  logger -t nvidia-gui-bringup -- "$*" 2>/dev/null || true
}

log "==== bringup start ===="

# --- 1. NVIDIA char nodes + DRI perms ---
if [ -x /usr/sbin/create-nvidia-nodes ]; then
  /usr/sbin/create-nvidia-nodes >>"$LOG" 2>&1 || true
elif [ -x /usr/sbin/scripts/create-nvidia-nodes.sh ]; then
  /usr/sbin/scripts/create-nvidia-nodes.sh >>"$LOG" 2>&1 || true
fi

# Wait briefly for nvidia-drm card (cold boot race).
i=0
while [ "$i" -lt 30 ]; do
  [ -e /dev/dri/card2 ] && break
  i=$((i + 1))
  sleep 1
done

if [ -x /usr/share/chromiumos-nvidia-cross/release-nvidia-drm-master.sh ]; then
  /usr/share/chromiumos-nvidia-cross/release-nvidia-drm-master.sh >>"$LOG" 2>&1 || true
fi

for n in /dev/nvidiactl /dev/nvidia0 /dev/nvidia-modeset /dev/nvidia-uvm \
         /dev/nvidia-uvm-tools /dev/dri/card2 /dev/dri/renderD129 \
         /dev/dri/renderD128; do
  [ -e "$n" ] || continue
  chmod 0666 "$n" 2>/dev/null || true
done
# Hide amdgpu modeset only (release script does this; re-assert).
for node in /dev/dri/card[0-9]*; do
  [ -e "$node" ] || continue
  sys=$(readlink -f "/sys/class/drm/$(basename "$node")/device/driver" 2>/dev/null || true)
  case "$sys" in
    *amdgpu*) chmod 000 "$node" 2>/dev/null || true ;;
  esac
done

# Shim log files chronos must append.
: > /usr/local/tmp/drm-addfb.log 2>/dev/null || true
: > /usr/local/tmp/gbm-compat.log 2>/dev/null || true
chmod 666 /usr/local/tmp/drm-addfb.log /usr/local/tmp/gbm-compat.log 2>/dev/null || true

# GBM backend symlink for NVIDIA allocator.
ln -sfn ../libnvidia-allocator.so.1 /usr/local/lib64/gbm/nvidia-drm_gbm.so 2>/dev/null || true

# --- 2. chrome-nvidia-egl + ui.override (idempotent) ---
if [ ! -x /usr/sbin/chrome-nvidia-egl ]; then
  log "WARN missing /usr/sbin/chrome-nvidia-egl"
fi
if [ ! -f /etc/init/ui.override ] ||
   ! grep -qF 'chrome-nvidia-egl' /etc/init/ui.override 2>/dev/null; then
  mount -o remount,rw / 2>/dev/null || true
  printf '%s\n' 'env CHROME_COMMAND_FLAG="--chrome-command=/usr/sbin/chrome-nvidia-egl"' \
    > /etc/init/ui.override 2>/dev/null || true
  log "wrote /etc/init/ui.override"
fi

# --- 3. modeset-target for AddFB shim (preferred 3440 mode) ---
for t in /run/frecon/current /run/frecon/vt*; do
  [ -e "$t" ] || continue
  printf '\033]drmdropmaster\a' > "$t" 2>/dev/null || true
done
sleep 0.2 2>/dev/null || true

if [ -x /usr/sbin/drm-take-master ]; then
  /usr/sbin/drm-take-master /dev/dri/card2 >>"$LOG" 2>&1 || true
elif [ -x /usr/local/sbin/drm-take-master ]; then
  /usr/local/sbin/drm-take-master /dev/dri/card2 >>"$LOG" 2>&1 || true
fi

MODESET=""
if [ -x /usr/sbin/drm-modeset-test ]; then
  MODESET=/usr/sbin/drm-modeset-test
elif [ -x /usr/local/sbin/drm-modeset-test ]; then
  MODESET=/usr/local/sbin/drm-modeset-test
fi
if [ -n "$MODESET" ] && [ -e /dev/dri/card2 ]; then
  log "drm-modeset-test (brief pink → modeset-target)"
  "$MODESET" /dev/dri/card2 >>"$LOG" 2>&1 || log "drm-modeset-test exit=$?"
else
  log "WARN no drm-modeset-test or card2"
fi

chmod 0666 /dev/dri/card2 /dev/dri/renderD129 2>/dev/null || true

# --- 4. Kill frecon so Ash keeps DRM master (VT2 blanks — habitability tradeoff) ---
if pgrep -x frecon >/dev/null 2>&1; then
  log "killing frecon for Ash DRM master"
  # shellcheck disable=SC2046
  kill -CONT $(pgrep -x frecon) 2>/dev/null || true
  # shellcheck disable=SC2046
  kill -TERM $(pgrep -x frecon) 2>/dev/null || true
  sleep 0.3 2>/dev/null || sleep 1
  # shellcheck disable=SC2046
  kill -KILL $(pgrep -x frecon) 2>/dev/null || true
fi
log "frecon left: $(pgrep -x frecon | tr '\n' ' ')"

if [ -x /usr/sbin/drm-take-master ]; then
  /usr/sbin/drm-take-master /dev/dri/card2 >>"$LOG" 2>&1 || true
fi

log "==== bringup done — ui may start ===="
exit 0
