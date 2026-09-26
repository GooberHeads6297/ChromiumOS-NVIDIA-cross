#!/bin/bash
# tools/verify-stage2.sh -- the Stage 2 gate. Run this ON the ChromiumOS device.
#
# Stage 2 asks one question: does the NVIDIA driver load completely, while the display
# is still owned by the iGPU?
#
# Passing means the kernel module, the GSP firmware and the userspace libraries all
# agree and the GPU is fully usable for compute, with the console still guaranteed by
# amdgpu. That is the safest checkpoint in the project: everything about the driver is
# proven before anything about the display is risked.
#
# Get it onto the device with (from the build host):
#   scp tools/verify-stage2.sh root@<device>:/tmp/     # test image password: test0000
#   ssh root@<device> /tmp/verify-stage2.sh
#
# Exit 0 means proceed to Stage 3.

set -uo pipefail

FAIL=0
WARN=0

ok()   { printf '  [ OK ]  %s\n' "$*"; }
bad()  { printf '  [FAIL]  %s\n' "$*"; FAIL=$(( FAIL + 1 )); }
note() { printf '  [WARN]  %s\n' "$*"; WARN=$(( WARN + 1 )); }
hdr()  { printf '\n%s\n' "$*"; }

EXPECT_PCI_ID="10de:2705"
EXPECT_NAME="NVIDIA GeForce RTX 4070 Ti SUPER"
EXPECT_VERSION="595.91.07"
IGPU_ADDR="0000:0d:00.0"
GPU_ADDR="0000:01:00.0"

printf '================================================================\n'
printf '  Stage 2 gate: driver loads, display stays on the iGPU\n'
printf '================================================================\n'

# ---------------------------------------------------------------------------
hdr "1. Hardware enumeration"
# ---------------------------------------------------------------------------
if [ -d "/sys/bus/pci/devices/${GPU_ADDR}" ]; then
    ok "GPU present at ${GPU_ADDR}"
else
    bad "no PCI device at ${GPU_ADDR}"
fi

drv="$(basename "$(readlink -f "/sys/bus/pci/devices/${GPU_ADDR}/driver" 2>/dev/null)" 2>/dev/null || echo none)"
case "$drv" in
    nvidia)  ok "GPU bound to the 'nvidia' driver" ;;
    nouveau) bad "GPU bound to 'nouveau'. That is the diagnostic fallback, not the target.
          Check /etc/modprobe.d/nvidia.conf blacklists nouveau." ;;
    none)    bad "GPU has no driver bound. Try: modprobe nvidia; then dmesg | grep -i nvidia" ;;
    *)       bad "GPU bound to unexpected driver '${drv}'" ;;
esac

# ---------------------------------------------------------------------------
hdr "2. Kernel modules"
# ---------------------------------------------------------------------------
for m in nvidia nvidia_modeset nvidia_uvm; do
    if lsmod 2>/dev/null | grep -q "^${m} "; then
        ok "${m} loaded"
    else
        bad "${m} not loaded"
    fi
done

# nvidia_drm is expected to be loaded but NOT driving a display in Stage 2.
if lsmod 2>/dev/null | grep -q '^nvidia_drm '; then
    ok "nvidia_drm loaded"
    ms="$(cat /sys/module/nvidia_drm/parameters/modeset 2>/dev/null || echo '?')"
    case "$ms" in
        N|0) ok "nvidia_drm modeset=${ms} -- correct for Stage 2 (no display handover yet)" ;;
        Y|1) note "nvidia_drm modeset=${ms}. That is Stage 3 configuration, not Stage 2.
          Fine if deliberate, but this gate is meant to pass with modesetting off." ;;
        *)   note "could not read nvidia_drm modeset parameter" ;;
    esac
else
    note "nvidia_drm not loaded (acceptable in Stage 2; required for Stage 3)"
fi

# ---------------------------------------------------------------------------
hdr "3. Device nodes"
# ---------------------------------------------------------------------------
# Missing nodes with a loaded module is the classic ChromeOS trap: no nvidia-modprobe
# runs setuid here, so udev has to create them (99-nvidia-dev.rules).
for d in /dev/nvidiactl /dev/nvidia0; do
    if [ -e "$d" ]; then
        ok "${d} exists"
    else
        bad "${d} missing. The module may be loaded but nodes were never created --
          check that 99-nvidia-dev.rules is installed and udev ran."
    fi
done
[ -e /dev/nvidia-uvm ] && ok "/dev/nvidia-uvm exists" || note "/dev/nvidia-uvm missing (needed for CUDA and some Vulkan paths)"

# ---------------------------------------------------------------------------
hdr "4. GSP firmware"
# ---------------------------------------------------------------------------
fw="/lib/firmware/nvidia/${EXPECT_VERSION}/gsp_ga10x.bin"
if [ -f "$fw" ]; then
    ok "GSP firmware present ($(du -h "$fw" 2>/dev/null | cut -f1))"
else
    bad "missing ${fw}. Ada cannot initialise without the GSP image."
fi

if dmesg 2>/dev/null | grep -qi 'gsp.*fail\|failed to load firmware'; then
    bad "dmesg reports a GSP firmware load failure:"
    dmesg 2>/dev/null | grep -i 'gsp.*fail\|failed to load firmware' | tail -3 | sed 's/^/          /'
fi

# ---------------------------------------------------------------------------
hdr "5. nvidia-smi -- the real test"
# ---------------------------------------------------------------------------
if ! command -v nvidia-smi >/dev/null 2>&1; then
    bad "nvidia-smi not installed"
else
    if out="$(nvidia-smi --query-gpu=name,driver_version,vbios_version,temperature.gpu,power.draw --format=csv,noheader 2>&1)"; then
        ok "nvidia-smi communicates with the driver"
        printf '          %s\n' "$out"

        name="$(printf '%s' "$out" | cut -d, -f1 | sed 's/^ *//;s/ *$//')"
        ver="$(printf '%s' "$out" | cut -d, -f2 | tr -d ' ')"
        [ "$name" = "$EXPECT_NAME" ] && ok "card identified as ${EXPECT_NAME}" \
                                     || bad "card reports '${name}', expected '${EXPECT_NAME}'"
        [ "$ver" = "$EXPECT_VERSION" ] && ok "driver version ${ver} matches the pin" \
                                       || bad "driver version ${ver}, expected ${EXPECT_VERSION}"
    else
        bad "nvidia-smi failed: ${out}"
        printf '          This usually means one of:\n'
        printf '            - device nodes missing (see section 3)\n'
        printf '            - kernel module / userspace version mismatch\n'
        printf '            - GSP firmware absent or the wrong version\n'
    fi
fi

# ---------------------------------------------------------------------------
hdr "6. Display ownership -- must still be the iGPU"
# ---------------------------------------------------------------------------
igpu_drv="$(basename "$(readlink -f "/sys/bus/pci/devices/${IGPU_ADDR}/driver" 2>/dev/null)" 2>/dev/null || echo none)"
if [ "$igpu_drv" = "amdgpu" ]; then
    ok "iGPU bound to amdgpu -- the console is safe"
else
    bad "iGPU driver is '${igpu_drv}', expected amdgpu. The recovery console is not guaranteed."
fi

# In Stage 2 the only DRM card should be the iGPU's.
if [ -d /sys/class/drm ]; then
    for c in /sys/class/drm/card[0-9]*; do
        [ -e "$c" ] || continue
        cdrv="$(basename "$(readlink -f "${c}/device/driver" 2>/dev/null)" 2>/dev/null || echo '?')"
        printf '          %s -> %s\n' "$(basename "$c")" "$cdrv"
    done
fi

# ---------------------------------------------------------------------------
hdr "7. Errors worth knowing about"
# ---------------------------------------------------------------------------
xids="$(dmesg 2>/dev/null | grep -c 'NVRM.*Xid' || true)"
if [ "${xids:-0}" -gt 0 ]; then
    bad "${xids} Xid error(s) in dmesg -- the GPU reported a fault:"
    dmesg 2>/dev/null | grep 'NVRM.*Xid' | tail -3 | sed 's/^/          /'
else
    ok "no Xid errors in dmesg"
fi

if dmesg 2>/dev/null | grep -qi 'nvrm.*version mismatch'; then
    bad "kernel module / userspace version mismatch reported in dmesg"
fi

aer="$(dmesg 2>/dev/null | grep -ci 'pcieport.*AER\|severity=Corrected' || true)"
[ "${aer:-0}" -gt 20 ] && note "${aer} PCIe AER messages; check riser/slot seating if this grows"

# ---------------------------------------------------------------------------
hdr "8. Watchdog"
# ---------------------------------------------------------------------------
if [ -x /usr/share/chromiumos-nvidia-cross/gpu-guard.sh ]; then
    ok "gpu-guard installed"
    if status gpu-guard 2>/dev/null | grep -q running; then
        ok "gpu-guard running"
    else
        note "gpu-guard not running. Start it before applying any GPU load: start gpu-guard"
    fi
else
    note "gpu-guard not installed on this image"
fi

# ---------------------------------------------------------------------------
printf '\n================================================================\n'
if [ "$FAIL" -eq 0 ]; then
    printf '  STAGE 2 GATE PASSED (%d warning(s))\n' "$WARN"
    printf '================================================================\n'
    cat <<'EOF'

The driver is fully loaded and the console is still on the iGPU. This is the
checkpoint worth pausing at -- everything about the driver is now proven.

To proceed to Stage 3 (hand the display to the RTX):
  1. Edit /etc/modprobe.d/nvidia-modeset-off.conf -> options nvidia-drm modeset=1 fbdev=1
  2. Ensure the patched minigbm with the nvidia-drm backend is in the image
  3. Attach a monitor to the RTX, and keep one on the iGPU as a fallback
  4. Reboot, then run tools/verify-stage3.sh
EOF
    exit 0
fi
printf '  STAGE 2 GATE FAILED (%d failure(s), %d warning(s))\n' "$FAIL" "$WARN"
printf '================================================================\n'
cat <<'EOF'

Do not enable modesetting until this passes. Useful next commands:
  dmesg | grep -i -E 'nvrm|nvidia|gsp'
  modprobe -v nvidia
  nvidia-smi -q | head -40
EOF
exit 1
