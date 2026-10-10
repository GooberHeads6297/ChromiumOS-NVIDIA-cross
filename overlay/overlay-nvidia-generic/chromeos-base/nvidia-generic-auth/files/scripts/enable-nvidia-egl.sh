#!/bin/sh
# Run on ChromiumOS VT2 as root.
set -eu
mount -o remount,rw /

if [ -x /usr/sbin/create-nvidia-nodes ]; then
  /usr/sbin/create-nvidia-nodes
elif [ -x /usr/sbin/scripts/create-nvidia-nodes.sh ]; then
  /usr/sbin/scripts/create-nvidia-nodes.sh
elif [ -x /usr/share/chromiumos-nvidia-cross/scripts/create-nvidia-nodes.sh ]; then
  /usr/share/chromiumos-nvidia-cross/scripts/create-nvidia-nodes.sh
fi

# Mesa MUST be enabled for device_* client extensions (NVIDIA alone lacks them).
if [ -f /usr/share/glvnd/egl_vendor.d/50_mesa.json.disabled ]; then
  mv /usr/share/glvnd/egl_vendor.d/50_mesa.json.disabled \
     /usr/share/glvnd/egl_vendor.d/50_mesa.json
fi

cat > /usr/sbin/chrome-nvidia-egl << 'EOF'
#!/bin/sh
export LD_LIBRARY_PATH=/usr/local/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export __EGL_VENDOR_LIBRARY_DIRS=/usr/share/glvnd/egl_vendor.d
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json:/usr/share/glvnd/egl_vendor.d/50_mesa.json
export __EGL_EXTERNAL_PLATFORM_CONFIG_DIRS=/usr/share/egl/egl_external_platform.d
exec /opt/google/chrome/chrome "$@"
EOF
chmod 755 /usr/sbin/chrome-nvidia-egl
printf '%s\n' 'env CHROME_COMMAND_FLAG="--chrome-command=/usr/sbin/chrome-nvidia-egl"' > /etc/init/ui.override

# Drop flags that force the wrong GL path.
if [ -f /etc/chrome_dev.conf ]; then
  sed -i '/use-gl/d; /use-angle/d' /etc/chrome_dev.conf || true
fi

initctl reload-configuration
stop ui 2>/dev/null || true
sleep 1
start ui
