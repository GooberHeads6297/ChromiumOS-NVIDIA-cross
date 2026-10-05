#!/bin/bash
# Drop fbcon's DRM master on NVIDIA so Ash/minigbm can CREATE_DUMB.
# Splash can still draw with fbdev=1; this runs immediately before `ui`.
# Does not unload nvidia-drm.
#
# Name stays "frame buffer device" after unbind; /bind is the real state (0/1).

set -u

log() { logger -t release-nvidia-drm-master -- "$*"; echo "release-nvidia-drm-master: $*"; }

# Prefer dummy vtcon as console so unbinding the framebuffer is allowed.
for d in /sys/class/vtconsole/vtcon*; do
  [ -e "$d/name" ] || continue
  name="$(cat "$d/name" 2>/dev/null || true)"
  case "$name" in
    *dummy*)
      echo 1 > "$d/bind" 2>/dev/null || true
      log "bound dummy $(basename "$d") bind=$(cat "$d/bind" 2>/dev/null)"
      ;;
  esac
done

unbound=0
for d in /sys/class/vtconsole/vtcon*; do
  [ -e "$d/name" ] || continue
  name="$(cat "$d/name" 2>/dev/null || true)"
  before="$(cat "$d/bind" 2>/dev/null || echo '?')"
  log "$(basename "$d") name='${name}' bind=${before}"
  case "$name" in
    *frame\ buffer*|*framebuffer*)
      if echo 0 > "$d/bind" 2>/dev/null; then
        after="$(cat "$d/bind" 2>/dev/null || echo '?')"
        log "unbound $(basename "$d") bind ${before}->${after}"
        unbound=$((unbound + 1))
      else
        log "failed to unbind $(basename "$d") bind=${before}"
      fi
      ;;
  esac
done

log "unbound ${unbound} framebuffer vtconsole(s); nvidia-drm left loaded"
exit 0
