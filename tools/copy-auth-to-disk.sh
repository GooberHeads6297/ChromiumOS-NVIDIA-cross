#!/bin/bash
# Copy local-account helpers + Gaia-offline login prefs onto a ChromiumOS disk
# without rebuilding the image.
#
#   sudo ./tools/copy-auth-to-disk.sh /dev/nvme0n1
#   sudo ./tools/copy-auth-to-disk.sh /dev/sdc
#
# Updates every ROOT-A partition, STATE/H-STATE (/usr/local + Local State),
# and merges chrome_dev.conf flags for offline password login.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUTH_FILES="${REPO_ROOT}/overlay/overlay-nvidia-generic/chromeos-base/nvidia-generic-auth/files"
DEV="${1:-/dev/nvme0n1}"
USER_EMAIL="${LOCAL_USER_EMAIL:-localuser@localhost}"

if [ "$(id -u)" -ne 0 ]; then
    echo "re-run as root: sudo $0 ${DEV}" >&2
    exit 1
fi

[ -b "$DEV" ] || { echo "not a block device: $DEV" >&2; exit 1; }
[ -d "$AUTH_FILES" ] || { echo "missing $AUTH_FILES" >&2; exit 1; }

for f in create-local-account.sh register-local-login.sh verify-local-account.sh \
         ensure-software-tpm.sh local-account-setup.py chrome_dev.conf.auth \
         chrome_dev.conf.display chrome-nvidia-egl ui.override; do
    [ -f "${AUTH_FILES}/${f}" ] || { echo "missing ${AUTH_FILES}/${f}" >&2; exit 1; }
done

label_of() {
    local l
    l=$(lsblk -no LABEL "$1" 2>/dev/null | sed '/^$/d' | head -n1)
    if [ -n "$l" ]; then
        printf '%s\n' "$l"
        return
    fi
    lsblk -no PARTLABEL "$1" 2>/dev/null | sed '/^$/d' | head -n1
}

MNT="$(mktemp -d /tmp/cros-auth-XXXXXX)"
cleanup() {
    umount "$MNT" 2>/dev/null || true
    rmdir "$MNT" 2>/dev/null || true
}
trap cleanup EXIT

mount_rw() {
    local part="$1"
    umount "$MNT" 2>/dev/null || true
    if ! mount -o rw "$part" "$MNT"; then
        echo "retrying ${part} with noload" >&2
        mount -o rw,noload "$part" "$MNT"
    fi
}

merge_chrome_dev() {
    local conf="$1"
    local auth_src="${AUTH_FILES}/chrome_dev.conf.auth"
    local disp_src="${AUTH_FILES}/chrome_dev.conf.display"
    touch "$conf"
    # Drop known-bad login extension line if present.
    sed -i '/local-account-ext/d' "$conf" 2>/dev/null || true

    ensure_flag() {
        local flag="$1"
        grep -qF -- "$flag" "$conf" 2>/dev/null || printf '%s\n' "$flag" >> "$conf"
    }

    if ! grep -qF '# nvidia-generic-auth chrome flags' "$conf" 2>/dev/null; then
        {
            printf '\n# nvidia-generic-auth chrome flags\n'
            cat "$auth_src"
        } >> "$conf"
    else
        # Fragment already present — still ensure the critical offline flags.
        ensure_flag '--disable-gaia-services'
        ensure_flag '--oobe-skip-to-login'
        ensure_flag '--allow-failed-policy-fetch-for-test'
        ensure_flag '--skip-force-online-signin-for-testing'
    fi

    if ! grep -qF '# nvidia-generic-auth display flags v6' "$conf" 2>/dev/null; then
        sed -i '/# nvidia-generic-auth display flags v3/,/^--ignore-gpu-blocklist$/d' "$conf" 2>/dev/null || true
        sed -i '/# nvidia-generic-auth display flags v4/,/^--disable-features=Vulkan$/d' "$conf" 2>/dev/null || true
        sed -i '/# nvidia-generic-auth display flags v4/,/^--ignore-gpu-blocklist$/d' "$conf" 2>/dev/null || true
        sed -i '/# nvidia-generic-auth display flags v5/,/^--ignore-gpu-blocklist$/d' "$conf" 2>/dev/null || true
        sed -i '/^__EGL_VENDOR_LIBRARY_DIRS=/d' "$conf" 2>/dev/null || true
        sed -i '/^__EGL_VENDOR_LIBRARY_FILENAMES=/d' "$conf" 2>/dev/null || true
        {
            printf '\n# nvidia-generic-auth display flags v6\n'
            cat "$disp_src"
        } >> "$conf"
    fi
    grep -qF -- '__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json' "$conf" 2>/dev/null || \
        printf '%s\n' '__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json' >> "$conf"
    ensure_flag '--disable-gpu-sandbox'
    ensure_flag '--skip-force-online-signin-for-testing'

    install -m 0644 "$auth_src" \
        "${MNT}/usr/share/chromiumos-nvidia-cross/chrome_dev.conf.auth"
    install -m 0644 "$disp_src" \
        "${MNT}/usr/share/chromiumos-nvidia-cross/chrome_dev.conf.display"
    if [ -f "${AUTH_FILES}/nvidia-generic-auth-chrome.conf" ] && [ -d "${MNT}/etc/init" ]; then
        install -m 0644 "${AUTH_FILES}/nvidia-generic-auth-chrome.conf" \
            "${MNT}/etc/init/nvidia-generic-auth-chrome.conf"
    fi
    if [ -d "${MNT}/etc/init" ]; then
        install -m 0644 "${AUTH_FILES}/ui.override" "${MNT}/etc/init/ui.override"
    fi
    if [ -f "${AUTH_FILES}/chrome-nvidia-egl" ]; then
        install -m 0755 "${AUTH_FILES}/chrome-nvidia-egl" \
            "${MNT}/usr/sbin/chrome-nvidia-egl"
    fi
}

patch_local_state() {
    local path="$1"
    local email="$2"
    [ -f "$path" ] || {
        echo "  (no Local State yet at ${path} — will be written on first register)"
        return 0
    }
    USER_EMAIL="$email" LOCAL_STATE_PATH="$path" python3 - <<'PY'
import json, os, pathlib
email = os.environ["USER_EMAIL"]
path = pathlib.Path(os.environ["LOCAL_STATE_PATH"])
data = json.loads(path.read_text(encoding="utf-8"))

def as_dict(key):
    v = data.get(key)
    if not isinstance(v, dict):
        data[key] = {}
    return data[key]

name = email.split("@", 1)[0] or email
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
as_dict("UserType")[email] = 0
as_dict("UserForceOnlineSignin")[email] = False
as_dict("OAuthTokenStatus")[email] = 4  # OAUTH2_TOKEN_STATUS_VALID
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
print("  patched Local State oauth=4 force_online=False for", email)
PY
    chown 1000:1000 "$path" 2>/dev/null || true
    chmod 600 "$path" 2>/dev/null || true
}

copy_sbin() {
    local dest="$1"
    mkdir -p "$dest" "${MNT}/usr/share/chromiumos-nvidia-cross"
    for f in create-local-account.sh register-local-login.sh verify-local-account.sh \
             ensure-software-tpm.sh collect-auth-debug.sh verify-auth-bringup.sh \
             verify-crostini-host.sh chrome-nvidia-egl; do
        [ -f "${AUTH_FILES}/${f}" ] || continue
        install -m 0755 "${AUTH_FILES}/${f}" "${dest}/${f}"
    done
    install -m 0755 "${AUTH_FILES}/local-account-setup.py" \
        "${MNT}/usr/share/chromiumos-nvidia-cross/local-account-setup.py"
    # Prefer /usr/sbin helper name used by Upstart job.
    if [ -d "${MNT}/usr/sbin" ]; then
        mkdir -p "${MNT}/usr/sbin/scripts"
        if [ -f "${AUTH_FILES}/scripts/enable-nvidia-egl.sh" ]; then
            install -m 0755 "${AUTH_FILES}/scripts/enable-nvidia-egl.sh" \
                "${MNT}/usr/sbin/scripts/enable-nvidia-egl.sh"
        fi
        install -m 0755 "${AUTH_FILES}/local-account-setup.py" \
            "${MNT}/usr/sbin/local-account-setup.py" 2>/dev/null || true
    fi
    ls -l "${dest}/create-local-account.sh" "${dest}/register-local-login.sh"
}

echo "target ${DEV}"
ROOTS=()
STATE=""
shopt -s nullglob
for part in "${DEV}"p* "${DEV}"[0-9]* "${DEV}"*; do
    [ -b "$part" ] || continue
    case "$(label_of "$part")" in
        ROOT-A|ROOT-B) ROOTS+=("$part") ;;
        STATE|H-STATE) STATE="$part" ;;
    esac
done
shopt -u nullglob
if [ "${#ROOTS[@]}" -gt 0 ]; then
    mapfile -t ROOTS < <(printf '%s\n' "${ROOTS[@]}" | awk 'NF && !seen[$0]++')
fi

[ "${#ROOTS[@]}" -ge 1 ] || { echo "no ROOT-A partitions on ${DEV}" >&2; exit 1; }
[ -n "$STATE" ] || { echo "no STATE/H-STATE on ${DEV}" >&2; exit 1; }

for root in "${ROOTS[@]}"; do
    echo
    echo "=== ${root} (ROOT-A) ==="
    mount_rw "$root"
    copy_sbin "${MNT}/usr/sbin"
    merge_chrome_dev "${MNT}/etc/chrome_dev.conf"
    echo "  chrome_dev.conf flags:"
    grep -E 'disable-gaia|skip-force-online|oobe-skip|disable-gpu-sandbox|chrome-nvidia-egl|10_nvidia|50_mesa|VENDOR_LIBRARY_DIRS' \
        "${MNT}/etc/chrome_dev.conf" | sed 's/^/    /' || true
    echo "  wrapper: $(ls -l "${MNT}/usr/sbin/chrome-nvidia-egl" 2>/dev/null || echo missing)"
    echo "  ui.override: $(ls -l "${MNT}/etc/init/ui.override" 2>/dev/null || echo missing)"
    sync
    umount "$MNT"
done

echo
echo "=== ${STATE} (stateful) ==="
mount_rw "$STATE"
mkdir -p "${MNT}/dev_image/sbin" "${MNT}/home/chronos"
copy_sbin "${MNT}/dev_image/sbin"
# local-account-setup lives under /usr on rootfs; also keep a copy for /usr/local
install -m 0755 "${AUTH_FILES}/local-account-setup.py" \
    "${MNT}/dev_image/sbin/local-account-setup.py"
patch_local_state "${MNT}/home/chronos/Local State" "$USER_EMAIL"
touch "${MNT}/home/chronos/.oobe_completed"
chown 1000:1000 "${MNT}/home/chronos/.oobe_completed" 2>/dev/null || true
sync
umount "$MNT"

echo
echo "done. Reboot ChromiumOS from ${DEV}, then either:"
echo "  http://127.0.0.1:17891/   # set password (AuthFactor local-password)"
echo "or:"
echo "  create-local-account.sh --force-remove --user ${USER_EMAIL} --password '...' --key-label local-password"
echo "Login pod should show a password field (not Google verification)."
