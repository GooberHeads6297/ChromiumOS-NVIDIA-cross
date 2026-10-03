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

### 1. Rebuild image (auth package + login_manager + test image)

```bash
cd "/home/gooberheads/CodeEnv/NVIDIA cross ChromeOS"
./tools/rebuild-auth-image.sh --flash /dev/sdc
```

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

### 3. Install to NVMe (from ChromiumOS, never Ubuntu)

`install-to-disk.sh` must run **on the live ChromiumOS USB**, as root. It wipes the
destination disk. Dry-run first. Confirm the NVMe node (`nvme0n1` vs `nvme1n1`) on **this**
boot.

```bash
install-to-disk.sh --dst /dev/nvme0n1 --dry-run
install-to-disk.sh --dst /dev/nvme0n1
```

USB cryptohome vaults **do not** copy to NVMe. After reboot from NVMe, create the local
user **again**.

---

## Account setup (CLI) — do this on the device

Stay on the login screen or VT2 as **root**. **Sign out of Guest** first (Guest makes
`PreparePersistentVault` fail with `CRYPTOHOME_ERROR_MOUNT_FATAL`).

**Do not** use Chrome **Create local account** → **Next**. That Gaia fallback crashes
login Chrome and can powerwash when API keys are absent.

```bash
ensure-software-tpm.sh
cryptohome --action=unmount

# First time, or after a failed half-create:
create-local-account.sh --force-remove --user localuser@localhost --password 'testpass' --key-label gaia

# If the vault already exists and you only need the login pod:
register-local-login.sh --user localuser@localhost
```

`create-local-account.sh` already calls `register-local-login.sh` when that file is in
`/usr/sbin`. Flag form is required: `--user EMAIL`, not a bare email.

Then Ctrl-Alt-F1. Sign in on the **localuser** pod with the same password. If you still
get Google **Verify it's you**, the image’s `session_manager` is not applying
`--disable-gaia-services` — rebuild with `rebuild-auth-image.sh` (it emerges
`chromeos-login` with `patches/login_manager/nvidia-generic-local-accounts.patch`). A
live workaround on a test image:

```bash
mount -o remount,rw /
printf '%s\n' '#!/bin/sh' 'exit 0' > /usr/sbin/is_developer_end_user
chmod 0755 /usr/sbin/is_developer_end_user
printf '%s\n' '--oobe-skip-to-login' '--allow-failed-policy-fetch-for-test' '--disable-gaia-services' '--skip-force-online-signin-for-testing' >> /etc/chrome_dev.conf
restart ui
```

If the password field rejects `testpass` but you created with label `password`, recreate
with `--key-label gaia` (Chrome’s login screen looks up that factor). Optional check:

```bash
verify-local-account.sh --user localuser@localhost --password 'testpass'
verify-crostini-host.sh
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
| `tools/rebuild-auth-image.sh` | Fast rebuild for auth + login_manager |
| `tools/flash.sh` | USB writer with disk allowlist |
| `tools/install-to-disk.sh` | Device-side NVMe install |
| [docs/INSTALL.md](docs/INSTALL.md) | Full phased runbook |
| [docs/TEST-USB.md](docs/TEST-USB.md) | USB boot / dGPU console checks |
