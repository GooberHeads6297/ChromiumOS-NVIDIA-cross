# /etc/profile.d/nvidia-egl-env.sh — interactive shells only (not Ash).
# Do not force GBM_BACKEND or NVIDIA-only EGL; that breaks the iGPU login UI.

export __EGL_VENDOR_LIBRARY_DIRS=/usr/share/glvnd/egl_vendor.d
export __EGL_EXTERNAL_PLATFORM_CONFIG_DIRS=/usr/share/egl/egl_external_platform.d
