# ChromiumOS-NVIDIA-cross

ChromiumOS board `nvidia-generic`: NVIDIA open kernel modules, dual-GPU bring-up
(RTX + Raphael iGPU recovery), software TPM, and **offline local accounts** (no Google
login, no FydeOS binaries).

Read [SAFETY.md](SAFETY.md) first. Ubuntu on `sda` is never a flash or install target.

| Detail | Where |
| --- | --- |
| Full USB → NVMe → Steam runbook | [docs/INSTALL.md](docs/INSTALL.md) |
| Local accounts / cryptohome / Crostini | [docs/LOCAL-ACCOUNTS.md](docs/LOCAL-ACCOUNTS.md) |
| Settled hardware and next milestone | [docs/HANDOFF.md](docs/HANDOFF.md) |

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
**Ctrl-Alt-F2** (VT2). Return to the UI with Ctrl-Alt-F1.

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

Ash on the RTX (not only iGPU/fbcon) needs the minigbm `nvidia-drm` backend:

```bash
./tools/rebuild-display-image.sh --minigbm-only
```

Chrome's `Unable to initialize GBM ... Permission denied (13)` is a **stale errno**:
`gbm_create_device()` returns NULL because minigbm has no backend matching the
`nvidia-drm` driver name, and nothing is denying access. The backend ships in
`media-libs/minigbm-0.0.1-r810` (overlay) — a git-apply into `src/platform/minigbm`
does not reach the image, because a non-`cros_workon` emerge builds
`CROS_WORKON_TREE`. Verify on the device with `nvidia-gbm-probe` and:

```bash
grep -aF nvidia-drm /usr/lib64/libminigbm.so.1.0.0
```

Pass `--with-chrome` to also rebuild Ozone's prefer-nvidia-drm patch (hours). Keep a
motherboard monitor for recovery.

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

## Status

| Stage | What it proves | State |
| --- | --- | --- |
| 0 | Safety harness | Implemented |
| 1–3 | USB boot, NVIDIA modules, dual output | Working on this hardware |
| Auth | Local cryptohome + login pod, no Google | In tree; needs patched `chromeos-login` in the flashed image |
| 4 | Steam/Proton | After NVMe + signed-in local user |

## Hardware (this machine)

- **RTX 4070 Ti SUPER** AD103 `10de:2705`, host driver **595.91.07**
- Ryzen 9 7900X, Raphael iGPU `amdgpu`
- Ubuntu on `sda` (blocked). USB test stick typically `sdc`. Internal ChromiumOS is the
  NVMe you pass to `install-to-disk.sh`.

## Layout

| Path | Purpose |
| --- | --- |
| [SAFETY.md](SAFETY.md) | GPU / disk guardrails |
| `sdk/bootstrap.sh` / `sdk/build.sh` | Host prep and image build |
| `overlay/overlay-nvidia-generic/` | Board overlay (drivers, BSP, auth) |
| `patches/login_manager/` | Skip Gaia; always apply `chrome_dev.conf` |
| `patches/chrome/` | Ozone prefers nvidia-drm |
| `tools/rebuild-auth-image.sh` | Fast rebuild for auth + login_manager |
| `tools/rebuild-display-image.sh` | minigbm nvidia-drm backend; optional chromeos-chrome |
| `tools/flash.sh` | USB writer with disk allowlist |
| `tools/install-to-disk.sh` | Device-side NVMe install |
| [docs/INSTALL.md](docs/INSTALL.md) | Full phased runbook |
| [docs/TEST-USB.md](docs/TEST-USB.md) | USB boot / dGPU console checks |
