#!/bin/bash
# Install sbin scripts, GBM/AddFB shims, persistent GUI bring-up, Gaia hooks.
#
#   sudo ./tools/copy-sbin-scripts-to-disk.sh /dev/nvme1n1
#   sudo ./tools/enable-persistent-gui.sh /dev/nvme1n1   # preferred for daily boots
#
# Applies (offline, no restart ui):
#   /usr/sbin/scripts/debug.sh
#   /usr/sbin/scripts/enable-nvidia-egl.sh
#   /usr/sbin/scripts/create-nvidia-nodes.sh
#   /usr/sbin/chrome-nvidia-egl   (dual GLVND: nvidia + mesa)
#   /etc/init/ui.override
#   restore 50_mesa.json on ROOT-A
#   strip --use-gl=egl from chrome_dev.conf

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUTH_FILES="${REPO_ROOT}/overlay/overlay-nvidia-generic/chromeos-base/nvidia-generic-auth/files"
BSP_FILES="${REPO_ROOT}/overlay/overlay-nvidia-generic/chromeos-base/chromeos-bsp-nvidia-generic/files"

pick_cros_disk() {
    local d
    for d in /dev/nvme0n1 /dev/nvme1n1 /dev/sda /dev/sdb; do
        [ -b "$d" ] || continue
        if lsblk -npo LABEL,PARTLABEL "$d" 2>/dev/null | grep -qE 'H-STATE|^STATE' &&
           lsblk -npo LABEL,PARTLABEL "$d" 2>/dev/null | grep -q ROOT-A; then
            printf '%s\n' "$d"
            return 0
        fi
    done
    return 1
}

if [ "${1:-}" != "" ]; then
    DEV="$1"
else
    DEV="$(pick_cros_disk)" || {
        echo "pass the ChromiumOS disk (has ROOT-A + H-STATE), e.g. /dev/nvme1n1" >&2
        lsblk -o NAME,LABEL,PARTLABEL >&2
        exit 1
    }
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "re-run as root: sudo $0 ${DEV}" >&2
    exit 1
fi
[ -b "$DEV" ] || { echo "not a block device: $DEV" >&2; exit 1; }
[ -f "${AUTH_FILES}/scripts/debug.sh" ] || {
    echo "missing ${AUTH_FILES}/scripts/debug.sh" >&2
    exit 1
}
[ -f "${AUTH_FILES}/scripts/enable-nvidia-egl.sh" ] || {
    echo "missing ${AUTH_FILES}/scripts/enable-nvidia-egl.sh" >&2
    exit 1
}
[ -f "${AUTH_FILES}/chrome-nvidia-egl" ] || {
    echo "missing ${AUTH_FILES}/chrome-nvidia-egl" >&2
    exit 1
}
[ -f "${AUTH_FILES}/ui.override" ] || {
    echo "missing ${AUTH_FILES}/ui.override" >&2
    exit 1
}

label_of() {
    local l
    l=$(lsblk -no LABEL "$1" 2>/dev/null | sed '/^$/d' | head -n1)
    if [ -n "$l" ]; then
        printf '%s\n' "$l"
        return
    fi
    lsblk -no PARTLABEL "$1" 2>/dev/null | sed '/^$/d' | head -n1
}

MNT="$(mktemp -d /tmp/cros-sbin-scripts-XXXXXX)"
cleanup() {
    umount "$MNT" 2>/dev/null || true
    rmdir "$MNT" 2>/dev/null || true
}
trap cleanup EXIT

apply_root() {
    local dest_scripts="${MNT}/usr/sbin/scripts"
    mkdir -p "$dest_scripts" "${MNT}/etc/init" \
        "${MNT}/usr/share/chromiumos-nvidia-cross/scripts"
    install -m 0755 "${AUTH_FILES}/scripts/debug.sh" \
        "${dest_scripts}/debug.sh"
    install -m 0755 "${AUTH_FILES}/scripts/enable-nvidia-egl.sh" \
        "${dest_scripts}/enable-nvidia-egl.sh"
    install -m 0755 "${AUTH_FILES}/scripts/create-nvidia-nodes.sh" \
        "${dest_scripts}/create-nvidia-nodes.sh"
    if [ -f "${AUTH_FILES}/scripts/capture-chrome-logs.sh" ]; then
        install -m 0755 "${AUTH_FILES}/scripts/capture-chrome-logs.sh" \
            "${dest_scripts}/capture-chrome-logs.sh"
    fi
    if [ -f "${AUTH_FILES}/scripts/nvidia-gui-bringup.sh" ]; then
        install -m 0755 "${AUTH_FILES}/scripts/nvidia-gui-bringup.sh" \
            "${dest_scripts}/nvidia-gui-bringup.sh"
    fi
    if [ -f "${AUTH_FILES}/scripts/disable-gaia-after-local-account.sh" ]; then
        install -m 0755 "${AUTH_FILES}/scripts/disable-gaia-after-local-account.sh" \
            "${dest_scripts}/disable-gaia-after-local-account.sh"
    fi
    # Flat sbin names from the ebuild (CrOS QA forbids /usr/sbin/scripts in image).
    install -m 0755 "${AUTH_FILES}/scripts/debug.sh" \
        "${MNT}/usr/sbin/nvidia-generic-debug"
    install -m 0755 "${AUTH_FILES}/scripts/enable-nvidia-egl.sh" \
        "${MNT}/usr/sbin/enable-nvidia-egl"
    install -m 0755 "${AUTH_FILES}/scripts/create-nvidia-nodes.sh" \
        "${MNT}/usr/sbin/create-nvidia-nodes"
    if [ -f "${AUTH_FILES}/scripts/capture-chrome-logs.sh" ]; then
        install -m 0755 "${AUTH_FILES}/scripts/capture-chrome-logs.sh" \
            "${MNT}/usr/sbin/capture-chrome-logs"
    fi
    if [ -f "${AUTH_FILES}/scripts/nvidia-gui-bringup.sh" ]; then
        install -m 0755 "${AUTH_FILES}/scripts/nvidia-gui-bringup.sh" \
            "${MNT}/usr/sbin/nvidia-gui-bringup"
    fi
    if [ -f "${AUTH_FILES}/scripts/disable-gaia-after-local-account.sh" ]; then
        install -m 0755 "${AUTH_FILES}/scripts/disable-gaia-after-local-account.sh" \
            "${MNT}/usr/sbin/disable-gaia-after-local-account"
    fi
    if [ -f "${AUTH_FILES}/create-local-account.sh" ]; then
        install -m 0755 "${AUTH_FILES}/create-local-account.sh" \
            "${MNT}/usr/sbin/create-local-account.sh"
    fi
    if [ -f "${AUTH_FILES}/local-account-setup.py" ]; then
        mkdir -p "${MNT}/usr/share/chromiumos-nvidia-cross"
        install -m 0755 "${AUTH_FILES}/local-account-setup.py" \
            "${MNT}/usr/share/chromiumos-nvidia-cross/local-account-setup.py"
    fi
    install -m 0755 "${AUTH_FILES}/scripts/debug.sh" \
        "${MNT}/usr/share/chromiumos-nvidia-cross/scripts/debug.sh"
    install -m 0755 "${AUTH_FILES}/scripts/enable-nvidia-egl.sh" \
        "${MNT}/usr/share/chromiumos-nvidia-cross/scripts/enable-nvidia-egl.sh"
    install -m 0755 "${AUTH_FILES}/scripts/create-nvidia-nodes.sh" \
        "${MNT}/usr/share/chromiumos-nvidia-cross/scripts/create-nvidia-nodes.sh"
    if [ -f "${AUTH_FILES}/scripts/nvidia-gui-bringup.sh" ]; then
        install -m 0755 "${AUTH_FILES}/scripts/nvidia-gui-bringup.sh" \
            "${MNT}/usr/share/chromiumos-nvidia-cross/scripts/nvidia-gui-bringup.sh"
    fi
    if [ -f "${AUTH_FILES}/scripts/disable-gaia-after-local-account.sh" ]; then
        install -m 0755 "${AUTH_FILES}/scripts/disable-gaia-after-local-account.sh" \
            "${MNT}/usr/share/chromiumos-nvidia-cross/scripts/disable-gaia-after-local-account.sh"
    fi
    install -m 0755 "${AUTH_FILES}/chrome-nvidia-egl" \
        "${MNT}/usr/sbin/chrome-nvidia-egl"
    if [ -f "${AUTH_FILES}/drm-take-master" ]; then
        install -m 0755 "${AUTH_FILES}/drm-take-master" \
            "${MNT}/usr/sbin/drm-take-master"
    fi
    if [ -f "${AUTH_FILES}/drm-chronos-probe" ]; then
        install -m 0755 "${AUTH_FILES}/drm-chronos-probe" \
            "${MNT}/usr/sbin/drm-chronos-probe"
    fi
    if [ -f "${AUTH_FILES}/drm-modeset-test" ]; then
        install -m 0755 "${AUTH_FILES}/drm-modeset-test" \
            "${MNT}/usr/sbin/drm-modeset-test"
    fi
    if [ -f "${AUTH_FILES}/drm-force-scanout" ]; then
        install -m 0755 "${AUTH_FILES}/drm-force-scanout" \
            "${MNT}/usr/sbin/drm-force-scanout"
    fi
    install -m 0644 "${AUTH_FILES}/ui.override" "${MNT}/etc/init/ui.override"
    if [ -f "${AUTH_FILES}/nvidia-devnodes.conf" ]; then
        install -m 0644 "${AUTH_FILES}/nvidia-devnodes.conf" \
            "${MNT}/etc/init/nvidia-devnodes.conf"
    fi
    if [ -f "${AUTH_FILES}/nvidia-generic-auto-debug.conf" ]; then
        install -m 0644 "${AUTH_FILES}/nvidia-generic-auto-debug.conf" \
            "${MNT}/etc/init/nvidia-generic-auto-debug.conf"
        echo "  installed nvidia-generic-auto-debug.conf (flag-file headless debug)"
    fi
    if [ -f "${AUTH_FILES}/nvidia-gui-bringup.conf" ]; then
        install -m 0644 "${AUTH_FILES}/nvidia-gui-bringup.conf" \
            "${MNT}/etc/init/nvidia-gui-bringup.conf"
        echo "  installed nvidia-gui-bringup.conf (EVERY boot → GUI)"
    fi
    # Persist Gaia-off flags on rootfs chrome_dev.conf (not only after account create).
    if [ -f "${AUTH_FILES}/chrome_dev.conf.auth" ] && [ -f "${MNT}/etc/chrome_dev.conf" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in
                ''|\#*) continue ;;
                --*)
                    grep -qF -- "$line" "${MNT}/etc/chrome_dev.conf" 2>/dev/null || \
                        printf '%s\n' "$line" >> "${MNT}/etc/chrome_dev.conf"
                    ;;
            esac
        done < "${AUTH_FILES}/chrome_dev.conf.auth"
        echo "  merged chrome_dev.conf.auth (disable-gaia / oobe-skip)"
    fi
    if [ -f "${BSP_FILES}/release-nvidia-drm-master.sh" ]; then
        mkdir -p "${MNT}/usr/share/chromiumos-nvidia-cross"
        install -m 0755 "${BSP_FILES}/release-nvidia-drm-master.sh" \
            "${MNT}/usr/share/chromiumos-nvidia-cross/release-nvidia-drm-master.sh"
        echo "  updated release-nvidia-drm-master.sh (stops frecon)"
    fi
    if [ -f "${BSP_FILES}/release-nvidia-drm-master.conf" ]; then
        install -m 0644 "${BSP_FILES}/release-nvidia-drm-master.conf" \
            "${MNT}/etc/init/release-nvidia-drm-master.conf"
    fi
    if [ -f "${MNT}/usr/share/glvnd/egl_vendor.d/50_mesa.json.disabled" ]; then
        mv "${MNT}/usr/share/glvnd/egl_vendor.d/50_mesa.json.disabled" \
           "${MNT}/usr/share/glvnd/egl_vendor.d/50_mesa.json"
        echo "  restored 50_mesa.json (needed for EGL device_* extensions)"
    elif [ -f "${MNT}/usr/share/glvnd/egl_vendor.d/50_mesa.json" ]; then
        echo "  50_mesa.json present"
    else
        echo "  WARNING: no 50_mesa.json on this rootfs"
    fi
    if [ -f "${MNT}/etc/chrome_dev.conf" ]; then
        sed -i '/use-gl/d; /use-angle/d' "${MNT}/etc/chrome_dev.conf" || true
        # Ensure dual-vendor FILENAMES line exists (session_manager may ignore __*).
        sed -i '/^__EGL_VENDOR_LIBRARY_FILENAMES=/d' "${MNT}/etc/chrome_dev.conf" || true
        printf '%s\n' \
          '__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json:/usr/share/glvnd/egl_vendor.d/10_nvidia.json' \
          >> "${MNT}/etc/chrome_dev.conf"
        echo "  chrome_dev.conf EGL:"
        grep -E 'EGL|use-gl|gpu-sandbox' "${MNT}/etc/chrome_dev.conf" | sed 's/^/    /' || true
    fi
    echo "  wrapper FILENAMES:"
    grep EGL_VENDOR "${MNT}/usr/sbin/chrome-nvidia-egl" | sed 's/^/    /' || true
    ls -l "${dest_scripts}/debug.sh" \
        "${MNT}/usr/sbin/nvidia-generic-debug" \
        "${MNT}/usr/sbin/chrome-nvidia-egl" \
        "${MNT}/etc/init/ui.override" \
        "${MNT}/etc/init/nvidia-gui-bringup.conf" 2>/dev/null || true
}

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

# Unique in case glob double-matches.
if [ "${#ROOTS[@]}" -gt 0 ]; then
    mapfile -t ROOTS < <(printf '%s\n' "${ROOTS[@]}" | awk 'NF && !seen[$0]++')
fi

[ "${#ROOTS[@]}" -ge 1 ] || { echo "no ROOT-A/ROOT-B partitions on ${DEV}" >&2; lsblk -o NAME,LABEL,PARTLABEL "$DEV" >&2; exit 1; }

echo "target ${DEV}"
for root in "${ROOTS[@]}"; do
    echo
    echo "=== ${root} ($(label_of "$root")) ==="
    umount "$MNT" 2>/dev/null || true
    mount -o rw "$root" "$MNT" || mount -o rw,noload "$root" "$MNT"
    apply_root
    sync
    umount "$MNT"
done

if [ -n "$STATE" ]; then
    echo
    echo "=== ${STATE} (stateful) ==="
    mount -o rw "$STATE" "$MNT"
    mkdir -p "${MNT}/dev_image/sbin/scripts"
    install -m 0755 "${AUTH_FILES}/scripts/debug.sh" \
        "${MNT}/dev_image/sbin/scripts/debug.sh"
    install -m 0755 "${AUTH_FILES}/scripts/enable-nvidia-egl.sh" \
        "${MNT}/dev_image/sbin/scripts/enable-nvidia-egl.sh"
    install -m 0755 "${AUTH_FILES}/scripts/create-nvidia-nodes.sh" \
        "${MNT}/dev_image/sbin/scripts/create-nvidia-nodes.sh"
    if [ -f "${AUTH_FILES}/scripts/capture-chrome-logs.sh" ]; then
        install -m 0755 "${AUTH_FILES}/scripts/capture-chrome-logs.sh" \
            "${MNT}/dev_image/sbin/scripts/capture-chrome-logs.sh"
    fi
    if [ -f "${AUTH_FILES}/scripts/nvidia-gui-bringup.sh" ]; then
        install -m 0755 "${AUTH_FILES}/scripts/nvidia-gui-bringup.sh" \
            "${MNT}/dev_image/sbin/scripts/nvidia-gui-bringup.sh"
    fi
    if [ -f "${AUTH_FILES}/scripts/disable-gaia-after-local-account.sh" ]; then
        install -m 0755 "${AUTH_FILES}/scripts/disable-gaia-after-local-account.sh" \
            "${MNT}/dev_image/sbin/scripts/disable-gaia-after-local-account.sh"
    fi
    install -m 0755 "${AUTH_FILES}/scripts/debug.sh" \
        "${MNT}/dev_image/sbin/nvidia-generic-debug"
    install -m 0755 "${AUTH_FILES}/scripts/enable-nvidia-egl.sh" \
        "${MNT}/dev_image/sbin/enable-nvidia-egl"
    install -m 0755 "${AUTH_FILES}/scripts/create-nvidia-nodes.sh" \
        "${MNT}/dev_image/sbin/create-nvidia-nodes"
    if [ -f "${AUTH_FILES}/scripts/capture-chrome-logs.sh" ]; then
        install -m 0755 "${AUTH_FILES}/scripts/capture-chrome-logs.sh" \
            "${MNT}/dev_image/sbin/capture-chrome-logs"
    fi
    if [ -f "${AUTH_FILES}/scripts/nvidia-gui-bringup.sh" ]; then
        install -m 0755 "${AUTH_FILES}/scripts/nvidia-gui-bringup.sh" \
            "${MNT}/dev_image/sbin/nvidia-gui-bringup"
    fi
    if [ -f "${AUTH_FILES}/scripts/disable-gaia-after-local-account.sh" ]; then
        install -m 0755 "${AUTH_FILES}/scripts/disable-gaia-after-local-account.sh" \
            "${MNT}/dev_image/sbin/disable-gaia-after-local-account"
    fi
    install -m 0755 "${AUTH_FILES}/chrome-nvidia-egl" \
        "${MNT}/dev_image/sbin/chrome-nvidia-egl"
    if [ -f "${AUTH_FILES}/drm-take-master" ]; then
        install -m 0755 "${AUTH_FILES}/drm-take-master" \
            "${MNT}/dev_image/sbin/drm-take-master"
    fi
    if [ -f "${AUTH_FILES}/drm-chronos-probe" ]; then
        install -m 0755 "${AUTH_FILES}/drm-chronos-probe" \
            "${MNT}/dev_image/sbin/drm-chronos-probe"
    fi
    if [ -f "${AUTH_FILES}/drm-modeset-test" ]; then
        install -m 0755 "${AUTH_FILES}/drm-modeset-test" \
            "${MNT}/dev_image/sbin/drm-modeset-test"
    fi
    if [ -f "${AUTH_FILES}/drm-force-scanout" ]; then
        install -m 0755 "${AUTH_FILES}/drm-force-scanout" \
            "${MNT}/dev_image/sbin/drm-force-scanout"
    fi
    mkdir -p "${MNT}/dev_image/lib64/gbm"
    # NVIDIA GBM shim + Mesa GBM frontend (Mesa-first EGL needs device_*).
    GBM_COMPAT="${AUTH_FILES}/libgbm-minigbm-compat.so"
    if [ ! -f "$GBM_COMPAT" ]; then
        echo "missing $GBM_COMPAT — build gbm-minigbm-compat.c first" >&2
        exit 1
    fi
    install -m 0755 "$GBM_COMPAT" "${MNT}/dev_image/lib64/libgbm.so.1"
    install -m 0755 "$GBM_COMPAT" "${MNT}/dev_image/lib64/libgbm-nvidia-shim.so.1.bak"
    DRM_COMPAT="${AUTH_FILES}/libdrm-addfb-compat.so"
    if [ -f "$DRM_COMPAT" ]; then
        install -m 0755 "$DRM_COMPAT" "${MNT}/dev_image/lib64/libdrm.so.2"
    fi
    MESA_GBM=""
    for cand in /usr/lib/x86_64-linux-gnu/libgbm.so.1.0.0 \
                /usr/lib/x86_64-linux-gnu/libgbm.so.1; do
        if [ -f "$cand" ]; then
            MESA_GBM="$cand"
            break
        fi
    done
    [ -n "$MESA_GBM" ] || { echo "host Mesa libgbm not found" >&2; exit 1; }
    install -m 0755 "$MESA_GBM" "${MNT}/dev_image/lib64/libgbm-mesa.so.1"
    if [ -e "${MNT}/dev_image/lib64/libnvidia-allocator.so.1" ] || \
       [ -e "${MNT}/dev_image/lib64/libnvidia-allocator.so.595.91.07" ]; then
        ln -sfn ../libnvidia-allocator.so.1 \
            "${MNT}/dev_image/lib64/gbm/nvidia-drm_gbm.so"
    fi
    echo "  GBM/DRM:"
    ls -l "${MNT}/dev_image/lib64/libgbm.so.1" \
        "${MNT}/dev_image/lib64/libgbm-mesa.so.1" \
        "${MNT}/dev_image/lib64/libdrm.so.2" \
        "${MNT}/dev_image/lib64/gbm/nvidia-drm_gbm.so" 2>&1 | sed 's/^/    /'
    ls -l "${MNT}/dev_image/sbin/scripts/enable-nvidia-egl.sh"
    sync
    umount "$MNT"
fi

echo
echo "done. Reboot ChromiumOS, or on VT2:"
echo "  /usr/sbin/scripts/debug.sh"
echo "  # or: /usr/sbin/nvidia-generic-debug"
