#!/bin/bash
# Hand NVIDIA DRM master to Ash WITHOUT killing frecon (VT2 must stay alive).
#
# frecon picks the connected monitor (RTX HDMI) and holds drmSetMaster.
# Chrome then logs "Failed to authenticate /dev/dri/cardN". Killing frecon
# fixes auth but destroys the VT2 console. Instead ask frecon to drop master:
#   printf '\033]drmdropmaster\a' > /run/frecon/current
#
# Also hide amdgpu DRM nodes so Ash cannot fall back to the iGPU login path
# while the monitor is on the RTX.

set -u

log() { logger -t release-nvidia-drm-master -- "$*"; echo "release-nvidia-drm-master: $*"; }

# Prefer dummy vtcon so framebuffer unbind is allowed.
for d in /sys/class/vtconsole/vtcon*; do
  [ -e "$d/name" ] || continue
  name="$(cat "$d/name" 2>/dev/null || true)"
  case "$name" in
    *dummy*)
      echo 1 > "$d/bind" 2>/dev/null || true
      ;;
  esac
done

unbound=0
for d in /sys/class/vtconsole/vtcon*; do
  [ -e "$d/name" ] || continue
  name="$(cat "$d/name" 2>/dev/null || true)"
  case "$name" in
    *frame\ buffer*|*framebuffer*)
      if echo 0 > "$d/bind" 2>/dev/null; then
        unbound=$((unbound + 1))
      fi
      ;;
  esac
done
log "unbound ${unbound} framebuffer vtconsole(s)"

# Ask frecon to drop DRM master (keeps process + VT2 pts alive).
dropped=0
for target in /run/frecon/current /run/frecon/vt0 /run/frecon/vt1; do
  if [ -e "$target" ]; then
    # OSC escape: ]drmdropmaster BEL
    printf '\033]drmdropmaster\a' > "$target" 2>/dev/null && dropped=$((dropped + 1)) || true
  fi
done
# Also try every frecon vt link.
for target in /run/frecon/vt*; do
  [ -e "$target" ] || continue
  printf '\033]drmdropmaster\a' > "$target" 2>/dev/null || true
done
log "drmdropmaster writes=${dropped} frecon_pids=$(pgrep -x frecon | tr '\n' ' ')"

# Hide Raphael *modeset* node so Ash cannot pick iGPU for scanout/login.
# Do NOT chmod 000 amdgpu renderD* — Mesa EGL walks all render nodes and
# "Failed to get system egl display" if any return EACCES (seen 2026-10-10).
# Nodes come back on reboot or: chmod 666 /dev/dri/card1
for node in /dev/dri/card[0-9]*; do
  [ -e "$node" ] || continue
  sys=$(readlink -f "/sys/class/drm/$(basename "$node")/device/driver" 2>/dev/null || true)
  case "$sys" in
    *amdgpu*)
      chmod 000 "$node" 2>/dev/null && log "hid amdgpu modeset $node" || log "failed to hide $node"
      ;;
  esac
done
# Ensure amdgpu render nodes stay open for EGL device enumeration.
for node in /dev/dri/renderD*; do
  [ -e "$node" ] || continue
  sys=$(readlink -f "/sys/class/drm/$(basename "$node")/device/driver" 2>/dev/null || true)
  case "$sys" in
    *amdgpu*)
      chmod 666 "$node" 2>/dev/null && log "keep amdgpu render $node mode 666" || true
      ;;
  esac
done

# NVIDIA character devices: Mesa nvidia-drm GBM opens these as chronos.
# EACCES here surfaces as Chrome "Unable to initialize GBM for .../cardN".
for n in /dev/nvidiactl /dev/nvidia0 /dev/nvidia-modeset /dev/nvidia-uvm \
         /dev/nvidia-uvm-tools /dev/dri/card2 /dev/dri/renderD129; do
  [ -e "$n" ] || continue
  chmod 0666 "$n" 2>/dev/null || true
  chown root:video "$n" 2>/dev/null || true
done
log "nvidia/dri nodes chmod 0666 for chronos GBM"

# Do NOT stop/kill frecon — that blanks VT2 and strands bring-up.
log "frecon left running; nvidia-drm left loaded"
exit 0
