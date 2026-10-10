# Auto-debug (headless Stage 3 capture)

**Primary diagnosis loop for this project.** VT2 login races with frecon / Ash on
nvidia-drm, so we do **not** rely on Ctrl-Alt-F2 for graphics bring-up. Arm a
one-shot flag from Ubuntu, boot ChromiumOS, power off, pull logs back to the host.

Pink splash on the RTX HDMI means nvidia-drm fbdev is alive. That is expected and
good — it is not a failure by itself.

## Why this exists

| Problem | Auto-debug answer |
| --- | --- |
| VT2 login races frecon / DRM master | No console login required |
| Blind or frozen Ash after logo | Flag runs `debug.sh`, then you power off |
| Need Chrome ERROR / pageflip evidence after UI | Soft capture without wiping the session |
| Slow edit loop on NVMe | Copy scripts from Ubuntu → H-STATE / ROOT-A |

## Quick loop

ChromiumOS disk idle under Ubuntu (typically `/dev/nvme1n1`):

```bash
cd "/home/gooberheads/CodeEnv/NVIDIA cross ChromeOS"

# Install scripts + GBM/EGL shims + Upstart job, then arm one-shot flag
sudo ./tools/arm-nvidia-auto-debug.sh /dev/nvme1n1

# Optional: also pause Ash so VT2 stays usable (~3 min)
# sudo ./tools/arm-nvidia-auto-debug.sh /dev/nvme1n1 --hold-ui
```

Boot ChromiumOS. Wait ~90s (logo / pink / black / login UI are all fine). Power off
(or SSH if available), then on Ubuntu:

```bash
sudo ./tools/pull-nvidia-debug-logs.sh /dev/nvme1n1
./tools/verify-modeset-from-logs.sh
```

Pulled files land in the repo root (`nvidia-debug.log`, `drm-addfb.log`,
`gbm-compat.log`, `nvidia-auto-debug-upstart.log`, and when present `chrome.log` /
`chrome-capture-*.txt`). They are gitignored — keep them local for analysis.

## Soft capture (UI already up — prefer this after login appears)

Full `debug.sh` stops `ui` and can truncate the session you care about. After Ash
shows Get Started / login:

```bash
# From Ubuntu first (once), refresh tools onto disk:
sudo ./tools/copy-sbin-scripts-to-disk.sh /dev/nvme1n1
```

On the device (SSH or VT2):

```bash
/usr/sbin/capture-chrome-logs
# or: /usr/sbin/scripts/capture-chrome-logs.sh
```

Power off → pull as above. Soft capture does **not** consume the auto-debug flag
and does not re-run the destructive probe path.

## Flags (H-STATE `unencrypted/`)

| Flag file | Effect |
| --- | --- |
| `nvidia-auto-debug` | One-shot: stop `ui`, run `nvidia-generic-debug` / `debug.sh`, delete flag |
| `nvidia-hold-ui` | Keep Ash stopped briefly for VT2 (or pair with auto-debug) |

Upstart job: `nvidia-generic-auto-debug.conf` → `/etc/init/` on ROOT-A via
`copy-sbin-scripts-to-disk.sh` / `arm-nvidia-auto-debug.sh`.

## What `debug.sh` proves

Rough sections (see the script for the live layout):

0. Chrome Ozone 0002/0003 binary markers  
A–B. Nodes, frecon, DRM master, chronos open/GBM probe  
C–E. Modeset / AddFB / pageflip / Chrome ERROR scrape  

`verify-modeset-from-logs.sh` scores the pull: legacy KMS, Modeset succeeded,
SETCRTC/PAGE_FLIP, AddFB shim hits, common EGL/GBM failure strings.

## Related tools

| Tool | Role |
| --- | --- |
| `tools/arm-nvidia-auto-debug.sh` | Copy toolkit + arm flag |
| `tools/copy-sbin-scripts-to-disk.sh` | Refresh ROOT-A + stateful sbin without arming |
| `tools/pull-nvidia-debug-logs.sh` | Mount H-STATE → repo root logs |
| `tools/verify-modeset-from-logs.sh` | Pass/fail summary of a pull |
| `tools/copy-nvidia-egl-libs-to-disk.sh` | NVIDIA EGL/GLES libs onto rootfs |
| `tools/rebuild-chrome-0003.sh` | Rebuild chromeos-chrome with Ozone 0003 |
| `files/scripts/debug.sh` | On-device full probe |
| `files/scripts/capture-chrome-logs.sh` | Soft Chrome log capture |

Source lives under
`overlay/overlay-nvidia-generic/chromeos-base/nvidia-generic-auth/files/`.
