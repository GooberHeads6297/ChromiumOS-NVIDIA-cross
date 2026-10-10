#!/bin/sh
# Living VT2 debug — log to stateful for Ubuntu readback.
# Must stay POSIX (/bin/sh = dash on CrOS); no bash process substitution.
set -eu

LOG=/usr/local/tmp/nvidia-debug.log
LOG2=/mnt/stateful_partition/unencrypted/nvidia-debug.log
mount -o remount,rw / 2>/dev/null || true
mkdir -p /usr/local/tmp /mnt/stateful_partition/unencrypted 2>/dev/null || true

: >"$LOG"
: >"$LOG2"
: > /usr/local/tmp/drm-addfb.log 2>/dev/null || true
: > /usr/local/tmp/gbm-compat.log 2>/dev/null || true
# chronos GPU process must append shim logs
chmod 666 /usr/local/tmp/drm-addfb.log /usr/local/tmp/gbm-compat.log 2>/dev/null || true

# Headless (NVIDIA_AUTO_DEBUG=1 / no tty): log-only — VT2 login is unreliable
# once Ash owns the GPU. Interactive VT2: tee to /dev/tty as well.
PIPE=/usr/local/tmp/nvidia-debug.pipe
TEE_PID=""
rm -f "$PIPE"
if [ -n "${NVIDIA_AUTO_DEBUG:-}" ] || [ ! -w /dev/tty ]; then
  exec >>"$LOG" 2>&1
  echo "(headless / auto-debug — not using VT2 console)"
elif command -v tee >/dev/null 2>&1 && mkfifo "$PIPE" 2>/dev/null; then
  # shellcheck disable=SC2094
  tee -a "$LOG" > /dev/tty < "$PIPE" &
  TEE_PID=$!
  exec >"$PIPE" 2>&1
else
  exec >>"$LOG" 2>&1
fi

snap() {
  sync
  cp -f "$LOG" "$LOG2" 2>/dev/null || true
  sync
}

cleanup_tee() {
  exec > /dev/null 2>&1 || true
  if [ -n "${TEE_PID:-}" ]; then
    kill "$TEE_PID" 2>/dev/null || true
    wait "$TEE_PID" 2>/dev/null || true
  fi
  rm -f "$PIPE"
}
trap cleanup_tee EXIT

echo "======== debug.sh $(date -u +%Y-%m-%dT%H:%M:%SZ) ========"
snap

echo
echo "==== 0a. NVIDIA char nodes (chronos GBM needs these RW) ===="
if [ -x /usr/sbin/create-nvidia-nodes ]; then
  /usr/sbin/create-nvidia-nodes || true
elif [ -x /usr/sbin/scripts/create-nvidia-nodes.sh ]; then
  /usr/sbin/scripts/create-nvidia-nodes.sh || true
fi
for n in /dev/nvidiactl /dev/nvidia0 /dev/nvidia-modeset /dev/nvidia-uvm \
         /dev/nvidia-uvm-tools; do
  [ -e "$n" ] || continue
  chmod 0666 "$n" 2>/dev/null || true
  chown root:video "$n" 2>/dev/null || true
done
ls -l /dev/nvidia* 2>&1 | sed 's/^/  /' || echo "  MISSING /dev/nvidia*"

echo
echo "==== 0. Chrome binary Ozone patches (grep -a; no strings needed) ===="
CHROME_BIN=/opt/google/chrome/chrome
if [ ! -f "$CHROME_BIN" ]; then
  echo "  MISSING $CHROME_BIN"
else
  ls -l "$CHROME_BIN" | sed 's/^/  /'
  # Busybox/coreutils grep -a reads binary; prints HIT/MISS per patch marker.
  for pat in \
      'nvidia-drm: forcing legacy KMS' \
      'treating modes>0 as connected' \
      'GetDisplays:' \
      'SchedulePageFlip: no controller_' \
      'FindDisplay: no ID'; do
    if grep -aF -m1 -q -- "$pat" "$CHROME_BIN" 2>/dev/null; then
      echo "  HIT  $pat"
    else
      echo "  MISS $pat"
    fi
  done
  if grep -aF -m1 -q -- 'nvidia-drm: forcing legacy KMS' "$CHROME_BIN" 2>/dev/null &&
     grep -aF -m1 -q -- 'treating modes>0 as connected' "$CHROME_BIN" 2>/dev/null; then
    echo "  VERDICT: Chrome has Ozone 0002+0003 markers"
  else
    echo "  VERDICT: Chrome MISSING Ozone markers — flash/install rebuilt chromeos-chrome"
  fi
fi
snap

echo
echo "==== A. frecon dropmaster + hide amdgpu ===="
if [ -x /usr/share/chromiumos-nvidia-cross/release-nvidia-drm-master.sh ]; then
  /usr/share/chromiumos-nvidia-cross/release-nvidia-drm-master.sh || true
else
  for t in /run/frecon/current /run/frecon/vt*; do
    [ -e "$t" ] || continue
    printf '\033]drmdropmaster\a' > "$t" 2>/dev/null || true
  done
  # Only hide amdgpu modeset card — never renderD* (breaks Mesa EGL).
  chmod 000 /dev/dri/card1 2>/dev/null || true
  chmod 666 /dev/dri/renderD128 2>/dev/null || true
fi
echo "frecon: $(pgrep -x frecon | tr '\n' ' ')"
ls -l /dev/dri
snap

echo
echo "==== B. Mesa-first EGL + NVIDIA GBM + AddFB shim ===="
if [ ! -f /usr/local/lib64/libgbm.so.1 ]; then
  echo "  FATAL: missing /usr/local/lib64/libgbm.so.1"
fi
if [ ! -f /usr/local/lib64/libgbm-mesa.so.1 ]; then
  echo "  WARNING: missing /usr/local/lib64/libgbm-mesa.so.1"
fi
# EGL died last run with "Failed to get system egl display" when amdgpu
# renderD128 was mode 000. Keep render nodes usable; only card1 stays hidden.
chmod 666 /dev/dri/renderD128 /dev/dri/renderD129 2>/dev/null || true
chmod 666 /dev/dri/card2 2>/dev/null || true
ln -sfn ../libnvidia-allocator.so.1 /usr/local/lib64/gbm/nvidia-drm_gbm.so 2>/dev/null || true
echo "  EGL libs:"
ls -l /usr/local/lib64/libEGL_nvidia.so* /usr/local/lib64/libnvidia-egl-gbm.so* \
  /usr/share/glvnd/egl_vendor.d/10_nvidia.json \
  /usr/share/glvnd/egl_vendor.d/50_mesa.json 2>&1 | sed 's/^/    /'
echo "  dri nodes after unhide-render:"
ls -l /dev/dri/card* /dev/dri/renderD* 2>&1 | sed 's/^/    /'

cat > /usr/sbin/chrome-nvidia-egl << 'EOF'
#!/bin/sh
export LD_LIBRARY_PATH=/usr/local/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export GBM_BACKENDS_PATH=/usr/local/lib64/gbm
unset GBM_BACKEND
export MESA_GBM_LIB=/usr/local/lib64/libgbm-mesa.so.1
export __EGL_VENDOR_LIBRARY_DIRS=/usr/share/glvnd/egl_vendor.d
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json:/usr/share/glvnd/egl_vendor.d/50_mesa.json
export __EGL_EXTERNAL_PLATFORM_CONFIG_DIRS=/usr/share/egl/egl_external_platform.d
export EGL_PLATFORM=device
exec /opt/google/chrome/chrome \
  --disable-gpu-sandbox \
  --gpu-sandbox-failures-fatal=0 \
  --ignore-gpu-blocklist \
  --disable-native-gpu-memory-buffers \
  --disable-gpu-memory-buffer-compositor-resources \
  --enable-logging \
  --vmodule=*/screen_manager*=1,*/drm_gpu*=1,*/hardware_display*=1,*/drm_display*=1 \
  "$@"
EOF
chmod 755 /usr/sbin/chrome-nvidia-egl
printf '%s\n' 'env CHROME_COMMAND_FLAG="--chrome-command=/usr/sbin/chrome-nvidia-egl"' > /etc/init/ui.override
sed -i '/use-gl/d; /use-angle/d; /native-gpu-memory-buffer/d; /gpu-memory-buffer-compositor/d; /PassthroughCommandDecoder/d; /^__EGL_VENDOR_LIBRARY_FILENAMES=/d; /vmodule/d; /^--enable-logging/d; /disable-gpu-sandbox/d; /gpu-sandbox-failures/d; /ignore-gpu-blocklist/d' \
  /etc/chrome_dev.conf 2>/dev/null || true
{
  printf '%s\n' '__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json:/usr/share/glvnd/egl_vendor.d/50_mesa.json'
  printf '%s\n' '--disable-gpu-sandbox'
  printf '%s\n' '--gpu-sandbox-failures-fatal=0'
  printf '%s\n' '--ignore-gpu-blocklist'
  printf '%s\n' '!--enable-native-gpu-memory-buffers'
  printf '%s\n' '--disable-native-gpu-memory-buffers'
  printf '%s\n' '--disable-gpu-memory-buffer-compositor-resources'
  printf '%s\n' '--enable-logging'
  printf '%s\n' '--vmodule=*/screen_manager*=1,*/drm_gpu*=1,*/hardware_display*=1,*/drm_display*=1'
} >> /etc/chrome_dev.conf

echo "  GBM/DRM/EGL:"
ls -l /usr/local/lib64/libgbm.so.1 /usr/local/lib64/libgbm-mesa.so.1 \
  /usr/local/lib64/libdrm.so.2 /usr/local/lib64/gbm/nvidia-drm_gbm.so \
  /usr/share/glvnd/egl_vendor.d/50_mesa.json 2>&1 | sed 's/^/    /'
if grep -aF -m1 -q 'nvidia-bo ok' /usr/local/lib64/libgbm.so.1 2>/dev/null; then
  echo "    shim: gbm-minigbm-compat (NVIDIA renderable BO path)"
else
  echo "    shim: WARNING libgbm.so.1 missing nvidia-bo ok marker"
fi
snap

: > /var/log/chrome/chrome 2>/dev/null || true
stop ui 2>/dev/null || true
sleep 1
# Dropmaster while frecon can still process OSC, then STOP so it cannot reclaim.
for t in /run/frecon/current /run/frecon/vt*; do
  [ -e "$t" ] || continue
  printf '\033]drmdropmaster\a' > "$t" 2>/dev/null || true
done
sleep 0.3 2>/dev/null || sleep 1
if pgrep -x frecon >/dev/null 2>&1; then
  echo "  NOTE: frecon STOP — VT2 text may freeze until SUMMARY at end; log still grows"
  # shellcheck disable=SC2046
  kill -STOP $(pgrep -x frecon) 2>/dev/null || true
  echo "  frecon STOP for master handoff"
fi
# Root steal+release: clears any leftover master so chronos Chrome can SET_MASTER.
if [ -x /usr/local/sbin/drm-take-master ]; then
  /usr/local/sbin/drm-take-master /dev/dri/card2 || true
elif [ -x /usr/sbin/drm-take-master ]; then
  /usr/sbin/drm-take-master /dev/dri/card2 || true
fi
# Brief pink proof ONLY — must finish and release BEFORE start ui.
# Holding an FB across Chrome start raced GBM init (EACCES / 0 displays).
MODESET_BIN=""
if [ -x /usr/local/sbin/drm-modeset-test ]; then
  MODESET_BIN=/usr/local/sbin/drm-modeset-test
elif [ -x /usr/sbin/drm-modeset-test ]; then
  MODESET_BIN=/usr/sbin/drm-modeset-test
fi
if [ -n "$MODESET_BIN" ]; then
  echo "  running drm-modeset-test (brief pink, release before ui)..."
  "$MODESET_BIN" /dev/dri/card2 || true
else
  echo "  WARNING: drm-modeset-test missing"
fi
# Re-assert nodes after modeset-test; probe as chronos (matches Ash).
chmod 0666 /dev/dri/card2 /dev/dri/renderD129 2>/dev/null || true
for n in /dev/nvidiactl /dev/nvidia0 /dev/nvidia-modeset /dev/nvidia-uvm; do
  [ -e "$n" ] || continue
  chmod 0666 "$n" 2>/dev/null || true
done
echo "  --- chronos DRM/NVIDIA probe (must PASS before ui) ---"
PROBE=""
if [ -x /usr/local/sbin/drm-chronos-probe ]; then
  PROBE=/usr/local/sbin/drm-chronos-probe
elif [ -x /usr/sbin/drm-chronos-probe ]; then
  PROBE=/usr/sbin/drm-chronos-probe
fi
if [ -n "$PROBE" ]; then
  # CrOS has no `su`. Prefer runuser; else setuid via python.
  if command -v runuser >/dev/null 2>&1; then
    runuser -u chronos -- "$PROBE" /dev/dri/card2 2>&1 | sed 's/^/  /' || true
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$PROBE" <<'PY' 2>&1 | sed 's/^/  /' || true
import os, pwd, sys
os.setgid(pwd.getpwnam("chronos").pw_gid)
os.setuid(pwd.getpwnam("chronos").pw_uid)
os.execv(sys.argv[1], [sys.argv[1], "/dev/dri/card2"])
PY
  else
    echo "  WARNING: cannot drop to chronos (no runuser/python3); running probe as root"
    "$PROBE" /dev/dri/card2 2>&1 | sed 's/^/  /' || true
  fi
else
  echo "  WARNING: drm-chronos-probe missing"
fi
# Always kill frecon before Ash — plain fuser only prints PIDs (no "frecon" text).
if pgrep -x frecon >/dev/null 2>&1; then
  echo "  killing frecon so Ash can own card2 (VT2 will blank)"
  # shellcheck disable=SC2046
  kill -CONT $(pgrep -x frecon) 2>/dev/null || true
  # shellcheck disable=SC2046
  kill -TERM $(pgrep -x frecon) 2>/dev/null || true
  sleep 0.5 2>/dev/null || sleep 1
  # shellcheck disable=SC2046
  kill -KILL $(pgrep -x frecon) 2>/dev/null || true
  echo "  frecon after kill: $(pgrep -x frecon | tr '\n' ' ')"
fi
if [ -x /usr/sbin/drm-take-master ]; then
  /usr/sbin/drm-take-master /dev/dri/card2 || true
fi
echo "  holders before ui:"
fuser -v /dev/dri/card2 2>&1 | sed 's/^/    /' || echo "    (none)"
start ui 2>/dev/null || true
snap
# Wait for Chrome GBM + modeset/pageflip. Do NOT force-scanout (steals master).
sleep 15
status ui 2>/dev/null || true
snap
cp -f /usr/local/tmp/drm-addfb.log /mnt/stateful_partition/unencrypted/drm-addfb.log 2>/dev/null || true
cp -f /usr/local/tmp/gbm-compat.log /mnt/stateful_partition/unencrypted/gbm-compat.log 2>/dev/null || true
# Prefer fresh small logs over stale huge ones on pull: also stamp mtime.
touch /mnt/stateful_partition/unencrypted/gbm-compat.log \
  /mnt/stateful_partition/unencrypted/drm-addfb.log 2>/dev/null || true
sync
echo "  frecon left stopped/killed so Ash keeps DRM master"
echo "  for VT2 later (if frecon alive): kill -CONT \$(pgrep -x frecon)"
snap

echo
echo "==== C. holders / processes ===="
for c in /dev/dri/card*; do
  echo -n "  $c: "; fuser -v "$c" 2>&1 | tr '\n' ' ' || true; echo
done
pgrep -a 'chrome --type=gpu' 2>/dev/null | head -3 || echo "no gpu-process"
pgrep -c chrome 2>/dev/null || echo "chrome count 0"

echo
echo "==== D. counts ===="
for pat in 'Failed to authenticate' 'Platform device' 'eglCreateImage' \
           'CreateSharedImage' 'init_success' 'Restarting GPU' \
           'forcing legacy' 'Modeset succeeded' 'No modeset was attempted' \
           'Modeset commit failed' 'Display configuration failed' \
           'Failed to commit' 'Failed to set CRTC' 'Page flip' \
           'Can.t get a SkSurface' 'SetMaster' 'drmSetMaster' \
           'Unable to initialize GBM' 'Permission denied' 'EBUSY' 'incomplete' \
           'Failed to create scanout buffer' 'Failed to add framebuffer' \
           'Test-modeset' 'DRM configuring' 'DRM testing' \
           'GetDisplays:' 'FindDisplay:' 'SchedulePageFlip:' \
           'treating modes>0 as connected' 'reclaimed DRM master' \
           'drmSetMaster ok' 'drmSetMaster failed'; do
  n=$(grep -cF "$pat" /var/log/chrome/chrome 2>/dev/null || true)
  echo "  ${n:-0}	$pat"
done
echo "  --- shim present path (need Chrome SETCRTC/PAGE_FLIP > 0) ---"
if [ -f /usr/local/tmp/drm-addfb.log ]; then
  for spat in 'ioctl SETCRTC' 'ioctl PAGE_FLIP' 'PageFlip '; do
    n=$(grep -cF "$spat" /usr/local/tmp/drm-addfb.log 2>/dev/null || true)
    echo "  ${n:-0}	$spat"
  done
fi

echo
echo "==== E. ERROR/WARNING + modeset (last 100) ===="
grep -E 'ERROR|WARNING|ERR:|FATAL|modeset|Modeset|SetCrtc|CRTC|commit|master|SkSurface|configuration failed|AddFramebuffer' \
  /var/log/chrome/chrome 2>/dev/null | tail -100 || true

echo
echo "==== F. gpu maps ===="
gpid=$(pgrep -n -f 'chrome --type=gpu-process' 2>/dev/null || true)
echo "gpu_pid=${gpid:-none}"
if [ -n "${gpid:-}" ]; then
  grep -E 'libEGL|nvidia|mesa|minigbm|gpucomp|libgbm|libdrm' \
    "/proc/$gpid/maps" 2>/dev/null | awk '{print $NF}' | sort -u || true
fi

echo
echo "==== G. shim logs ===="
echo "-- drm-addfb --"
if [ -f /usr/local/tmp/drm-addfb.log ]; then
  wc -l /usr/local/tmp/drm-addfb.log
  grep -E 'SetCrtc|ADDFB2|Atomic|PageFlip|PAGE_FLIP|SETCRTC|SET_MASTER|DROP_MASTER|SetPlane|failed' \
    /usr/local/tmp/drm-addfb.log | tail -80
else
  echo "  (missing)"
fi
echo "-- gbm-compat (summary) --"
if [ -f /usr/local/tmp/gbm-compat.log ]; then
  echo -n "  ok: "; grep -c ' ok ' /usr/local/tmp/gbm-compat.log || echo 0
  echo -n "  failed: "; grep -c ' failed ' /usr/local/tmp/gbm-compat.log || echo 0
  grep ' failed ' /usr/local/tmp/gbm-compat.log | sort | uniq -c | sort -rn | head -5 | sed 's/^/    /'
  grep ' ok ' /usr/local/tmp/gbm-compat.log | sort | uniq -c | sort -rn | head -5 | sed 's/^/    /'
else
  echo "  (missing)"
fi

echo "======== end ========"
snap

# Only CONT frecon for interactive VT2; headless auto-debug must not steal DRM.
if [ -z "${NVIDIA_AUTO_DEBUG:-}" ] && pgrep -x frecon >/dev/null 2>&1; then
  # shellcheck disable=SC2046
  kill -CONT $(pgrep -x frecon) 2>/dev/null || true
  sleep 0.3 2>/dev/null || sleep 1
fi

echo
echo "======== SUMMARY ========"
if grep -qF 'VERDICT: Chrome has Ozone 0002+0003 markers' "$LOG" 2>/dev/null; then
  echo "  Chrome patches: 0002+0003 PRESENT"
else
  echo "  Chrome patches: MISSING or section 0 incomplete"
fi
echo -n "  chronos probe PASS: "
grep -cF 'drm-chronos-probe: PASS' "$LOG" 2>/dev/null || echo 0
echo -n "  Unable to initialize GBM: "
grep -cF 'Unable to initialize GBM' /var/log/chrome/chrome 2>/dev/null || echo 0
echo -n "  GetDisplays >0: "
grep -E 'GetDisplays: [1-9]' /var/log/chrome/chrome 2>/dev/null | wc -l || echo 0
echo -n "  forcing legacy (runtime): "
grep -cF 'forcing legacy' /var/log/chrome/chrome 2>/dev/null || echo 0
echo -n "  Modeset succeeded: "
grep -cF 'Modeset succeeded' /var/log/chrome/chrome 2>/dev/null || echo 0
if [ -f /usr/local/tmp/drm-addfb.log ]; then
  echo -n "  ioctl SETCRTC: "
  grep -cF 'ioctl SETCRTC' /usr/local/tmp/drm-addfb.log 2>/dev/null || echo 0
  echo -n "  ioctl PAGE_FLIP: "
  grep -cF 'ioctl PAGE_FLIP' /usr/local/tmp/drm-addfb.log 2>/dev/null || echo 0
  echo -n "  ADDFB2: "
  grep -cF 'ADDFB2' /usr/local/tmp/drm-addfb.log 2>/dev/null || echo 0
fi
echo "  full log: $LOG2"
echo "  Ubuntu pull:"
echo "    sudo ./tools/pull-nvidia-debug-logs.sh /dev/nvme1n1 && ./tools/verify-modeset-from-logs.sh"
echo "======== SUMMARY end ========"
snap
