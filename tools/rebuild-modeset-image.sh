#!/bin/bash
# tools/rebuild-modeset-image.sh -- rebuild nvidia-open-drivers -r2 and the image.
#
# Dual-output bring-up: modeset=1 fbdev=1. Run from an interactive terminal so sudo
# can prompt. Usage:
#   ./tools/rebuild-modeset-image.sh
#   ./tools/rebuild-modeset-image.sh --flash   # also write /dev/sdc

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "${REPO_ROOT}/safety/lib-common.sh"

CROS_CHECKOUT="${CROS_CHECKOUT:-${HOME}/chromiumos}"
DEPOT_TOOLS_DIR="${DEPOT_TOOLS_DIR:-${HOME}/depot_tools}"
export PATH="${PATH}:${DEPOT_TOOLS_DIR}"
DO_FLASH=0
[ "${1:-}" = "--flash" ] && DO_FLASH=1

is_root && die "do not run as root; cros_sdk sudoes for itself"

# Prefer an interactive terminal so sudo can prompt. If sudo is already primed
# (or SUDO_ASKPASS works), continue without a tty.
if ! sudo -n true 2>/dev/null; then
  if [ -t 0 ]; then
    log "priming sudo"
    sudo -v || die "sudo failed"
  else
    die "sudo needs a password and stdin is not a terminal.
     Run from an interactive shell, or prime with:  sudo -v"
  fi
else
  log "sudo already authenticated"
fi

# Keep the ticket alive across the long emerge + image.
( while true; do sudo -n true 2>/dev/null || exit 0; sleep 50; done ) &
KEEP=$!
trap 'kill '"$KEEP"' 2>/dev/null || true' EXIT

banner "link overlay"
"${REPO_ROOT}/sdk/build.sh" --board nvidia-generic link || die "link failed"

banner "emerge nvidia-open-drivers-595.91.07-r2"
(
  cd "$CROS_CHECKOUT"
  ./chromite/bin/cros_sdk -- emerge-nvidia-generic -v '=x11-drivers/nvidia-open-drivers-595.91.07-r2'
) || die "emerge failed"

banner "quickpkg so build-image has a binary"
(
  cd "$CROS_CHECKOUT"
  ./chromite/bin/cros_sdk -- sudo PKGDIR=/build/nvidia-generic/packages \
    ROOT=/build/nvidia-generic quickpkg --include-config=y \
    'x11-drivers/nvidia-open-drivers'
) || die "quickpkg failed"

CONF="${CROS_CHECKOUT}/out/build/nvidia-generic/etc/modprobe.d/nvidia-modeset.conf"
if [ -f "$CONF" ] && grep -q 'modeset=1' "$CONF"; then
  log "sysroot has nvidia-modeset.conf with modeset=1"
else
  die "sysroot missing expected nvidia-modeset.conf with modeset=1"
fi
OFF="${CROS_CHECKOUT}/out/build/nvidia-generic/etc/modprobe.d/nvidia-modeset-off.conf"
if [ -e "$OFF" ]; then
  warn "stale nvidia-modeset-off.conf still present; removing it from the sysroot"
  # May already be root-owned from emerge.
  if [ -w "$(dirname "$OFF")" ]; then
    rm -f "$OFF"
  else
    sudo rm -f "$OFF"
  fi
fi

banner "build image"
"${REPO_ROOT}/sdk/build.sh" --board nvidia-generic image || die "build-image failed"
IMG="${CROS_CHECKOUT}/src/build/images/nvidia-generic/latest/chromiumos_test_image.bin"
[ -f "$IMG" ] || die "no test image at ${IMG}"
log "image ready: ${IMG}"

if [ "$DO_FLASH" -eq 1 ]; then
  banner "flash USB /dev/sdc"
  "${REPO_ROOT}/tools/flash.sh" --board nvidia-generic --target usb --device /dev/sdc \
    || die "flash failed"
fi

banner "done"
cat <<EOF
Next:
  BIOS primary = iGPU. Monitor 1 = motherboard, Monitor 2 = RTX. Boot the USB stick.
  On device:
    cat /sys/module/nvidia_drm/parameters/modeset   # Y or 1
    cat /sys/module/nvidia_drm/parameters/fbdev     # Y or 1
    lspci -k -s 0d:00.0                            # amdgpu
    lspci -k -s 01:00.0                            # nvidia
EOF
