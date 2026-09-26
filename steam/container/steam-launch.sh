#!/bin/bash
# steam-launch.sh -- launch Steam inside the container with sane Proton defaults.
#
# Installed to /usr/local/bin/steam-launch in the container rootfs.
#
# The environment here is the difference between Proton finding the NVIDIA driver and
# silently falling back to software rendering, so each variable is explained.

set -uo pipefail

NVIDIA_LIB_DIR=/usr/lib/x86_64-linux-gnu/nvidia

# --- driver selection -----------------------------------------------------
# The bind-mounted host libraries must come first on the search path, ahead of any
# Mesa libraries Debian installed.
export LD_LIBRARY_PATH="${NVIDIA_LIB_DIR}:${NVIDIA_LIB_DIR}/32:${LD_LIBRARY_PATH:-}"
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json
export __GLX_VENDOR_LIBRARY_NAME=nvidia

# --- Proton ---------------------------------------------------------------
# Force Proton for titles without a native Linux build. Without this Steam hides most
# of the library.
export STEAM_COMPAT_CLIENT_INSTALL_PATH=/opt/steam
# DXVK and VKD3D translate D3D to Vulkan; both want a real Vulkan driver, which is the
# whole point of the work up to here.
export PROTON_ENABLE_NVAPI=1
export PROTON_HIDE_NVIDIA_GPU=0

# NVAPI and DLSS need this on Ada. Harmless if unused.
export PROTON_ENABLE_NGX_UPDATER=1

# --- shader cache ---------------------------------------------------------
# Put the cache somewhere persistent and roomy. ChromeOS's stateful partition is the
# right place; /tmp would be cleared on every boot and recompile shaders each time.
export __GL_SHADER_DISK_CACHE=1
export __GL_SHADER_DISK_CACHE_PATH=/var/cache/nvidia-shaders
export DXVK_STATE_CACHE_PATH=/var/cache/dxvk
mkdir -p "$__GL_SHADER_DISK_CACHE_PATH" "$DXVK_STATE_CACHE_PATH" 2>/dev/null || true

# --- frame pacing ---------------------------------------------------------
# Leave vsync to the game. Forcing it on via the driver interacts badly with the linear
# dumb-buffer presentation path used for the ChromeOS UI.
export __GL_SYNC_TO_VBLANK=0

# --- diagnostics ----------------------------------------------------------
# DXVK's HUD is the quickest way to confirm the GPU is really doing the work. Set
# DXVK_HUD=full when investigating.
export DXVK_HUD="${DXVK_HUD:-}"
export DXVK_LOG_LEVEL="${DXVK_LOG_LEVEL:-warn}"

# --- sanity check before launching ---------------------------------------
if ! vulkaninfo --summary 2>/dev/null | grep -qi nvidia; then
    echo "ERROR: Vulkan is not being served by the NVIDIA driver." >&2
    echo "       Run 'setup-steam-container.sh verify' on the host and fix that first." >&2
    echo "       Launching Steam now would just run everything on the CPU." >&2
    exit 1
fi

echo "Vulkan: $(vulkaninfo --summary 2>/dev/null | grep -i deviceName | head -1 | sed 's/^ *//')" >&2

exec /opt/steam/steam.sh "$@"
