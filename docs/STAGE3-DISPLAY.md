# Stage 3 display — development status

Ash on **nvidia-drm** (RTX HDMI) with offline local accounts. This document tracks
what landed, what still hurts, and how we debug without VT2.

For the capture loop itself, see **[AUTO-DEBUG.md](AUTO-DEBUG.md)** — that is the
default workflow for this phase.

## Milestone (2026-10-10)

| Observation | Meaning |
| --- | --- |
| Pink splash → black → Chromebook-like boot | nvidia-drm fbdev + Ash present path is alive |
| Login / Get Started UI appears | Ozone legacy KMS + GBM/EGL path reached composited UI |
| Low framerate | Present/pageflip or vsync path still wrong or software-heavy |
| Mouse exists but invisible | Cursor plane / hotspot / HW cursor not wired on this path |
| Horizontal black tearing / chunk bands | Incomplete pageflips or master/buffer handoff under load |

**Not done yet:** smooth interactive Ash, visible cursor, tear-free flips, Steam.

## What we built to get here

1. **Ozone prefer nvidia-drm + legacy KMS** (`patches/chrome/0002…`, `0003…`)  
   Treat nvidia connectors with modes as connected, commit modeset, recover DRM
   master, sync display IDs so `SchedulePageFlip` runs.

2. **Frecon / DRM master release** (`release-nvidia-drm-master.sh`, Upstart before `ui`)  
   So chronos can CREATE_DUMB / SetMaster on `card2`.

3. **Device nodes + ACLs** (`create-nvidia-nodes.sh`, udev, `nvidia-devnodes.conf`)  
   chronos needs RW on NVIDIA char nodes and DRI nodes for GBM.

4. **GBM / AddFB shims** (`gbm-minigbm-compat.c`, `drm-addfb-compat.c`)  
   Bridge minigbm expectations and AddFB2 quirks on nvidia-drm.

5. **NVIDIA-first EGL wrapper** (`chrome-nvidia-egl`, `enable-nvidia-egl.sh`)  
   Avoid Mesa EGL on the wrong device after `eglCreateImage` / FBO failures.

6. **Headless auto-debug** (this project's diagnosis backbone)  
   Flag-armed Upstart job + `debug.sh` + host pull/verify. Soft
   `capture-chrome-logs` when the UI is already up.

## Current working hypothesis for the three bugs

| Symptom | Likely layer | Next evidence |
| --- | --- | --- |
| Slow framerate | Pageflip cadence / vsync / compositor on legacy KMS | Soft-capture `chrome.log` during interaction; count PAGE_FLIP vs failures |
| Invisible mouse | Cursor BO / plane not scheduled (or ARGB cursor unsupported) | Ozone cursor path + DRM plane dump after UI |
| Horizontal tear bands | Missed flips, partial damage, or master loss mid-frame | drm-addfb / pageflip ERROR lines around freeze |

Do **not** re-run full auto-debug while staring at a good login UI — use soft capture
first so Chrome's live log survives.

## Rebuild / deploy (display stack)

```bash
# Ozone 0003 chrome (hours)
./tools/rebuild-chrome-0003.sh

# Or broader display image path
./tools/rebuild-display-image.sh --with-chrome

# Fast iteration on scripts/shims without full emerge
sudo ./tools/copy-sbin-scripts-to-disk.sh /dev/nvme1n1
sudo ./tools/arm-nvidia-auto-debug.sh /dev/nvme1n1   # when you need a fresh probe
```

Keep a motherboard (iGPU) monitor attached for recovery. Pink on RTX HDMI is the
health signal that the dGPU console path still modesets.
