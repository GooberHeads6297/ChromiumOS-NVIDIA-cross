#!/bin/bash
# tools/confirm-auth-image.sh -- verify the built test image contains auth packaging.
#
# Host-side (Ubuntu). Does not need the ChromiumOS device. Uses cgpt + debugfs on a
# extracted ROOT-A slice when possible.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "${REPO_ROOT}/safety/lib-common.sh"

BOARD=nvidia-generic
CROS_CHECKOUT="${CROS_CHECKOUT:-${HOME}/chromiumos}"
IMG="${CROS_CHECKOUT}/src/build/images/${BOARD}/latest/chromiumos_test_image.bin"
WORK="${TMPDIR:-/tmp}/confirm-auth-image.$$"

while [ $# -gt 0 ]; do
    case "$1" in
        --board) BOARD="${2:?}"; shift
                 IMG="${CROS_CHECKOUT}/src/build/images/${BOARD}/latest/chromiumos_test_image.bin" ;;
        --image) IMG="${2:?}"; shift ;;
        -h|--help) sed -n '1,16p' "$0"; exit 0 ;;
        *) die "unknown arg: $1" ;;
    esac
    shift
done

[ -f "$IMG" ] || die "image not found: ${IMG}
Build with: ./tools/rebuild-auth-image.sh"

command -v cgpt >/dev/null 2>&1 || die "cgpt required"
command -v debugfs >/dev/null 2>&1 || die "debugfs required (e2fsprogs)"

banner "confirm auth packaging in $(basename "$IMG")"

# ROOT-A is partition 3 on ChromeOS GPT layouts used here.
START="$(cgpt show -i 3 -b "$IMG")"
SIZE="$(cgpt show -i 3 -s "$IMG")"
[ -n "$START" ] && [ -n "$SIZE" ] || die "could not read ROOT-A from GPT"

mkdir -p "$WORK"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

ROOT_IMG="${WORK}/root-a.img"
log "extracting ROOT-A (start=${START} size=${SIZE} sectors) — may take a minute"
dd if="$IMG" of="$ROOT_IMG" bs=512 skip="$START" count="$SIZE" status=progress 2>&1 | tail -n 3

FAIL=0
check_path() {
    local p="$1"
    if debugfs -R "stat ${p}" "$ROOT_IMG" >/dev/null 2>&1; then
        printf '  [ OK ]  %s\n' "$p"
    else
        printf '  [FAIL]  %s\n' "$p"
        FAIL=$(( FAIL + 1 ))
    fi
}

check_path /usr/sbin/create-local-account.sh
check_path /usr/sbin/register-local-login.sh
check_path /usr/sbin/ensure-software-tpm.sh
check_path /usr/sbin/collect-auth-debug.sh
check_path /usr/sbin/verify-local-account.sh
check_path /usr/sbin/verify-auth-bringup.sh
check_path /usr/sbin/verify-crostini-host.sh
check_path /usr/sbin/install-to-disk.sh
check_path /usr/share/chromiumos-nvidia-cross/limits.conf
check_path /usr/share/chromiumos-nvidia-cross/local-account-setup.py
check_path /usr/share/chromiumos-nvidia-cross/local-account-ext/manifest.json
check_path /etc/init/local-account-setup.conf
check_path /usr/share/chromiumos-nvidia-cross/chrome_dev.conf.auth

if [ "$FAIL" -eq 0 ]; then
    banner "PASS — nvidia-generic-auth is in the image"
    log "Flash: ./tools/flash.sh --board ${BOARD} --target usb --device /dev/sdc"
    exit 0
fi
banner "FAIL — ${FAIL} path(s) missing"
log "Run: ./tools/rebuild-auth-image.sh --flash /dev/sdc"
exit 1
