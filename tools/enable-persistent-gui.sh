#!/bin/bash
# Install persistent every-boot RTX→Ash GUI bring-up + Gaia-off hooks.
# No one-shot auto-debug flag — just make normal boots reach login UI.
#
#   sudo ./tools/enable-persistent-gui.sh /dev/nvme1n1
#
# Then boot ChromiumOS repeatedly: pink splash → Ash login each time.
# Create localuser via http://127.0.0.1:17891/ — Gaia disable runs automatically.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEV="${1:-}"

if [ "$(id -u)" -ne 0 ]; then
  echo "re-run as root: sudo $0 ${DEV:-/dev/nvme1n1}" >&2
  exit 1
fi

if [ -z "$DEV" ]; then
  for d in /dev/nvme1n1 /dev/nvme0n1 /dev/sdc; do
    [ -b "$d" ] || continue
    if lsblk -npo LABEL,PARTLABEL "$d" 2>/dev/null | grep -qE 'H-STATE|^STATE' &&
       lsblk -npo LABEL,PARTLABEL "$d" 2>/dev/null | grep -q ROOT-A; then
      DEV="$d"
      break
    fi
  done
fi
[ -n "$DEV" ] || { echo "pass ChromiumOS disk" >&2; lsblk -o NAME,LABEL,PARTLABEL >&2; exit 1; }

echo "=== enable persistent GUI on ${DEV} ==="
"${REPO_ROOT}/tools/copy-sbin-scripts-to-disk.sh" "$DEV"

# Ensure we are NOT leaving a stale auto-debug flag that would stop ui.
label_of() {
  local l
  l=$(lsblk -no LABEL "$1" 2>/dev/null | sed '/^$/d' | head -n1)
  [ -n "$l" ] && { printf '%s\n' "$l"; return; }
  lsblk -no PARTLABEL "$1" 2>/dev/null | sed '/^$/d' | head -n1
}
STATE=""
shopt -s nullglob
for part in "${DEV}"p* "${DEV}"[0-9]*; do
  [ -b "$part" ] || continue
  case "$(label_of "$part")" in
    STATE|H-STATE) STATE="$part" ;;
  esac
done
shopt -u nullglob

if [ -n "$STATE" ]; then
  MNT="$(mktemp -d /tmp/enable-gui-XXXXXX)"
  mount -o rw "$STATE" "$MNT"
  rm -f "$MNT/unencrypted/nvidia-auto-debug" \
        "$MNT/unencrypted/nvidia-hold-ui" 2>/dev/null || true
  # Marker so humans know persistent mode is armed.
  mkdir -p "$MNT/unencrypted"
  date -u +%Y-%m-%dT%H:%M:%SZ > "$MNT/unencrypted/nvidia-gui-persistent.enabled"
  umount "$MNT"
  rmdir "$MNT"
  echo "cleared auto-debug/hold-ui flags; wrote nvidia-gui-persistent.enabled"
fi

cat <<EOF

OK — persistent GUI installed on ${DEV}

Boot ChromiumOS (no arm-nvidia-auto-debug needed):
  pink splash → Ash login every boot

Local account (on device):
  http://127.0.0.1:17891/  → set password for localuser@localhost
  (auto-runs disable-gaia-after-local-account)

Optional diagnose later:
  sudo ./tools/arm-nvidia-auto-debug.sh ${DEV}

EOF
