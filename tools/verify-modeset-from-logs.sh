#!/bin/bash
# Verify Ash present path from pulled debug logs (post-0003 / shim encoder fix).
# Usage: ./tools/verify-modeset-from-logs.sh [nvidia-debug.log] [drm-addfb.log]
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEBUG="${1:-$REPO_ROOT/nvidia-debug.log}"
ADDFB="${2:-$REPO_ROOT/drm-addfb.log}"

fail=0
ok() { printf 'OK  %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; fail=1; }
have() { grep -qF "$1" "$2" 2>/dev/null; }
count() { grep -cF "$1" "$2" 2>/dev/null || echo 0; }

echo "debug=$DEBUG"
echo "addfb=$ADDFB"

if [ ! -f "$DEBUG" ]; then
  bad "missing $DEBUG"
  exit 1
fi

# Chrome Ozone binary markers (section 0 from debug.sh)
if have 'VERDICT: Chrome has Ozone 0002+0003 markers' "$DEBUG"; then
  ok "Chrome binary has Ozone 0002+0003"
elif have 'VERDICT: Chrome MISSING Ozone markers' "$DEBUG"; then
  bad "Chrome binary missing Ozone markers (wrong/old chrome on disk)"
elif have 'HIT  nvidia-drm: forcing legacy KMS' "$DEBUG"; then
  ok "Chrome binary has legacy-KMS marker"
else
  printf 'WARN section 0 Chrome patch probe missing (copy new debug.sh)\n'
fi

# Chrome Ozone runtime
if have 'forcing legacy' "$DEBUG"; then ok "legacy KMS active at runtime"; else bad "no forcing legacy KMS at runtime"; fi
# Prefer chrome WARNING line; ignore section-D "  0	Modeset succeeded" count rows.
if have 'SchedulePageFlip: no controller_' "$DEBUG"; then
  bad "SchedulePageFlip: no controller_ (CommitModeset never bound window)"
fi
if grep -E 'WARNING.*Modeset succeeded\.|Modeset succeeded\.$' "$DEBUG" >/dev/null 2>&1; then
  ok "Modeset succeeded (chrome WARNING)"
elif grep -E $'^\s*[1-9][0-9]*\tModeset succeeded' "$DEBUG" >/dev/null 2>&1; then
  ok "Modeset succeeded count > 0"
else
  bad "Modeset succeeded still 0 / missing"
fi
if grep -E 'GetDisplays: [1-9]|GetDisplays: id=' "$DEBUG" >/dev/null 2>&1; then
  ok "GetDisplays logging (0003 runtime)"
else
  printf 'WARN GetDisplays runtime log missing (binary may still have marker)\n'
fi
# Binary probe HIT is not a runtime SchedulePageFlip failure.
if grep -E 'SchedulePageFlip: no controller_ widget=' "$DEBUG" >/dev/null 2>&1; then
  bad "SchedulePageFlip still has no controller_"
else
  ok "no SchedulePageFlip no-controller spam"
fi
if have 'Failed to get system egl display' "$DEBUG"; then
  bad "EGL init failed (Failed to get system egl display)"
fi
if have 'GLDisplayEGL::Initialize failed' "$DEBUG"; then
  bad "GLDisplayEGL::Initialize failed"
fi
# Match Chrome ERROR lines only — SUMMARY "Unable to initialize GBM: 0" is not a failure.
if grep -E 'ERROR.*Unable to initialize GBM' "$DEBUG" >/dev/null 2>&1; then
  bad "GBM init Permission denied / failed (fix nvidia nodes + frecon master)"
elif have 'drm-chronos-probe: PASS' "$DEBUG"; then
  ok "chronos DRM/NVIDIA probe PASS"
elif have 'drm-chronos-probe: FAIL' "$DEBUG"; then
  bad "chronos DRM/NVIDIA probe FAIL"
fi
if grep -qE 'eglCreateImage failed with 0x' "$DEBUG"; then
  bad "eglCreateImage failed (pixmap→GL bind broken — GPU crash loop)"
fi
if grep -qF "Couldn't create Gbm Device at /dev/dri/renderD128" "$DEBUG"; then
  bad "GBM on amdgpu renderD128 (should use nvidia card2/renderD129)"
fi
if grep -qF 'auto-SetCrtc OK' "$ADDFB" 2>/dev/null || grep -qF 'auto-SetCrtc OK' "$DEBUG"; then
  ok "shim auto-SetCrtc OK (KMS scanout path alive)"
fi
if [ -f "${REPO_ROOT}/gbm-compat.log" ] && grep -qE 'nvidia-bo ok|dumb ok' "${REPO_ROOT}/gbm-compat.log" 2>/dev/null; then
  ok "GBM BO allocations logged"
fi
if grep -qF '0x00008CD6' "$DEBUG" || grep -qF 'FramebufferGL.cpp' "$DEBUG"; then
  bad "GL FBO incomplete 0x8CD6 (buffers not GPU-renderable — need NVIDIA allocator BOs)"
fi
if grep -qF 'Unable to initialize SkSurface' "$DEBUG"; then
  bad "Unable to initialize SkSurface"
fi
if grep -E 'GetDisplays: 0 display' "$DEBUG" >/dev/null 2>&1; then
  bad "GetDisplays: 0 display(s)"
fi

if [ -f "$ADDFB" ]; then
  setcrtc=$(grep -cF 'ioctl SETCRTC' "$ADDFB" || true)
  pageflip=$(grep -cF 'ioctl PAGE_FLIP' "$ADDFB" || true)
  pageflip=$((pageflip + $(grep -cF 'PageFlip ' "$ADDFB" || true)))
  enc=$(grep -cF 'encoders=' "$ADDFB" || true)
  echo "  ioctl SETCRTC=$setcrtc  PAGE_FLIP/PageFlip=$pageflip  fake encoders lines=$enc"
  if [ "${setcrtc:-0}" -gt 1 ]; then ok "Chrome/shim SETCRTC > 1"; else bad "SETCRTC count $setcrtc (want >1 from Chrome)"; fi
  if [ "${pageflip:-0}" -gt 0 ]; then ok "PAGE_FLIP present"; else bad "no PAGE_FLIP (compositor not presenting)"; fi
  if [ "${enc:-0}" -gt 0 ]; then ok "fake GETCONNECTOR fills encoders"; else
    printf 'WARN fake GETCONNECTOR encoders= not logged (old shim?)\n'
  fi
else
  bad "missing $ADDFB"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS: modeset/present path looks healthy"
  exit 0
fi
echo "FAIL: see above (copy shim + rebuild Chrome with 0003, then re-run debug.sh)"
exit 1
