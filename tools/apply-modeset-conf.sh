#!/bin/bash
# tools/apply-modeset-conf.sh -- ship modeset=1 without rebuilding nvidia.ko.
#
# The -r2 emerge recompiles the open modules and currently dies on missing
# stdarg.h (conftest did not set NV_LINUX_STDARG_H_PRESENT). The .ko files from
# -r1 are already good; only /etc/modprobe.d needs to change for dual-output.
#
# This updates the installed -r1 package in the nvidia-generic sysroot, refreshes
# its binary package, and rebuilds the disk image. Run from an interactive shell:
#   ./tools/apply-modeset-conf.sh
#   ./tools/apply-modeset-conf.sh --flash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "${REPO_ROOT}/safety/lib-common.sh"

CROS_CHECKOUT="${CROS_CHECKOUT:-${HOME}/chromiumos}"
DEPOT_TOOLS_DIR="${DEPOT_TOOLS_DIR:-${HOME}/depot_tools}"
export PATH="${PATH}:${DEPOT_TOOLS_DIR}"
DO_FLASH=0
[ "${1:-}" = "--flash" ] && DO_FLASH=1

is_root && die "do not run as root"

SRC_CONF="${REPO_ROOT}/overlay/overlay-nvidia-generic/x11-drivers/nvidia-open-drivers/files/nvidia-modeset.conf"
[ -f "$SRC_CONF" ] || die "missing ${SRC_CONF}"
grep -q 'modeset=1' "$SRC_CONF" || die "${SRC_CONF} does not enable modeset=1"

SYSROOT="${CROS_CHECKOUT}/out/build/nvidia-generic"
MODDIR="${SYSROOT}/etc/modprobe.d"
VDB="${SYSROOT}/var/db/pkg/x11-drivers/nvidia-open-drivers-595.91.07-r1"
[ -d "$VDB" ] || die "nvidia-open-drivers -r1 is not installed in the sysroot; cannot patch it"

if ! sudo -n true 2>/dev/null; then
  [ -t 0 ] || die "sudo needs a password; run from an interactive shell"
  sudo -v || die "sudo failed"
fi

banner "install dual-output modeset conf into sysroot"
sudo mkdir -p "$MODDIR"
sudo cp -f "$SRC_CONF" "${MODDIR}/nvidia-modeset.conf"
sudo rm -f "${MODDIR}/nvidia-modeset-off.conf"
# Keep CONTENTS accurate so quickpkg / image packing see the new file.
if [ -f "${VDB}/CONTENTS" ]; then
  sudo sed -i '/nvidia-modeset-off.conf/d' "${VDB}/CONTENTS"
  if ! grep -q 'nvidia-modeset.conf' "${VDB}/CONTENTS"; then
    sum="$(md5sum "${MODDIR}/nvidia-modeset.conf" | awk '{print $1}')"
    ts="$(stat -c %Y "${MODDIR}/nvidia-modeset.conf")"
    printf 'obj /etc/modprobe.d/nvidia-modeset.conf %s %s\n' "$sum" "$ts" \
      | sudo tee -a "${VDB}/CONTENTS" >/dev/null
  fi
fi

log "sysroot now has:"
ls -l "${MODDIR}/nvidia"* 
grep -E 'modeset|fbdev' "${MODDIR}/nvidia-modeset.conf"

banner "quickpkg nvidia-open-drivers"
(
  cd "$CROS_CHECKOUT"
  ./chromite/bin/cros_sdk -- sudo PKGDIR=/build/nvidia-generic/packages \
    ROOT=/build/nvidia-generic quickpkg --include-config=y \
    'x11-drivers/nvidia-open-drivers'
) || die "quickpkg failed"

banner "build image"
"${REPO_ROOT}/sdk/build.sh" --board nvidia-generic image || die "build-image failed"

IMG="${CROS_CHECKOUT}/src/build/images/nvidia-generic/latest/chromiumos_test_image.bin"
[ -f "$IMG" ] || die "no image at ${IMG}"
log "image ready: ${IMG}"

if [ "$DO_FLASH" -eq 1 ]; then
  banner "flash USB /dev/sdc"
  "${REPO_ROOT}/tools/flash.sh" --board nvidia-generic --target usb --device /dev/sdc \
    || die "flash failed"
fi

banner "done"
cat <<EOF
Skipped rebuilding nvidia.ko (that is the stdarg.h failure). Only the modprobe
conf changed. After boot:
  cat /sys/module/nvidia_drm/parameters/modeset   # Y or 1
  cat /sys/module/nvidia_drm/parameters/fbdev     # Y or 1
EOF
