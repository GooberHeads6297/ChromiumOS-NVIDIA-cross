#!/bin/bash
# Inject NVIDIA EGL companion libs. ROOT-A is ~2G and fills easily
# (gpucomp alone ~90MB), so real .so files go on H-STATE → /usr/local/lib64
# and ROOT-A only gets tiny symlinks + LD_LIBRARY_PATH via chrome-nvidia-egl.
#
#   sudo ./tools/copy-nvidia-egl-libs-to-disk.sh /dev/nvme0n1

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUTH_FILES="${REPO_ROOT}/overlay/overlay-nvidia-generic/chromeos-base/nvidia-generic-auth/files"
DEV="${1:-/dev/nvme0n1}"
PV="595.91.07"
VENDOR="${REPO_ROOT}/vendor/NVIDIA-Linux-x86_64-${PV}"

if [ "$(id -u)" -ne 0 ]; then
    echo "re-run as root: sudo $0 ${DEV}" >&2
    exit 1
fi
[ -b "$DEV" ] || { echo "not a block device: $DEV" >&2; exit 1; }
[ -d "$VENDOR" ] || { echo "missing vendor tree $VENDOR" >&2; exit 1; }

# Large payloads — never store twice on ROOT-A.
LIBS=(
  "libnvidia-eglcore.so.${PV}"
  "libnvidia-glsi.so.${PV}"
  "libnvidia-gpucomp.so.${PV}"
  "libnvidia-tls.so.${PV}"
  "libnvidia-glcore.so.${PV}"
  "libEGL_nvidia.so.${PV}"
  "libGLX_nvidia.so.${PV}"
  "libGLESv2_nvidia.so.${PV}"
  "libGLESv1_CM_nvidia.so.${PV}"
  "libnvidia-egl-gbm.so.1.1.3"
  "libnvidia-allocator.so.${PV}"
)

for lib in "${LIBS[@]}"; do
  [ -f "${VENDOR}/${lib}" ] || { echo "missing ${VENDOR}/${lib}" >&2; exit 1; }
done

label_of() {
  local l
  l=$(lsblk -no LABEL "$1" 2>/dev/null | sed '/^$/d' | head -n1)
  if [ -n "$l" ]; then printf '%s\n' "$l"; return; fi
  lsblk -no PARTLABEL "$1" 2>/dev/null | sed '/^$/d' | head -n1
}

MNT="$(mktemp -d /tmp/cros-nvegl-XXXXXX)"
cleanup() { umount "$MNT" 2>/dev/null || true; rmdir "$MNT" 2>/dev/null || true; }
trap cleanup EXIT

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
mapfile -t ROOTS < <(printf '%s\n' "${ROOTS[@]}" | awk 'NF && !seen[$0]++')
[ "${#ROOTS[@]}" -ge 1 ] || { echo "no ROOT-A on ${DEV}" >&2; exit 1; }
[ -n "$STATE" ] || { echo "no STATE/H-STATE on ${DEV}" >&2; exit 1; }

echo "target ${DEV}"
echo "=== ${STATE} (stateful → /usr/local/lib64) ==="
umount "$MNT" 2>/dev/null || true
mount -o rw "$STATE" "$MNT"
mkdir -p "${MNT}/dev_image/lib64/gbm"
for lib in "${LIBS[@]}"; do
  install -m 0755 "${VENDOR}/${lib}" "${MNT}/dev_image/lib64/${lib}"
  echo "  + /usr/local/lib64/${lib} ($(du -h "${VENDOR}/${lib}" | cut -f1))"
done
ln -sfn "libEGL_nvidia.so.${PV}" "${MNT}/dev_image/lib64/libEGL_nvidia.so.0"
ln -sfn "libGLX_nvidia.so.${PV}" "${MNT}/dev_image/lib64/libGLX_nvidia.so.0"
ln -sfn "libGLESv2_nvidia.so.${PV}" "${MNT}/dev_image/lib64/libGLESv2_nvidia.so.2"
ln -sfn "libGLESv1_CM_nvidia.so.${PV}" "${MNT}/dev_image/lib64/libGLESv1_CM_nvidia.so.1"
ln -sfn "libnvidia-egl-gbm.so.1.1.3" "${MNT}/dev_image/lib64/libnvidia-egl-gbm.so.1"
ln -sfn "libnvidia-allocator.so.${PV}" "${MNT}/dev_image/lib64/libnvidia-allocator.so.1"
ln -sfn "../libnvidia-egl-gbm.so.1" "${MNT}/dev_image/lib64/gbm/nvidia-drm_gbm.so"
df -h "$MNT" | sed 's/^/  /'
sync
umount "$MNT"

# Wrapper must put /usr/local/lib64 first so dlopen finds versioned companions.
# Do not overwrite chrome-nvidia-egl here; copy-sbin-scripts owns that file.

link_root() {
  local libdir="$1"
  mkdir -p "${libdir}/gbm" "${MNT}/usr/sbin" "${MNT}/etc/init" "${MNT}/usr/sbin/scripts"
  # Free ROOT-A: remove fat copies left by the aborted install.
  for lib in "${LIBS[@]}"; do
    if [ -f "${libdir}/${lib}" ] && [ ! -L "${libdir}/${lib}" ]; then
      rm -f "${libdir}/${lib}"
      echo "  freed ${libdir}/${lib}"
    fi
  done
  for lib in "${LIBS[@]}"; do
    ln -sfn "/usr/local/lib64/${lib}" "${libdir}/${lib}"
  done
  ln -sfn "/usr/local/lib64/libEGL_nvidia.so.0" "${libdir}/libEGL_nvidia.so.0"
  ln -sfn "/usr/local/lib64/libGLX_nvidia.so.0" "${libdir}/libGLX_nvidia.so.0"
  ln -sfn "/usr/local/lib64/libGLESv2_nvidia.so.2" "${libdir}/libGLESv2_nvidia.so.2"
  ln -sfn "/usr/local/lib64/libGLESv1_CM_nvidia.so.1" "${libdir}/libGLESv1_CM_nvidia.so.1"
  ln -sfn "/usr/local/lib64/libnvidia-egl-gbm.so.1" "${libdir}/libnvidia-egl-gbm.so.1"
  ln -sfn "/usr/local/lib64/libnvidia-allocator.so.1" "${libdir}/libnvidia-allocator.so.1"
  ln -sfn "/usr/local/lib64/gbm/nvidia-drm_gbm.so" "${libdir}/gbm/nvidia-drm_gbm.so"
  install -m 0755 "${AUTH_FILES}/chrome-nvidia-egl" "${MNT}/usr/sbin/chrome-nvidia-egl"
  install -m 0644 "${AUTH_FILES}/ui.override" "${MNT}/etc/init/ui.override"
  if [ -f "${AUTH_FILES}/scripts/debug.sh" ]; then
    install -m 0755 "${AUTH_FILES}/scripts/debug.sh" \
      "${MNT}/usr/sbin/scripts/debug.sh"
  fi
  if [ -f "${MNT}/etc/chrome_dev.conf" ]; then
    sed -i '/^--use-gl=egl/d; /^--use-angle=/d' "${MNT}/etc/chrome_dev.conf" || true
  fi
  df -h "$MNT" | sed 's/^/  /'
  echo "  sample links:"
  ls -l "${libdir}/libEGL_nvidia.so.0" "${libdir}/libnvidia-gpucomp.so.${PV}" 2>/dev/null | sed 's/^/    /'
}

for root in "${ROOTS[@]}"; do
  echo
  echo "=== ${root} (ROOT — symlinks only) ==="
  umount "$MNT" 2>/dev/null || true
  mount -o rw "$root" "$MNT" || mount -o rw,noload "$root" "$MNT"
  if [ -d "${MNT}/usr/lib64" ]; then
    link_root "${MNT}/usr/lib64"
  else
    link_root "${MNT}/usr/lib"
  fi
  sync
  umount "$MNT"
done

echo
echo "done. Boot ChromiumOS, then VT2: /usr/sbin/scripts/debug.sh"
echo "Section A must show OK for eglcore/glsi/gpucomp (via /usr/local/lib64)."
