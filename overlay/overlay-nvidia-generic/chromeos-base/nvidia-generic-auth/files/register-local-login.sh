#!/bin/bash
# register-local-login.sh -- make a cryptohome user appear on the Chrome login pods.
#
# Cryptohome vaults created by create-local-account.sh do NOT register with Chrome.
# Chrome only shows users listed in /home/chronos/Local State. Without that, you
# get Get Started / Guest forever even though /home/.shadow has a vault.
#
# Usage (as root, after create-local-account.sh):
#   register-local-login.sh --user localuser@localhost
#   restart ui    # or reboot

set -euo pipefail

USER_EMAIL=""
die() { echo "error: $*" >&2; exit 1; }
log() { echo "[local-login] $*"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --user) USER_EMAIL="${2:?}"; shift ;;
        -h|--help) sed -n '1,16p' "$0"; exit 0 ;;
        *) die "unknown arg: $1" ;;
    esac
    shift
done

[ -n "$USER_EMAIL" ] || die "required: --user EMAIL"
command -v python3 >/dev/null 2>&1 || die "python3 required"

DISPLAY_NAME="${USER_EMAIL%@*}"
[ -n "$DISPLAY_NAME" ] || DISPLAY_NAME="$USER_EMAIL"

log "stopping ui so Chrome releases Local State"
stop ui 2>/dev/null || true
sleep 2

install -d -o chronos -g chronos -m 0755 /home/chronos
touch /home/chronos/.oobe_completed
chown chronos:chronos /home/chronos/.oobe_completed

export USER_EMAIL DISPLAY_NAME
python3 - <<'PY'
import json, os, pathlib

email = os.environ["USER_EMAIL"]
name = os.environ["DISPLAY_NAME"]
path = pathlib.Path("/home/chronos/Local State")

data = {}
if path.exists() and path.stat().st_size > 0:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        bak = path.with_suffix(".state.bak")
        path.replace(bak)
        data = {}

def as_dict(key):
    v = data.get(key)
    if not isinstance(v, dict):
        data[key] = {}
    return data[key]

data["OobeComplete"] = True
data["DeviceRegistered"] = True

users = data.get("LoggedInUsers")
if not isinstance(users, list):
    users = []
if email not in users:
    users.append(email)
data["LoggedInUsers"] = users
data["LastLoggedInRegularUser"] = email
data["LastActiveUser"] = email

as_dict("UserDisplayEmail")[email] = email
as_dict("UserDisplayName")[email] = name
as_dict("UserGivenName")[email] = name
# user_manager::UserType::USER_TYPE_REGULAR == 0
as_dict("UserType")[email] = 0
as_dict("UserForceOnlineSignin")[email] = False

path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
os.chown(path, 1000, 1000)  # chronos uid/gid on ChromeOS images
os.chmod(path, 0o600)
print("[local-login] wrote", path, "users=", data["LoggedInUsers"])
PY

# chronos is not always uid 1000; prefer chown by name
chown chronos:chronos "/home/chronos/Local State" /home/chronos/.oobe_completed 2>/dev/null || true

log "starting ui"
start ui 2>/dev/null || true
log "OK — login pod should list ${USER_EMAIL}. Do not click Create local account → Next."
