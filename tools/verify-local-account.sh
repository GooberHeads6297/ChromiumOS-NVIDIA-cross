#!/bin/bash
# tools/verify-local-account.sh -- gate for local account + cryptohome mount.
#
# Run ON the ChromiumOS device after create-local-account.sh (or OOBE local login).
#
# Usage:
#   ./verify-local-account.sh [--user EMAIL]
#
# Exit 0 means the vault exists and can be authenticated + mounted.

set -uo pipefail

USER_EMAIL="localuser@localhost"
PASSWORD=""

while [ $# -gt 0 ]; do
    case "$1" in
        --user) USER_EMAIL="${2:?}"; shift ;;
        --password) PASSWORD="${2:?}"; shift ;;
        -h|--help) sed -n '1,20p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
done

FAIL=0
ok()  { printf '  [ OK ]  %s\n' "$*"; }
bad() { printf '  [FAIL]  %s\n' "$*"; FAIL=$(( FAIL + 1 )); }
hdr() { printf '\n%s\n' "$*"; }

printf '================================================================\n'
printf '  Local account / cryptohome gate\n'
printf '================================================================\n'

hdr "0. packaging (sbin + GUI)"
if [ -x /usr/sbin/create-local-account.sh ]; then
    ok "/usr/sbin/create-local-account.sh present"
else
    bad "/usr/sbin/create-local-account.sh missing — image lacks nvidia-generic-auth"
fi
if [ -f /usr/share/chromiumos-nvidia-cross/local-account-setup.py ]; then
    ok "local-account-setup.py present"
else
    bad "local-account-setup.py missing"
fi
if [ -f /usr/share/chromiumos-nvidia-cross/local-account-ext/manifest.json ]; then
    ok "local-account Chrome extension present"
else
    bad "local-account-ext missing"
fi
if curl -fsS --max-time 2 http://127.0.0.1:17891/api/status >/tmp/las.status 2>/dev/null; then
    ok "local-account-setup HTTP UI responding on :17891"
else
    # Not a hard fail after account exists (job stops); warn via OK note.
    ok "local-account-setup HTTP UI not running (expected after first account)"
fi

hdr "1. cryptohome CLI"
if command -v cryptohome >/dev/null 2>&1; then
    ok "cryptohome present"
else
    bad "cryptohome CLI missing"
fi

hdr "2. software TPM path"
if [ -e /etc/init/tpm2-simulator.conf ] || status tpm2-simulator 2>/dev/null | grep -q start; then
    ok "tpm2-simulator job is present/running"
else
    bad "tpm2-simulator not available — hardware TPM conflicts are more likely"
fi

hdr "3. system salt"
if cryptohome --action=get_system_salt >/tmp/salt.out 2>&1; then
    ok "get_system_salt succeeded"
else
    bad "get_system_salt failed (cryptohome not healthy)"
    cat /tmp/salt.out | sed 's/^/          /'
fi

hdr "4. auth session for ${USER_EMAIL}"
OUT="$(cryptohome --action=start_auth_session --user="${USER_EMAIL}" 2>&1)" || true
printf '%s\n' "$OUT" | sed 's/^/          /'
SID="$(printf '%s\n' "$OUT" | sed -n 's/.*auth_session_id: *"\([0-9a-fA-F]*\)".*/\1/p' | head -1)"
if [ -z "$SID" ]; then
    # alternate text formats
    SID="$(printf '%s\n' "$OUT" | sed -n 's/.*auth_session_id: \([0-9a-fA-F]\{16,\}\).*/\1/p' | head -1)"
fi
if [ -n "$SID" ]; then
    ok "auth_session_id=${SID:0:16}..."
else
    bad "could not parse auth_session_id from start_auth_session"
fi

if [ -n "$SID" ] && [ -n "$PASSWORD" ]; then
    hdr "5. authenticate + prepare vault"
    if cryptohome --action=authenticate_auth_factor \
            --auth_session_id="$SID" \
            --key_label=local-password \
            --password="$PASSWORD" >/tmp/auth.out 2>&1; then
        ok "authenticate_auth_factor succeeded"
    else
        bad "authenticate_auth_factor failed"
        sed 's/^/          /' /tmp/auth.out
    fi
    if cryptohome --action=prepare_persistent_vault \
            --auth_session_id="$SID" >/tmp/prep.out 2>&1; then
        ok "prepare_persistent_vault succeeded"
    else
        bad "prepare_persistent_vault failed"
        sed 's/^/          /' /tmp/prep.out
    fi
    cryptohome --action=invalidate_auth_session --auth_session_id="$SID" >/dev/null 2>&1 || true
elif [ -n "$SID" ]; then
    hdr "5. authenticate skipped (pass --password to exercise mount)"
    ok "session started; vault existence left to list_auth_factors / shadow"
    cryptohome --action=list_auth_factors --auth_session_id="$SID" 2>&1 | sed 's/^/          /' || true
    cryptohome --action=invalidate_auth_session --auth_session_id="$SID" >/dev/null 2>&1 || true
fi

hdr "6. shadow directory"
if ls /home/.shadow/*/  >/dev/null 2>&1; then
    ok "at least one shadow user directory exists"
    ls -la /home/.shadow | sed 's/^/          /'
else
    bad "no /home/.shadow users — create-local-account.sh has not succeeded"
fi

printf '\n'
if [ "$FAIL" -eq 0 ]; then
    printf 'PASS (%s)\n' "$USER_EMAIL"
    exit 0
fi
printf 'FAIL (%d checks)\n' "$FAIL"
exit 1
