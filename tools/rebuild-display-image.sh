#!/bin/bash
# tools/rebuild-display-image.sh -- everything needed for Ash on the RTX.
#
# minigbm nvidia-drm backend + BSP (0666 DRM nodes, fbcon master release) +
# auth flags. The GBM "Permission denied (13)" is a stale errno from
# gbm_create_device() failing on a missing backend, so minigbm is the real fix.
#
#   ./tools/rebuild-display-image.sh --minigbm-only
#   ./tools/rebuild-display-image.sh --minigbm-only --flash /dev/sdc
#
# Add Ozone nvidia-drm preference + legacy KMS (atomic TEST_ONLY fails on NVIDIA):
#   ./tools/rebuild-display-image.sh --with-chrome --flash /dev/sdc
#
# Default is --minigbm-only (does not emerge chromeos-chrome).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "${REPO_ROOT}/safety/lib-common.sh"

BOARD=nvidia-generic
FLASH_DEV=""
CROS_CHECKOUT="${CROS_CHECKOUT:-${HOME}/chromiumos}"
WITH_CHROME=0

while [ $# -gt 0 ]; do
    case "$1" in
        --board) BOARD="${2:?}"; shift ;;
        --flash) FLASH_DEV="${2:?}"; shift ;;
        --minigbm-only) WITH_CHROME=0 ;;
        --with-chrome) WITH_CHROME=1 ;;
        -h|--help) sed -n '1,16p' "$0"; exit 0 ;;
        *) die "unknown arg: $1" ;;
    esac
    shift
done

is_root && die "do not run as root"

banner "link overlay (applies minigbm nvidia-drm + ozone patches)"
"${REPO_ROOT}/sdk/build.sh" --board "$BOARD" link

export PATH="${PATH}:${HOME}/depot_tools"
cd "$CROS_CHECKOUT"

# /build/$BOARD inside the SDK is out/build/$BOARD on the host, so verify here
# rather than inside bash -c. minigbm installs libminigbm.so.1.0.0 and symlinks
# libgbm.so* to it; there is no libminigbm.so.1.
verify_minigbm_backend() {
    local sysroot so found=0
    for sysroot in "${CROS_CHECKOUT}/out/build/${BOARD}" \
                   "${CROS_CHECKOUT}/chroot/build/${BOARD}"; do
        [ -d "$sysroot" ] || continue
        found=1
        for so in "${sysroot}/usr/lib64/libminigbm.so."* \
                  "${sysroot}/usr/lib/libminigbm.so."*; do
            [ -f "$so" ] || continue
            if grep -aF 'nvidia-drm' "$so" >/dev/null 2>&1; then
                log "nvidia-drm backend present in ${so}"
                return 0
            fi
            warn "no nvidia-drm backend in ${so}"
        done
    done
    [ "$found" -eq 1 ] || die "no board sysroot found under ${CROS_CHECKOUT}"
    die "libminigbm has no nvidia-drm backend.
     Chrome then fails with 'Couldn't create Gbm Device' plus a stale errno
     that reads as Permission denied. Confirm media-libs/minigbm-0.0.1-r810
     is the version that emerged."
}

banner "emerge overlay minigbm r810 (applies nvidia-drm backend to pinned r809)"
cros_sdk -- bash -c "set -euo pipefail; emerge-${BOARD} -v =media-libs/minigbm-0.0.1-r810"
verify_minigbm_backend

banner "emerge BSP + auth + login_manager"
cros_sdk -- bash -c "set -euo pipefail; emerge-${BOARD} -v chromeos-base/chromeos-bsp-nvidia-generic chromeos-base/nvidia-generic-auth virtual/chromeos-bsp; emerge-${BOARD} -v chromeos-base/chromeos-login; emerge-${BOARD} -v chromeos-base/libchromeos-use-flags || true"

if [ "$WITH_CHROME" -eq 1 ]; then
    banner "emerge chromeos-chrome from local chrome_root (hours)"
    CHROME_SRC_ROOT="${CROS_CHECKOUT}/chrome_root"
    [ -f "${CHROME_SRC_ROOT}/src/ui/ozone/platform/drm/common/drm_wrapper.cc" ] || \
        die "chrome_root missing drm_wrapper.cc at ${CHROME_SRC_ROOT}"
    grep -q 'forcing legacy KMS' \
        "${CHROME_SRC_ROOT}/src/ui/ozone/platform/drm/common/drm_wrapper.cc" || \
        die "ozone nvidia legacy-KMS patch is not in ${CHROME_SRC_ROOT}
     Run: ${REPO_ROOT}/sdk/build.sh --board ${BOARD} link"
    cros_sdk --chrome-root="${CHROME_SRC_ROOT}" -- bash -c \
        "set -euo pipefail; export CHROME_ORIGIN=LOCAL_SOURCE; export CHROME_ROOT=/mnt/host/source/chrome_root; emerge-${BOARD} -v chromeos-base/chromeos-chrome"
else
    log "skipping chromeos-chrome (pass --with-chrome to rebuild Ozone/NVIDIA KMS)"
fi

banner "build test image"
"${REPO_ROOT}/sdk/build.sh" --board "$BOARD" image

banner "confirm auth paths inside image"
"${REPO_ROOT}/tools/confirm-auth-image.sh" --board "$BOARD"

if [ -n "$FLASH_DEV" ]; then
    banner "flash ${FLASH_DEV}"
    "${REPO_ROOT}/tools/flash.sh" --board "$BOARD" --target usb --device "$FLASH_DEV"
    log "Boot USB. Setup UI: http://127.0.0.1:17891/"
else
    log "Image ready. Flash with:"
    log "  ./tools/flash.sh --board ${BOARD} --target usb --device /dev/sdc"
fi
