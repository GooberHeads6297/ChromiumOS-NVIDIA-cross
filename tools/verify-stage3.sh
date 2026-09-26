#!/bin/bash
# tools/verify-stage3.sh -- the Stage 3 gate. Run this ON the ChromiumOS device.
#
# Stage 3 asks: is the ChromeOS UI actually being composited by the RTX card?
#
# The trap this script exists to catch: Chrome falls back to software rendering
# silently. The UI looks fine, you conclude it works, and nothing is using the GPU. So
# this checks the render path rather than whether pixels appeared.
#
# Run Stage 2's gate first. This one assumes the driver already loads.
#
# Usage:  ssh root@<device> /tmp/verify-stage3.sh

set -uo pipefail

FAIL=0
WARN=0
ok()   { printf '  [ OK ]  %s\n' "$*"; }
bad()  { printf '  [FAIL]  %s\n' "$*"; FAIL=$(( FAIL + 1 )); }
note() { printf '  [WARN]  %s\n' "$*"; WARN=$(( WARN + 1 )); }
hdr()  { printf '\n%s\n' "$*"; }

printf '================================================================\n'
printf '  Stage 3 gate: ChromeOS UI rendering on the RTX 4070 Ti SUPER\n'
printf '================================================================\n'

# ---------------------------------------------------------------------------
hdr "1. Modesetting enabled"
# ---------------------------------------------------------------------------
ms="$(cat /sys/module/nvidia_drm/parameters/modeset 2>/dev/null || echo missing)"
case "$ms" in
    Y|1) ok "nvidia_drm modeset=${ms}" ;;
    N|0) bad "nvidia_drm modeset=${ms}. Stage 3 needs modeset=1.
          Edit /etc/modprobe.d/nvidia-modeset-off.conf and reboot." ;;
    *)   bad "nvidia_drm not loaded" ;;
esac

fb="$(cat /sys/module/nvidia_drm/parameters/fbdev 2>/dev/null || echo '?')"
[ "$fb" = "Y" ] || [ "$fb" = "1" ] && ok "nvidia_drm fbdev=${fb}" \
                                   || note "nvidia_drm fbdev=${fb}; no framebuffer console on the RTX"

# ---------------------------------------------------------------------------
hdr "2. DRM devices"
# ---------------------------------------------------------------------------
nv_card=""
for c in /sys/class/drm/card[0-9]*; do
    [ -e "$c" ] || continue
    cdrv="$(basename "$(readlink -f "${c}/device/driver" 2>/dev/null)" 2>/dev/null || echo '?')"
    printf '          %-8s -> %s\n' "$(basename "$c")" "$cdrv"
    [ "$cdrv" = "nvidia" ] && nv_card="$(basename "$c")"
done
if [ -n "$nv_card" ]; then
    ok "NVIDIA registered a DRM device (${nv_card})"
else
    bad "no DRM card bound to the nvidia driver -- minigbm has nothing to allocate on"
fi

# Confirm a display is actually connected and lit on the NVIDIA card.
if [ -n "$nv_card" ]; then
    connected=0
    for conn in /sys/class/drm/${nv_card}-*/status; do
        [ -e "$conn" ] || continue
        if [ "$(cat "$conn" 2>/dev/null)" = "connected" ]; then
            connected=1
            printf '          connected: %s\n' "$(basename "$(dirname "$conn")")"
        fi
    done
    [ "$connected" -eq 1 ] && ok "a monitor is connected to the RTX" \
                           || bad "no connected output on the RTX. Attach a monitor to the card."
fi

# ---------------------------------------------------------------------------
hdr "3. minigbm has an nvidia-drm backend"
# ---------------------------------------------------------------------------
# The patched minigbm registers a backend named "nvidia-drm". Without it, Chrome cannot
# allocate buffers on this device.
mg="$(find /usr/lib64 /usr/lib -maxdepth 1 -name 'libgbm.so*' -print -quit 2>/dev/null)"
if [ -n "$mg" ]; then
    if strings "$mg" 2>/dev/null | grep -qx 'nvidia-drm'; then
        ok "minigbm contains the nvidia-drm backend ($(basename "$mg"))"
    else
        bad "minigbm has no nvidia-drm backend string.
          The patch in patches/minigbm/ is not in this image."
    fi
else
    note "could not locate libgbm to inspect"
fi

# ---------------------------------------------------------------------------
hdr "4. EGL / GBM / Vulkan vendor configuration"
# ---------------------------------------------------------------------------
for f in /usr/share/glvnd/egl_vendor.d/10_nvidia.json \
         /usr/share/egl/egl_external_platform.d/15_nvidia_gbm.json \
         /usr/share/vulkan/icd.d/nvidia_icd.json; do
    [ -f "$f" ] && ok "$(basename "$f") installed" || bad "missing ${f}"
done

for l in libnvidia-egl-gbm.so.1 libEGL_nvidia.so.0 libnvidia-allocator.so.1; do
    if find /usr/lib64 /usr/lib -maxdepth 2 -name "$l" -print -quit 2>/dev/null | grep -q .; then
        ok "${l} present"
    else
        bad "${l} missing"
    fi
done

gbm_backend="$(find /usr/lib64/gbm /usr/lib/gbm -name 'nvidia-drm_gbm.so' -print -quit 2>/dev/null)"
[ -n "$gbm_backend" ] && ok "GBM backend linked at ${gbm_backend}" \
                      || bad "no nvidia-drm_gbm.so in the GBM backend directory"

# ---------------------------------------------------------------------------
hdr "5. Is Chrome actually using the GPU? (the important bit)"
# ---------------------------------------------------------------------------
# A GPU process holding the NVIDIA device node is the strongest available evidence.
if command -v fuser >/dev/null 2>&1; then
    holders="$(fuser /dev/nvidia0 2>/dev/null | tr -s ' ')"
    if [ -n "$holders" ]; then
        ok "processes have /dev/nvidia0 open:${holders}"
        for p in $holders; do
            [ -r "/proc/${p}/comm" ] && printf '          %s -> %s\n' "$p" "$(cat "/proc/${p}/comm")"
        done
    else
        bad "nothing has /dev/nvidia0 open. Chrome is not rendering on the NVIDIA GPU
          (almost certainly fell back to software rendering)."
    fi
fi

# Cross-check with the driver's own client accounting.
if command -v nvidia-smi >/dev/null 2>&1; then
    if nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader 2>/dev/null | grep -qv '^ *0 *%, *0'; then
        ok "GPU reports non-zero utilisation/memory: $(nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader 2>/dev/null)"
    else
        note "GPU utilisation and memory are both ~0; nothing is rendering on it yet"
    fi
fi

# ---------------------------------------------------------------------------
hdr "6. Software-rendering fallback detection"
# ---------------------------------------------------------------------------
# SwiftShader or llvmpipe in the Chrome logs means the NVIDIA path failed.
CHROME_LOG=/var/log/chrome/chrome
if [ -r "$CHROME_LOG" ]; then
    if grep -qi 'swiftshader\|llvmpipe\|software rendering' "$CHROME_LOG" 2>/dev/null; then
        bad "Chrome logs mention software rendering:"
        grep -i 'swiftshader\|llvmpipe\|software rendering' "$CHROME_LOG" 2>/dev/null | tail -3 | sed 's/^/          /'
    else
        ok "no software-rendering fallback in the Chrome log"
    fi
    if grep -qi 'eglInitialize.*fail\|failed to create.*gbm\|no usable.*gbm' "$CHROME_LOG" 2>/dev/null; then
        bad "EGL/GBM initialisation errors in the Chrome log:"
        grep -i 'eglInitialize.*fail\|failed to create.*gbm\|no usable.*gbm' "$CHROME_LOG" 2>/dev/null | tail -3 | sed 's/^/          /'
    fi
else
    note "no readable Chrome log at ${CHROME_LOG}"
fi

# ---------------------------------------------------------------------------
hdr "7. GPU health"
# ---------------------------------------------------------------------------
xids="$(dmesg 2>/dev/null | grep -c 'NVRM.*Xid' || true)"
[ "${xids:-0}" -eq 0 ] && ok "no Xid errors" || bad "${xids} Xid error(s) in dmesg"

if [ -x /usr/share/chromiumos-nvidia-cross/gpu-guard.sh ]; then
    status gpu-guard 2>/dev/null | grep -q running && ok "gpu-guard running" \
        || note "gpu-guard not running -- start it before Stage 4 gaming load"
fi

# ---------------------------------------------------------------------------
printf '\n================================================================\n'
if [ "$FAIL" -eq 0 ]; then
    printf '  STAGE 3 GATE PASSED (%d warning(s))\n' "$WARN"
    printf '================================================================\n'
    cat <<'EOF'

The ChromeOS UI is compositing on the RTX. Next, Stage 4:

  steam/container/setup-steam-container.sh

Note that dumb buffers are linear and unaccelerated. If the UI feels sluggish that is
expected at this point, and is what libnvidia-allocator work addresses.
EOF
    exit 0
fi
printf '  STAGE 3 GATE FAILED (%d failure(s), %d warning(s))\n' "$FAIL" "$WARN"
printf '================================================================\n'
cat <<'EOF'

This is the hardest stage; a failure here is expected at least once. Diagnostics:

  grep -iE 'ozone|gbm|egl|drm' /var/log/chrome/chrome | tail -40
  EGL_LOG_LEVEL=debug VK_LOADER_DEBUG=all restart ui
  dmesg | grep -iE 'nvrm|nvidia-drm'

If the display is black, you still have the iGPU console -- that is why Stage 2 kept it.
To retreat, set modeset=0 in /etc/modprobe.d/nvidia-modeset-off.conf and reboot.
EOF
exit 1
