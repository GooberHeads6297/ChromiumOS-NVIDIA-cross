#!/bin/bash
# tools/verify-auth-bringup.sh -- USB / NVMe local-account bring-up checklist.
#
# Run ON the ChromiumOS device (USB live or installed NVMe).
#
# Usage:
#   ./verify-auth-bringup.sh --phase usb --user localuser@localhost --password '...'
#   ./verify-auth-bringup.sh --phase nvme --user localuser@localhost --password '...'
#
# phase=usb  : packaging + create path (expects you already created or will create)
# phase=nvme : same checks after install-to-disk (account must be recreated on NVMe)

set -uo pipefail

PHASE="usb"
USER_EMAIL="localuser@localhost"
PASSWORD=""

while [ $# -gt 0 ]; do
    case "$1" in
        --phase) PHASE="${2:?}"; shift ;;
        --user) USER_EMAIL="${2:?}"; shift ;;
        --password) PASSWORD="${2:?}"; shift ;;
        -h|--help) sed -n '1,20p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done

case "$PHASE" in usb|nvme) ;; *) echo "phase must be usb|nvme" >&2; exit 2 ;; esac

ROOT="$(cd "$(dirname "$0")" && pwd)"
VERIFY=""
for cand in \
    /usr/share/chromiumos-nvidia-cross/verify-local-account.sh \
    "${ROOT}/verify-local-account.sh" \
    /tmp/verify-local-account.sh; do
    if [ -x "$cand" ]; then VERIFY="$cand"; break; fi
done

printf '================================================================\n'
printf '  Auth bring-up (%s)\n' "$PHASE"
printf '================================================================\n'

if [ "$PHASE" = "nvme" ]; then
    echo "NOTE: NVMe stateful is fresh after install-to-disk."
    echo "      USB-created users do NOT exist here — create again first."
fi

FAIL=0
if [ -x /usr/sbin/create-local-account.sh ]; then
    echo "  [ OK ]  /usr/sbin/create-local-account.sh"
else
    echo "  [FAIL]  /usr/sbin/create-local-account.sh missing"
    FAIL=$(( FAIL + 1 ))
fi

if [ -n "$VERIFY" ]; then
    if [ -n "$PASSWORD" ]; then
        "$VERIFY" --user "$USER_EMAIL" --password "$PASSWORD" || FAIL=$(( FAIL + 1 ))
    else
        "$VERIFY" --user "$USER_EMAIL" || FAIL=$(( FAIL + 1 ))
    fi
else
    echo "  [FAIL]  verify-local-account.sh not found"
    FAIL=$(( FAIL + 1 ))
fi

if [ "$FAIL" -eq 0 ]; then
    echo "PASS ($PHASE)"
    exit 0
fi
echo "FAIL ($PHASE) — see docs/LOCAL-ACCOUNTS.md"
exit 1
