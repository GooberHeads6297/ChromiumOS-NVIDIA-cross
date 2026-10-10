#!/bin/sh
# Create /dev/nvidia* on ChromiumOS. nvidia-drm can KMS without these nodes;
# libEGL_nvidia cannot. Desktop distros use setuid nvidia-modprobe; ChromeOS does not.
set -eu

modprobe nvidia 2>/dev/null || true
modprobe nvidia-modeset 2>/dev/null || true
modprobe nvidia-uvm 2>/dev/null || true
modprobe nvidia-drm 2>/dev/null || true

if command -v nvidia-modprobe >/dev/null 2>&1; then
  nvidia-modprobe -c 0 -u -m 2>/dev/null || \
    nvidia-modprobe -c 0 2>/dev/null || true
fi

nv_major="$(awk '/^ *nvidia$/ {print $1; exit}' /proc/devices 2>/dev/null || true)"
if [ -z "$nv_major" ]; then
  nv_major="$(awk '/nvidia/ {print $1; exit}' /proc/devices 2>/dev/null || true)"
fi
if [ -n "$nv_major" ]; then
  [ -e /dev/nvidiactl ] || mknod -m 0666 /dev/nvidiactl c "$nv_major" 255
  [ -e /dev/nvidia0 ] || mknod -m 0666 /dev/nvidia0 c "$nv_major" 0
  [ -e /dev/nvidia-modeset ] || mknod -m 0666 /dev/nvidia-modeset c "$nv_major" 254
fi

uvm_minor="$(awk '/nvidia-uvm$/ {print $1; exit}' /proc/misc 2>/dev/null || true)"
if [ -n "$uvm_minor" ] && [ ! -e /dev/nvidia-uvm ]; then
  mknod -m 0666 /dev/nvidia-uvm c 10 "$uvm_minor"
fi

# nvidia-modprobe usually leaves 0660 root:root. Ash runs as chronos — must be 0666.
for n in /dev/nvidiactl /dev/nvidia0 /dev/nvidia-modeset /dev/nvidia-uvm \
         /dev/nvidia-uvm-tools; do
  [ -e "$n" ] || continue
  chmod 0666 "$n" 2>/dev/null || true
  chown root:video "$n" 2>/dev/null || true
done

echo "-- nvidia modules --"
lsmod | grep -E '^nvidia' || true
echo "-- /proc/devices nvidia --"
grep -i nvidia /proc/devices || true
echo "-- /dev/nvidia* (must be 0666 for chronos) --"
ls -l /dev/nvidia* 2>/dev/null || echo "still missing /dev/nvidia*"
if command -v nvidia-smi >/dev/null 2>&1; then
  echo "-- nvidia-smi -L --"
  nvidia-smi -L 2>&1 | head -5 || true
fi
