# /etc/profile.d/nvidia-egl-env.sh (and sourced by the UI environment)
#
# Points the EGL/GBM/Vulkan loaders at NVIDIA's implementations.
#
# ChromeOS normally has exactly one GL stack (Mesa) and so never needs any of this.
# Once NVIDIA's libraries are present there are two, and the loaders have to be told
# which vendor files to consider. Every path below corresponds to a JSON file installed
# by the nvidia-userspace ebuild, whose contents were read from the driver bundle:
#
#   10_nvidia.json      -> libEGL_nvidia.so.0          (glvnd EGL vendor)
#   15_nvidia_gbm.json  -> libnvidia-egl-gbm.so.1      (GBM external platform)
#   nvidia_icd.json     -> libGLX_nvidia.so.0          (Vulkan ICD, api 1.4.329)

# --- EGL vendor selection (glvnd) ------------------------------------------
# Mesa's vendor JSON also lives in this directory. Listing it keeps the iGPU usable as
# a fallback: glvnd picks a vendor per display, so both stacks can coexist.
export __EGL_VENDOR_LIBRARY_DIRS=/usr/share/glvnd/egl_vendor.d

# --- EGL external platforms -----------------------------------------------
# This is what makes eglGetPlatformDisplay(EGL_PLATFORM_GBM_KHR) work against NVIDIA.
# Without it, Chrome's Ozone/GBM backend cannot create a display on the NVIDIA device
# and falls back to software rendering.
export __EGL_EXTERNAL_PLATFORM_CONFIG_DIRS=/usr/share/egl/egl_external_platform.d

# --- GBM backend ----------------------------------------------------------
# Mesa's GBM loader looks here for a vendor backend matching the DRM driver name.
export GBM_BACKENDS_PATH=/usr/lib64/gbm
export GBM_BACKEND=nvidia-drm

# --- Vulkan ---------------------------------------------------------------
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json

# --- Device selection -----------------------------------------------------
# With two GPUs present, be explicit about which one the NVIDIA stack should drive.
# Matches the PCI address recorded in safety/limits.conf.
export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia

# Uncomment to trace loader decisions when the display path misbehaves. Very noisy, but
# it is the fastest way to find out which vendor library actually got loaded.
# export EGL_LOG_LEVEL=debug
# export VK_LOADER_DEBUG=all
