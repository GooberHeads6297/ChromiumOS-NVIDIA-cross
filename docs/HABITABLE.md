# Habitable OS — persistent GUI + offline local accounts

After Stage 3 display works, daily use needs **every boot → Ash** without Ubuntu
re-arming, and **Gaia stays off** after creating `localuser@localhost` via the
local setup UI.

## 1. Persistent GUI (every boot)

One-shot `arm-nvidia-auto-debug` is for diagnosis only. For normal life:

```bash
cd "/home/gooberheads/CodeEnv/NVIDIA cross ChromeOS"
sudo ./tools/enable-persistent-gui.sh /dev/nvme1n1
```

That installs (via `copy-sbin-scripts-to-disk.sh`):

| Piece | Role |
| --- | --- |
| `/etc/init/nvidia-gui-bringup.conf` | Runs **before** `ui` every boot |
| `/usr/sbin/nvidia-gui-bringup` | Nodes, frecon kill, `drm-modeset-test` (modeset-target), chrome-nvidia-egl |
| GBM/AddFB shims on stateful | Present path that made RTX Ash work |
| Auth flags in `chrome_dev.conf` | `--disable-gaia-services`, oobe-skip, etc. |

Clears any leftover `nvidia-auto-debug` / `nvidia-hold-ui` flags so Upstart does
not stop Ash for probing.

**Tradeoff:** frecon is killed each boot so Ash keeps DRM master → VT2 text
console blanks. Use SSH or soft-capture for logs.

Expect: pink splash → Ash login **every** reboot. Log:
`/mnt/stateful_partition/unencrypted/nvidia-gui-bringup.log`.

## 2. Local account + auto Gaia disable

On the device (Guest OK for install; sign out of Guest before password):

1. Open **http://127.0.0.1:17891/**
2. Set password for `localuser@localhost`

That calls `create-local-account.sh`, then automatically:

```text
/usr/sbin/disable-gaia-after-local-account localuser@localhost
```

Which:

- Merges `--disable-gaia-services` / offline login flags into `/etc/chrome_dev.conf`
- Runs `register-local-login.sh` (password pod / Local State)
- Soft-restarts `ui` so Ash shows the pod

Manual re-run if needed:

```bash
disable-gaia-after-local-account localuser@localhost
```

Do **not** use Chrome **Create local account → Next**.

## 3. Diagnosis (optional)

When something regresses:

```bash
sudo ./tools/arm-nvidia-auto-debug.sh /dev/nvme1n1   # one-shot probe
# boot ~90s, power off
sudo ./tools/pull-nvidia-debug-logs.sh /dev/nvme1n1
./tools/verify-modeset-from-logs.sh
```

Then re-enable normal boots:

```bash
sudo ./tools/enable-persistent-gui.sh /dev/nvme1n1
```

See also: [AUTO-DEBUG.md](AUTO-DEBUG.md), [STAGE3-DISPLAY.md](STAGE3-DISPLAY.md),
[LOCAL-ACCOUNTS.md](LOCAL-ACCOUNTS.md).
