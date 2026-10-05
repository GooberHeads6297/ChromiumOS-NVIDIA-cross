#!/bin/bash
# create-local-account.sh -- create a password-protected cryptohome via AuthSession.
#
# Installed on-device at /usr/sbin/create-local-account.sh
#
# Correct AuthSession order (matches platform2 CreateTestUser + vault mount):
#   StartAuthSession -> CreatePersistentUser -> AddAuthFactor(password)
#   -> PreparePersistentVault -> Unmount / InvalidateAuthSession
#
# Do NOT run this while a Guest session is active. Sign out of Guest first
# (or reboot), then use VT2 as root.

set -euo pipefail

USER_EMAIL=""
PASSWORD=""
KEY_LABEL="local-password"
KEEP_MOUNTED=0
FORCE_REMOVE=0

die() { echo "error: $*" >&2; exit 1; }
log() { echo "[local-account] $*"; }

usage() {
    sed -n '1,25p' "$0"
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --user) USER_EMAIL="${2:?}"; shift ;;
        --password) PASSWORD="${2:?}"; shift ;;
        --key-label) KEY_LABEL="${2:?}"; shift ;;
        --keep-mounted) KEEP_MOUNTED=1 ;;
        --force-remove) FORCE_REMOVE=1 ;;
        -h|--help) usage ;;
        *) die "unknown arg: $1" ;;
    esac
    shift
done

[ -n "$USER_EMAIL" ] || die "required: --user EMAIL (e.g. localuser@localhost)"
command -v cryptohome >/dev/null 2>&1 || die "cryptohome CLI missing"

if [ -z "$PASSWORD" ]; then
    if [ -t 0 ]; then
        printf 'Password for %s: ' "$USER_EMAIL"
        stty -echo
        IFS= read -r PASSWORD
        stty echo
        printf '\n'
    else
        die "required: --password (or run interactively)"
    fi
fi
[ -n "$PASSWORD" ] || die "empty password not allowed"

parse_auth_session_id() {
    local out="$1" sid=""
    sid="$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*auth_session_id: *"\([0-9a-fA-F]\{16,\}\)"[[:space:]]*$/\1/p' | head -1)"
    if [ -z "$sid" ]; then
        sid="$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*auth_session_id: \([0-9a-fA-F]\{16,\}\)[[:space:]]*$/\1/p' | head -1)"
    fi
    if [ -z "$sid" ] && command -v python3 >/dev/null 2>&1; then
        sid="$(printf '%s\n' "$out" | python3 -c '
import re, sys
text = sys.stdin.read()
m = re.search(r"auth_session_id:\s*\"((?:\\.|[^\"])*)\"", text)
if not m:
    sys.exit(0)
raw = bytes(m.group(1), "utf-8").decode("unicode_escape").encode("latin1")
print(raw.hex())
')"
    fi
    printf '%s' "$sid"
}

run_step() {
    local desc="$1"; shift
    log "$desc"
    local out rc=0
    out="$("$@" 2>&1)" || rc=$?
    printf '%s\n' "$out" | sed 's/^/  | /'
    # cryptohome often prints CRYPTOHOME_ERROR_NOT_SET on success
    if [ "$rc" -ne 0 ] || printf '%s' "$out" | grep -qiE 'CRYPTOHOME_ERROR_(MOUNT|INVALID|ACCOUNT|KEY|TPM|AUTH)_'; then
        if printf '%s' "$out" | grep -qi 'CRYPTOHOME_ERROR_NOT_SET' && \
           ! printf '%s' "$out" | grep -qiE 'CRYPTOHOME_ERROR_(MOUNT|INVALID|ACCOUNT_EXISTS|KEY|TPM|AUTH)_'; then
            return 0
        fi
        return 1
    fi
    return 0
}

log "checking cryptohome health"
cryptohome --action=get_system_salt >/dev/null 2>&1 || \
    die "get_system_salt failed — run ensure-software-tpm.sh"

log "unmount any Guest / other vaults (required before creating a persistent user)"
cryptohome --action=unmount 2>&1 | sed 's/^/  | /' || true
sleep 1

if [ "$FORCE_REMOVE" -eq 1 ]; then
    log "removing existing vault for ${USER_EMAIL} (--force-remove)"
    cryptohome --action=remove --user="${USER_EMAIL}" 2>&1 | sed 's/^/  | /' || true
fi

log "StartAuthSession for ${USER_EMAIL}"
START_OUT="$(cryptohome --action=start_auth_session --user="${USER_EMAIL}" 2>&1)" || \
    die "start_auth_session failed:
${START_OUT}"
printf '%s\n' "$START_OUT" | sed 's/^/  | /'
SID="$(parse_auth_session_id "$START_OUT")"
[ -n "$SID" ] || die "could not parse auth_session_id"

cleanup() {
    cryptohome --action=invalidate_auth_session --auth_session_id="$SID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if ! run_step "CreatePersistentUser" \
        cryptohome --action=create_persistent_user --auth_session_id="$SID"; then
    die "create_persistent_user failed (user may already exist — try --force-remove)"
fi

if ! run_step "AddAuthFactor (password)" \
        cryptohome --action=add_auth_factor \
            --auth_session_id="$SID" \
            --key_label="${KEY_LABEL}" \
            --password="${PASSWORD}"; then
    die "add_auth_factor failed"
fi

if ! run_step "PreparePersistentVault" \
        cryptohome --action=prepare_persistent_vault --auth_session_id="$SID"; then
    die "prepare_persistent_vault failed.
Sign out of Guest completely (or reboot), then:
  cryptohome --action=unmount
  create-local-account.sh --force-remove --user ${USER_EMAIL} --password '...'
Also check: tail -100 /var/log/cryptohomed.log"
fi

if [ "$KEEP_MOUNTED" -eq 0 ]; then
    log "Unmount"
    cryptohome --action=unmount 2>&1 | sed 's/^/  | /' || true
fi

trap - EXIT
cryptohome --action=invalidate_auth_session --auth_session_id="$SID" >/dev/null 2>&1 || true

log "OK — created cryptohome for ${USER_EMAIL}"
ls -la /home/.shadow 2>/dev/null | sed 's/^/  | /' || true

if [ -x /usr/sbin/register-local-login.sh ]; then
    log "registering ${USER_EMAIL} with Chrome login (Get Started skip)"
    /usr/sbin/register-local-login.sh --user "${USER_EMAIL}" || \
        log "WARN: register-local-login.sh failed — run it by hand"
else
    log "register-local-login.sh not installed; Chrome will still show Get Started"
    log "until you register the user in /home/chronos/Local State"
fi
