#!/bin/bash
# tools/rebuild-auth-image.sh -- emerge auth/BSP + rebuild test image (+ optional flash).
#
# Bakes: DRM ACL 0660 video, nvidia-drm modeset=1 fbdev=1, blacklist simpledrm,
# --disable-gpu-sandbox, and an Upstart job that unbinds fbcon DRM master before ui.
# Does not rebuild chromeos-chrome or minigbm.
#
# Requires an interactive terminal (cros_sdk / sudo). From the repo root:
#   ./tools/rebuild-auth-image.sh
#   ./tools/rebuild-auth-image.sh --flash /dev/sdc

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "${REPO_ROOT}/safety/lib-common.sh"

BOARD=nvidia-generic
FLASH_DEV=""
CROS_CHECKOUT="${CROS_CHECKOUT:-${HOME}/chromiumos}"

while [ $# -gt 0 ]; do
    case "$1" in
        --board) BOARD="${2:?}"; shift ;;
        --flash) FLASH_DEV="${2:?}"; shift ;;
        -h|--help) sed -n '1,12p' "$0"; exit 0 ;;
        *) die "unknown arg: $1" ;;
    esac
    shift
done

is_root && die "do not run as root"

banner "link overlay"
"${REPO_ROOT}/sdk/build.sh" --board "$BOARD" link

banner "emerge auth stack (package + login_manager + USE flags)"
export PATH="${PATH}:${HOME}/depot_tools"
cd "$CROS_CHECKOUT"
# cros_sdk collapses newlines inside bash -c; keep this as one semicolon-separated line
# (no # comments — they glue onto the previous token when newlines are stripped).
cros_sdk -- bash -c "set -euo pipefail; emerge-${BOARD} -v chromeos-base/chromeos-bsp-nvidia-generic chromeos-base/nvidia-generic-auth virtual/chromeos-bsp; emerge-${BOARD} -v chromeos-base/chromeos-login; emerge-${BOARD} -v chromeos-base/libchromeos-use-flags || true"
# chromeos-chrome Ozone nvidia-drm preference is tools/rebuild-display-image.sh (hours).

banner "build test image"
"${REPO_ROOT}/sdk/build.sh" --board "$BOARD" image

banner "confirm auth paths inside image"
"${REPO_ROOT}/tools/confirm-auth-image.sh" --board "$BOARD"

if [ -n "$FLASH_DEV" ]; then
    banner "flash ${FLASH_DEV}"
    "${REPO_ROOT}/tools/flash.sh" --board "$BOARD" --target usb --device "$FLASH_DEV"
    log "Boot the USB, then see docs/LOCAL-ACCOUNTS.md"
    log "  GUI:  http://127.0.0.1:17891/"
    log "  CLI:  create-local-account.sh --user localuser@localhost --password '...'"
else
    log "Image ready. Flash with:"
    log "  ./tools/flash.sh --board ${BOARD} --target usb --device /dev/sdc"
fi
