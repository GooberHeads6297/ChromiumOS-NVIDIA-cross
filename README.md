# ChromiumOS-NVIDIA-cross

ChromiumOS board `nvidia-generic`: NVIDIA open kernel modules, dual-GPU bring-up
(RTX + Raphael iGPU recovery), software TPM, and **offline local accounts** (no Google
login, no FydeOS binaries).

Read [SAFETY.md](SAFETY.md) first. Ubuntu on `sda` is never a flash or install target.

| Detail | Where |
| --- | --- |
| **Auto-debug (default Stage 3 loop)** | **[docs/AUTO-DEBUG.md](docs/AUTO-DEBUG.md)** |
| Stage 3 display status / open bugs | [docs/STAGE3-DISPLAY.md](docs/STAGE3-DISPLAY.md) |
| Full USB → NVMe → Steam runbook | [docs/INSTALL.md](docs/INSTALL.md) |
| Local accounts / cryptohome / Crostini | [docs/LOCAL-ACCOUNTS.md](docs/LOCAL-ACCOUNTS.md) |
| Settled hardware and earlier handoff | [docs/HANDOFF.md](docs/HANDOFF.md) |

---

## Auto-debug — how we develop Stage 3

VT2 is unreliable once frecon and Ash fight over nvidia-drm master. **Arm a one-shot
debug flag from Ubuntu, boot, power off, pull logs.** That loop is the backbone of
this project's display work — treat it as first-class, not an afterthought.

```bash
cd "/home/gooberheads/CodeEnv/NVIDIA cross ChromeOS"

# Disk idle under Ubuntu (example: internal ChromiumOS NVMe)
sudo ./tools/arm-nvidia-auto-debug.sh /dev/nvme1n1
# boot CrOS ~90s (pink splash on RTX HDMI = dGPU alive), power off, then:
sudo ./tools/pull-nvidia-debug-logs.sh /dev/nvme1n1
./tools/verify-modeset-from-logs.sh
```

When login UI is already up and you need Chrome's live ERROR/pageflip lines **without**
stopping `ui`:

```bash
sudo ./tools/copy-sbin-scripts-to-disk.sh /dev/nvme1n1   # once, from Ubuntu
# on device: /usr/sbin/capture-chrome-logs
# then pull again from Ubuntu
```

Full flag table, soft-capture notes, and what `debug.sh` sections mean:
**[docs/AUTO-DEBUG.md](docs/AUTO-DEBUG.md)**.

---

## Status (2026-10-10)

| Stage | What it proves | State |
| --- | --- | --- |
| 0 | Safety harness | Done |
| 1–2 | USB/NVMe boot, NVIDIA modules, pink RTX splash | Working |
| Auth | Local cryptohome + login pod, no Google | In tree / on disk |
| **3** | **Ash UI on nvidia-drm (RTX HDMI)** | **UI boots (pink → login). Still: low FPS, invisible mouse, horizontal tear bands** |
| 4 | Steam/Proton | Blocked on Stage 3 polish |

Open Stage 3 bugs and the stack we used to get past black screens:
[docs/STAGE3-DISPLAY.md](docs/STAGE3-DISPLAY.md).

---

## Easy path (checkout already exists)

From this repo on Ubuntu, **not** as root. `cros_sdk` must run as your user.

### 1. Rebuild image (auth + BSP DRM ACL + login_manager + test image)

```bash
cd "/home/gooberheads/CodeEnv/NVIDIA cross ChromeOS"
./tools/rebuild-auth-image.sh --flash /dev/sdc
```

That also ships `/dev/dri/card*` as `0660 video`, `nvidia-drm modeset=1 fbdev=1`,
`simpledrm` blacklisted, `--disable-gpu-sandbox`, and an Upstart job that unbinds
fbcon DRM master before `ui` so Ash/minigbm can CREATE_DUMB. Does **not** rebuild
chromeos-chrome.

Omit `--flash` to build only. Then:

```bash
./tools/flash.sh --board nvidia-generic --target usb --device /dev/sdc
```

Confirm the image actually has the helpers (host, after build):

```bash
./tools/confirm-auth-image.sh
```

You want `/usr/sbin/create-local-account.sh` and `/usr/sbin/register-local-login.sh` listed.

**First-time machine** (no `~/chromiumos` yet): `./sdk/bootstrap.sh --check` then
`./sdk/bootstrap.sh`, `./tools/fetch-nvidia.sh`, then
`./sdk/build.sh --board nvidia-generic all`. That is many hours. After that, use
`rebuild-auth-image.sh` for auth/login changes.

### 2. Boot the USB

Developer mode, monitor on the **motherboard** (iGPU) for recovery. Root console is
**Ctrl-Alt-F2** (VT2). Return to the UI with Ctrl-Alt-F1. Prefer
[auto-debug](docs/AUTO-DEBUG.md) when VT2 fights the GPU stack.

On the device:

```bash
verify-stage2.sh
ls -l /usr/sbin/create-local-account.sh /usr/sbin/register-local-login.sh
```

If those scripts are missing, this stick was flashed before `nvidia-generic-auth`. Rebuild
and reflash; do not expect Ubuntu `scp` (this machine often has no SSH into ChromiumOS).

### 3. Install to NVMe

On the **live USB**, Guest (or a browser) → **http://127.0.0.1:17891/** — pick the
internal disk, dry-run, type `erase DISKNAME`. Same checks as `install-to-disk.sh`
(Ubuntu UUID refuse). Shell still works:

```bash
install-to-disk.sh --dst /dev/nvme0n1 --dry-run
install-to-disk.sh --dst /dev/nvme0n1
```

USB vaults **do not** copy to NVMe. After NVMe boot, open `:17891` again (not Guest)
and set `localuser@localhost`’s password.

Ash on the RTX needs Ozone patches + shims (see Stage 3 doc). Fast script/shim push
without a full emerge:

```bash
sudo ./tools/copy-sbin-scripts-to-disk.sh /dev/nvme1n1
```

Chrome rebuild with modeset-commit patch (hours):

```bash
./tools/rebuild-chrome-0003.sh
# or: ./tools/rebuild-display-image.sh --with-chrome
```

Pass `--with-chrome` on `rebuild-display-image.sh` for the broader display path.
Keep a motherboard monitor for recovery. **Pink splash on RTX HDMI = nvidia-drm
fbdev alive.**

---

## Account setup — device

**GUI:** http://127.0.0.1:17891/ (URL also printed on VT2).

**CLI:** stay on login / VT2 as **root**. **Sign out of Guest** first.

**Do not** use Chrome **Create local account** → **Next**.

```bash
ensure-software-tpm.sh
cryptohome --action=unmount
create-local-account.sh --force-remove --user localuser@localhost --password 'testpass'
register-local-login.sh --user localuser@localhost
```

Default AuthFactor label is **`local-password`**. Flag form `--user EMAIL` is required.

Then Ctrl-Alt-F1, sign in on the **localuser** pod. Optional:

```bash
verify-local-account.sh --user localuser@localhost --password 'testpass'
verify-crostini-host.sh
verify-stage3.sh
```

Guest sessions gray out **Settings → Linux**; a persistent local user should not.

| Command | Role |
| --- | --- |
| `create-local-account.sh` | Cryptohome vault + Chrome login pod |
| `register-local-login.sh` | Write `/home/chronos/Local State` only |
| `ensure-software-tpm.sh` | Simulator TPM path |
| `verify-local-account.sh` | Auth + mount gate |
| `verify-crostini-host.sh` | KVM / Termina host bits |
| `collect-auth-debug.sh` | Logs for a failed login |
| `install-to-disk.sh` | USB → internal disk |

Host copies of the same scripts live under `tools/`. Deep notes:
[docs/LOCAL-ACCOUNTS.md](docs/LOCAL-ACCOUNTS.md).

---

## Hardware (this machine)

- **RTX 4070 Ti SUPER** AD103 `10de:2705`, host driver **595.91.07**
- Ryzen 9 7900X, Raphael iGPU `amdgpu`
- Ubuntu on `sda` (blocked). USB test stick typically `sdc`. Internal ChromiumOS is the
  NVMe you pass to `install-to-disk.sh` / auto-debug.

## Layout

| Path | Purpose |
| --- | --- |
| [SAFETY.md](SAFETY.md) | GPU / disk guardrails |
| [docs/AUTO-DEBUG.md](docs/AUTO-DEBUG.md) | **Headless Stage 3 capture loop** |
| [docs/STAGE3-DISPLAY.md](docs/STAGE3-DISPLAY.md) | Ash-on-RTX status and open bugs |
| `sdk/bootstrap.sh` / `sdk/build.sh` | Host prep and image build |
| `overlay/overlay-nvidia-generic/` | Board overlay (drivers, BSP, auth, shims) |
| `patches/login_manager/` | Skip Gaia; always apply `chrome_dev.conf` |
| `patches/chrome/` | Ozone prefer nvidia-drm + modeset commit (0002/0003) |
| `tools/arm-nvidia-auto-debug.sh` | Arm one-shot auto-debug on disk |
| `tools/pull-nvidia-debug-logs.sh` | Pull H-STATE logs into repo root |
| `tools/verify-modeset-from-logs.sh` | Score a pull |
| `tools/copy-sbin-scripts-to-disk.sh` | Push sbin/shims without full emerge |
| `tools/rebuild-auth-image.sh` | Fast rebuild for auth + login_manager |
| `tools/rebuild-display-image.sh` | minigbm / optional chromeos-chrome |
| `tools/rebuild-chrome-0003.sh` | Ozone 0003 chrome rebuild |
| `tools/flash.sh` | USB writer with disk allowlist |
| `tools/install-to-disk.sh` | Device-side NVMe install |
| [docs/INSTALL.md](docs/INSTALL.md) | Full phased runbook |
| [docs/TEST-USB.md](docs/TEST-USB.md) | USB boot / dGPU console checks |
