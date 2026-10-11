# Stage 3 display — development status

Ash on **nvidia-drm** (RTX HDMI) with offline local accounts. This document tracks
what landed, what still hurts, and how we debug without VT2.

For the capture loop itself, see **[AUTO-DEBUG.md](AUTO-DEBUG.md)** — that is the
default workflow for this phase.

## Milestone (2026-10-10)

| Observation | Meaning |
| --- | --- |
| Pink splash → black → Chromebook-like boot | nvidia-drm fbdev + Ash present path is alive |
| Login / Get Started UI appears | Shim bootstrap SetCrtc + composited Ash (see root cause below) |
| Low framerate | **No real pageflips** — compositor presents without `controller_` |
| Mouse exists but invisible | Cursor needs pageflip / cursor plane; input still works |
| Horizontal black tearing / chunk bands | Front-buffer-ish updates without vsync flips |

**Not done yet:** Chrome CommitModeset success → `SchedulePageFlip` → smooth Ash, visible cursor, tear-free flips, Steam.

## Root cause (pinned from logs)

All three symptoms share one failure:

1. Ozone **Test-modeset** fails with hundreds of `Failed to create scanout buffer`
   (logs show thrash on 720x576 / 640x480, then display disabled).
2. Host: `Display configuration failed. No modeset was attempted.`
3. GPU: `SchedulePageFlip: no controller_` (×30) — presents ACK without DRM flips.
4. Shim does **one** `auto-SetCrtc` on the first 3440×1440 AddFB → you see a
   Chromebook-like UI, but Chrome never owns the present path (`SETCRTC=0`,
   `PAGE_FLIP=0` in the AddFB shim).

So the UI is a **bootstrap scanout**, not a healthy Ozone pageflip loop. That
matches slow FPS, invisible cursor, and tear bands.

### Likely blockers inside Test-modeset

| Factor | Evidence | Fix in tree |
| --- | --- | --- |
| EDID mode spam | Was 720×576 thrash; after shim: only 3440×1440 | Shim `count_modes=1` (**landed** — failures 240→20) |
| Mesa GBM rejects SCANOUT formats | Override logs | `is_format_supported` for XR24/AR24 |
| ChromeOS create+**import** verify | Create OK; `import FAILED type=21765` (FD_MODIFIER). Chrome destroys a successful import immediately after the check. | Shim returns disposable **FAKE-OK** BO on import fail — **no Chrome rebuild**. Ozone 0004 optional backup. |

## What we built to get here

1. **Ozone prefer nvidia-drm + legacy KMS** (`patches/chrome/0002…`, `0003…`)  
   Treat nvidia connectors with modes as connected, commit modeset, recover DRM
   master, sync display IDs so `SchedulePageFlip` runs *once controller_ exists*.

2. **Frecon / DRM master release** (`release-nvidia-drm-master.sh`, Upstart before `ui`)  
   So chronos can CREATE_DUMB / SetMaster on `card2`.

3. **Device nodes + ACLs** (`create-nvidia-nodes.sh`, udev, `nvidia-devnodes.conf`)  
   chronos needs RW on NVIDIA char nodes and DRI nodes for GBM.

4. **GBM / AddFB shims** (`gbm-minigbm-compat.c`, `drm-addfb-compat.c`)  
   NVIDIA-renderable BOs, fake CONNECTED connector, bootstrap SetCrtc, format
   support overrides, single preferred mode.

5. **NVIDIA-first EGL wrapper** (`chrome-nvidia-egl`, `enable-nvidia-egl.sh`)  
   Avoid Mesa EGL on the wrong device after `eglCreateImage` / FBO failures.

6. **Headless auto-debug** (this project's diagnosis backbone)  
   Flag-armed Upstart job + `debug.sh` + host pull/verify. Soft
   `capture-chrome-logs` when the UI is already up.

## Pass criteria for the present-path fix

After soft-capture or a normal boot pull:

```text
Modeset succeeded > 0
ioctl PAGE_FLIP > 0   (drm-addfb.log)
SchedulePageFlip: no controller_  == 0
```

UI should feel vsync-smooth; software/HW cursor should appear; tear bands should
drop sharply.

## Rebuild / deploy (display stack)

```bash
# Fast: rebuild shims on Ubuntu, push to NVMe (no chrome emerge)
./tools/build-display-shims.sh
sudo ./tools/copy-sbin-scripts-to-disk.sh /dev/nvme1n1
# boot normally (do NOT arm auto-debug if you want to keep the UI)
# after login UI: /usr/sbin/capture-chrome-logs
sudo ./tools/pull-nvidia-debug-logs.sh /dev/nvme1n1
./tools/verify-modeset-from-logs.sh

# Slow: Ozone chrome rebuild (hours)
./tools/rebuild-chrome-0003.sh
```

Keep a motherboard (iGPU) monitor attached for recovery. Pink on RTX HDMI is the
health signal that the dGPU console path still modesets.
