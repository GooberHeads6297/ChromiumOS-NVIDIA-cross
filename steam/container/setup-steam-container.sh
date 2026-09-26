#!/bin/bash
# steam/container/setup-steam-container.sh -- Steam + Proton with native NVIDIA Vulkan.
#
# Run this ON the ChromiumOS device, after the Stage 3 gate passes.
#
# Why a container we build ourselves rather than a ChromeOS feature:
#
#   Borealis, the Steam environment ChromeOS used to ship, is Google-internal and was
#   discontinued on 1 January 2026. It was never in the open ChromiumOS tree, so
#   building from source does not provide it and no board configuration enables it.
#
# Why not Crostini:
#
#   Crostini runs containers inside the Termina VM, where the guest sees a virtio-gpu
#   device and Vulkan is forwarded through venus. That inserts a translation layer
#   between Proton and the GPU, which is precisely what we are trying to avoid. This
#   container instead runs directly on the ChromeOS host with the real /dev/nvidia*
#   nodes, so Proton talks to the NVIDIA driver with nothing in between.
#
# The one hard rule: the NVIDIA userspace inside the container must be the SAME version
# as the host kernel module. Installing Debian's nvidia packages here would pull a
# different version and break everything, so the host's libraries are bind-mounted in.
#
# Usage:
#   ./setup-steam-container.sh create      # build the rootfs
#   ./setup-steam-container.sh enter       # shell inside it
#   ./setup-steam-container.sh steam       # launch Steam
#   ./setup-steam-container.sh verify      # check the Vulkan path
#   ./setup-steam-container.sh destroy

set -uo pipefail

CONTAINER_ROOT="${CONTAINER_ROOT:-/usr/local/steam-container}"
ROOTFS="${CONTAINER_ROOT}/rootfs"
DEBIAN_SUITE="${DEBIAN_SUITE:-bookworm}"
DEBIAN_MIRROR="${DEBIAN_MIRROR:-https://deb.debian.org/debian}"

# Must match the host driver exactly. Kept in sync with safety/limits.conf.
NVIDIA_VERSION="${NVIDIA_VERSION:-595.91.07}"

log()  { printf '[steam-container] %s\n' "$*" >&2; }
die()  { printf '[steam-container] ERROR %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "must run as root"

ACTION="${1:-}"
[ -n "$ACTION" ] || die "usage: $0 {create|enter|steam|verify|destroy}"

# The host libraries the container needs. These are bind-mounted read-only rather than
# copied, so the container can never drift out of version with the kernel module.
host_nvidia_libs() {
    cat <<EOF
libnvidia-glcore.so.${NVIDIA_VERSION}
libEGL_nvidia.so.${NVIDIA_VERSION}
libGLX_nvidia.so.${NVIDIA_VERSION}
libnvidia-allocator.so.${NVIDIA_VERSION}
libcuda.so.${NVIDIA_VERSION}
EOF
}

# ---------------------------------------------------------------------------
verify_host() {
    [ -e /dev/nvidia0 ] || die "no /dev/nvidia0 on the host; Stage 2 has not passed"
    command -v nvidia-smi >/dev/null 2>&1 || die "nvidia-smi missing on the host"

    local hv
    hv="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | tr -d ' ')"
    [ -n "$hv" ] || die "cannot read the host driver version"
    if [ "$hv" != "$NVIDIA_VERSION" ]; then
        die "host driver is ${hv} but this script targets ${NVIDIA_VERSION}.
       The container userspace must match the host kernel module exactly.
       Update NVIDIA_VERSION (and safety/limits.conf) or rebuild the image."
    fi
    log "host driver ${hv} confirmed"
}

# ---------------------------------------------------------------------------
do_create() {
    verify_host
    command -v debootstrap >/dev/null 2>&1 || \
        die "debootstrap not available on the ChromeOS host.

       Two options:
         1. Build the rootfs on the Ubuntu build host and copy it across:
              sudo debootstrap ${DEBIAN_SUITE} ./rootfs ${DEBIAN_MIRROR}
              sudo tar -C ./rootfs -cf steam-rootfs.tar .
            then extract it into ${ROOTFS} here.
         2. Add dev-util/debootstrap to the board overlay."

    mkdir -p "$ROOTFS"
    log "bootstrapping Debian ${DEBIAN_SUITE} (this takes a while)"
    debootstrap --arch=amd64 --include=ca-certificates,curl,locales \
        "$DEBIAN_SUITE" "$ROOTFS" "$DEBIAN_MIRROR" || die "debootstrap failed"

    # 32-bit support is not optional: Steam's own client is 32-bit, and a great many
    # games still are. Forgetting this produces confusing "missing library" errors.
    log "enabling i386 multiarch and installing Steam dependencies"
    chroot "$ROOTFS" /bin/bash -euo pipefail <<'CHROOT'
export DEBIAN_FRONTEND=noninteractive
dpkg --add-architecture i386
apt-get update
apt-get install -y --no-install-recommends \
    libc6:i386 libstdc++6:i386 \
    libgl1:i386 libgl1 \
    libegl1:i386 libegl1 \
    libglx0:i386 libglx0 \
    libvulkan1:i386 libvulkan1 \
    libx11-6:i386 libxext6:i386 libxrandr2:i386 libxinerama1:i386 \
    libxcursor1:i386 libxi6:i386 libxfixes3:i386 \
    libasound2:i386 libpulse0:i386 \
    libdbus-1-3:i386 libnm0 \
    vulkan-tools mesa-utils \
    xz-utils zenity
# Deliberately NOT installing Debian's nvidia packages: they would pull a different
# driver version and conflict with the host module. The host libraries are bind-mounted
# in instead, which is the only way to keep versions identical.
apt-get clean
CHROOT
    [ $? -eq 0 ] || die "container package setup failed"

    # Where the host NVIDIA libraries get mounted.
    mkdir -p "${ROOTFS}/usr/lib/x86_64-linux-gnu/nvidia"
    mkdir -p "${ROOTFS}/usr/share/vulkan/icd.d"
    mkdir -p "${ROOTFS}/opt/steam"

    install -m 0755 "$(dirname "$0")/steam-launch.sh" "${ROOTFS}/usr/local/bin/steam-launch" 2>/dev/null \
        || log "note: steam-launch.sh not copied; run it from the repo instead"

    log "rootfs ready at ${ROOTFS}"
    log "next: ${0} enter   (or: ${0} steam)"
}

# ---------------------------------------------------------------------------
# Bind mounts. Read-only wherever possible; the NVIDIA libraries especially, since the
# container has no business modifying the host's driver.
# ---------------------------------------------------------------------------
setup_mounts() {
    local m
    for m in proc sys dev dev/pts tmp; do
        mkdir -p "${ROOTFS}/${m}"
    done

    mountpoint -q "${ROOTFS}/proc" || mount -t proc proc "${ROOTFS}/proc"
    mountpoint -q "${ROOTFS}/sys"  || mount -t sysfs sys "${ROOTFS}/sys"
    mountpoint -q "${ROOTFS}/dev"  || mount --rbind /dev "${ROOTFS}/dev"
    mountpoint -q "${ROOTFS}/tmp"  || mount -t tmpfs tmpfs "${ROOTFS}/tmp"

    # The NVIDIA userspace, straight from the host. This is what keeps the container's
    # libraries and the host's kernel module at identical versions.
    local dst="${ROOTFS}/usr/lib/x86_64-linux-gnu/nvidia"
    mkdir -p "$dst"
    local lib src
    while read -r lib; do
        [ -n "$lib" ] || continue
        src="$(find /usr/lib64 /usr/lib -maxdepth 2 -name "$lib" -print -quit 2>/dev/null)"
        if [ -z "$src" ]; then
            log "WARNING host library not found: ${lib}"
            continue
        fi
        touch "${dst}/${lib}"
        mountpoint -q "${dst}/${lib}" || mount --bind -o ro "$src" "${dst}/${lib}"
    done < <(host_nvidia_libs)

    # SONAME symlinks the loaders actually look for.
    chroot "$ROOTFS" /bin/sh -c '
        cd /usr/lib/x86_64-linux-gnu/nvidia || exit 0
        for f in *.so.'"${NVIDIA_VERSION}"'; do
            [ -e "$f" ] || continue
            base="${f%.so.'"${NVIDIA_VERSION}"'}"
            ln -sf "$f" "${base}.so.1"
            ln -sf "$f" "${base}.so"
        done
        ln -sf libGLX_nvidia.so.'"${NVIDIA_VERSION}"' libGLX_nvidia.so.0 2>/dev/null
        ln -sf libEGL_nvidia.so.'"${NVIDIA_VERSION}"' libEGL_nvidia.so.0 2>/dev/null
        echo /usr/lib/x86_64-linux-gnu/nvidia > /etc/ld.so.conf.d/nvidia.conf
        ldconfig
    ' 2>/dev/null

    # Vulkan ICD, pointed at the bind-mounted library.
    cat > "${ROOTFS}/usr/share/vulkan/icd.d/nvidia_icd.json" <<EOF
{
    "file_format_version" : "1.0.1",
    "ICD": {
        "library_path": "/usr/lib/x86_64-linux-gnu/nvidia/libGLX_nvidia.so.0",
        "api_version" : "1.4.329"
    }
}
EOF

    cp /etc/resolv.conf "${ROOTFS}/etc/resolv.conf" 2>/dev/null || true
}

teardown_mounts() {
    local m
    for m in $(awk '{print $2}' /proc/mounts | grep "^${ROOTFS}" | sort -r); do
        umount -l "$m" 2>/dev/null || true
    done
}

container_exec() {
    setup_mounts
    chroot "$ROOTFS" /usr/bin/env -i \
        HOME=/root TERM="${TERM:-xterm}" \
        PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games \
        LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu/nvidia \
        VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json \
        __GLX_VENDOR_LIBRARY_NAME=nvidia \
        "$@"
}

# ---------------------------------------------------------------------------
do_verify() {
    verify_host
    [ -d "$ROOTFS" ] || die "no container at ${ROOTFS}; run '${0} create'"

    log "checking the Vulkan path inside the container"
    local rc=0

    printf '\n--- nvidia-smi (host driver seen from inside) ---\n'
    container_exec /bin/sh -c 'command -v nvidia-smi >/dev/null && nvidia-smi --query-gpu=name,driver_version --format=csv,noheader || echo "(nvidia-smi not in container; host check already passed)"'

    printf '\n--- vulkaninfo: which ICD? ---\n'
    if container_exec /bin/sh -c 'vulkaninfo --summary 2>/dev/null | grep -iE "driverName|deviceName|apiVersion"'; then
        :
    else
        printf 'vulkaninfo failed\n'; rc=1
    fi

    printf '\n--- is the NVIDIA driver the one answering? ---\n'
    if container_exec /bin/sh -c 'vulkaninfo --summary 2>/dev/null | grep -qi nvidia'; then
        printf 'OK   Vulkan is being served by the NVIDIA driver\n'
    else
        printf 'FAIL Vulkan is not using NVIDIA. Check VK_ICD_FILENAMES and the bind mounts.\n'
        rc=1
    fi

    printf '\n--- glxinfo renderer ---\n'
    container_exec /bin/sh -c 'command -v glxinfo >/dev/null && glxinfo -B 2>/dev/null | grep -iE "renderer|OpenGL version" || echo "(glxinfo unavailable)"'

    teardown_mounts
    printf '\n'
    if [ "$rc" -eq 0 ]; then
        log "Vulkan path verified. Arm the watchdog, then try a game."
    else
        log "Vulkan path NOT working; do not bother launching Steam yet."
    fi
    return "$rc"
}

# ---------------------------------------------------------------------------
do_steam() {
    verify_host

    # Refuse to run a gaming workload without the thermal watchdog. This is the moment
    # the card first sees sustained load, which is exactly when the guard matters.
    if ! status gpu-guard 2>/dev/null | grep -q running; then
        log "WARNING gpu-guard is not running."
        log "Start it first:  start gpu-guard"
        printf 'Continue anyway? [y/N] ' >&2
        read -r reply
        case "$reply" in y|Y) ;; *) die "aborted; start the watchdog first" ;; esac
    fi

    [ -f "${ROOTFS}/opt/steam/steam.sh" ] || {
        log "Steam not installed in the container yet; fetching the bootstrap"
        container_exec /bin/sh -c '
            cd /opt/steam &&
            curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steam.tar.gz | tar xz --strip-components=1
        ' || { teardown_mounts; die "Steam download failed"; }
    }

    log "launching Steam"
    container_exec /bin/sh -c 'cd /opt/steam && ./steam.sh'
    teardown_mounts
}

case "$ACTION" in
    create)  do_create ;;
    enter)   container_exec /bin/bash; teardown_mounts ;;
    steam)   do_steam ;;
    verify)  do_verify ;;
    destroy) teardown_mounts; rm -rf "$CONTAINER_ROOT"; log "removed ${CONTAINER_ROOT}" ;;
    *)       die "unknown action: ${ACTION}" ;;
esac
