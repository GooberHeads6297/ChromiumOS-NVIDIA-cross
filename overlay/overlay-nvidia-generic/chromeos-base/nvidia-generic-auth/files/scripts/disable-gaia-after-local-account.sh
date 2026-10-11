#!/bin/sh
# Ensure Gaia stays off after a local account is created (CLI or :17891 UI).
#
#   disable-gaia-after-local-account.sh [user@localhost]
#
# - Merges --disable-gaia-services / offline login flags into chrome_dev.conf
# - Registers the Chrome login pod (Local State)
# - Soft-restarts ui so Ash picks up the password pod
set -eu

USER_EMAIL="${1:-localuser@localhost}"
CONF=/etc/chrome_dev.conf
AUTH_FRAG=/usr/share/chromiumos-nvidia-cross/chrome_dev.conf.auth
MARKER_DIR=/var/lib/nvidia-generic-auth
DONE="${MARKER_DIR}/gaia-disabled.done"
LOG=/mnt/stateful_partition/unencrypted/disable-gaia.log

mkdir -p "$MARKER_DIR" /mnt/stateful_partition/unencrypted 2>/dev/null || true
mount -o remount,rw / 2>/dev/null || true

log() {
  echo "[disable-gaia] $*"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >>"$LOG" 2>/dev/null || true
  logger -t disable-gaia -- "$*" 2>/dev/null || true
}

ensure_flag() {
  flag=$1
  [ -f "$CONF" ] || touch "$CONF"
  if grep -qF -- "$flag" "$CONF" 2>/dev/null; then
    return 0
  fi
  printf '%s\n' "$flag" >>"$CONF"
  log "added $flag"
}

log "start user=${USER_EMAIL}"

# Packaged auth fragment (idempotent line merge).
if [ -f "$AUTH_FRAG" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|\#*) continue ;;
      --*|!--*)
        # Strip leading ! comment-disable form if present for matching.
        bare=$line
        case "$bare" in
          !--*) bare=${bare#!} ;;
        esac
        ensure_flag "$bare"
        ;;
    esac
  done <"$AUTH_FRAG"
fi

# Hard guarantees even if fragment missing.
ensure_flag "--disable-gaia-services"
ensure_flag "--oobe-skip-to-login"
ensure_flag "--skip-force-online-signin-for-testing"
ensure_flag "--allow-failed-policy-fetch-for-test"

if [ -x /usr/sbin/register-local-login.sh ]; then
  log "register-local-login.sh --user ${USER_EMAIL}"
  /usr/sbin/register-local-login.sh --user "${USER_EMAIL}" || \
    log "WARN register-local-login failed"
else
  log "WARN register-local-login.sh missing"
fi

printf '%s\n' "${USER_EMAIL}" >"$DONE"
log "marker $DONE"

# Reload login UI so the password pod appears (safe on login/OOBE screen).
if status ui 2>/dev/null | grep -q start/running; then
  log "restarting ui for Local State / gaia flags"
  stop ui 2>/dev/null || true
  sleep 1
  start ui 2>/dev/null || true
fi

log "done"
exit 0
