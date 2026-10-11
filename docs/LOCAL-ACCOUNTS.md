# Local accounts, cryptohome, and NVMe install

## Cryptohome is not bypassed

A “local account” is still a **cryptohome** vault with a password AuthFactor. The dual-boot
mitigation is the **software TPM2 simulator** (`tpm2_simulator` + `vtpm_proxy`), not skipping
cryptohome.

## Linux (Crostini) vs Guest

| Session | Settings → Linux |
| --- | --- |
| **Guest** | Grayed out — expected ChromeOS policy (ephemeral session). Not caused by USB vs NVMe. |
| **Persistent local user** (`localuser@localhost`) | Should be available; image ships `kvm_host` / `containers` / Termina DLC. |

Cryptohome vaults created on VT2 do **not** by themselves create a Chrome login pod.
Chrome only lists users in `/home/chronos/Local State`. After `create-local-account.sh`,
run `register-local-login.sh --user localuser@localhost` (newer images do this automatically).

## USB vs NVMe (order matters)

| When you create the account | Where the vault lives | Survives `install-to-disk`? |
| --- | --- | --- |
| On live USB | USB stateful (`STATE`) | **No** |
| After install, on NVMe | NVMe stateful | **Yes** (until you wipe that disk) |

`tools/install-to-disk.sh` / `chromeos-install` create a **fresh** stateful on the destination.
USB logins do not become NVMe logins.

**Supported hard-test sequence** (all scripts are on-device under `/usr/sbin` after a
successful `rebuild-auth-image.sh` flash)

1. Boot USB → create a local user (optional USB-only test).
2. On the **ChromiumOS USB shell** (not Ubuntu):  
   `install-to-disk.sh --dst /dev/<nvme> --dry-run` then real install (never Ubuntu’s disk).
3. Reboot into NVMe → **create the local account again** → offline sign-in.
4. Drive-picker GUI: Guest on USB → http://127.0.0.1:17891/ (never Flex `--allow-os-install`).

| On-device command | Package |
| --- | --- |
| `create-local-account.sh`, `ensure-software-tpm.sh`, `verify-local-account.sh`, `collect-auth-debug.sh`, `verify-auth-bringup.sh`, `verify-crostini-host.sh` | `chromeos-base/nvidia-generic-auth` |
| `install-to-disk.sh` | `chromeos-base/chromeos-bsp-nvidia-generic` |

Step-by-step gate: [`tools/gate-local-linux-nvme.md`](../tools/gate-local-linux-nvme.md).

## How to create a local user (this image)

### GUI (http://127.0.0.1:17891/)

On the **live USB**, Guest may open that URL: pick the NVMe, dry-run, type `erase DISKNAME`,
install. Ubuntu is refused by filesystem UUID. Do **not** enable ChromeOS Flex
`--allow-os-install`.

After reboot from NVMe, open the same URL (not Guest) and set the password for
`localuser@localhost`. The AuthFactor label is **`local-password`** (the HTTP UI
passes `--key-label local-password` into `create-local-account.sh`).

After create, **`disable-gaia-after-local-account`** runs automatically (from the
HTTP UI and from `create-local-account.sh`): merges `--disable-gaia-services` /
offline flags, runs `register-local-login.sh`, soft-restarts `ui`. See
[HABITABLE.md](HABITABLE.md).

Chrome’s login pod shows a **password** field only when Local State has
`OAuthTokenStatus[email]=4` (VALID) and `UserForceOnlineSignin=false`. Without
that, Ash treats the regular user as needing Google verification. `register-local-login.sh`
writes those prefs; `/etc/chrome_dev.conf` also includes
`--skip-force-online-signin-for-testing` and `--disable-gaia-services`.

If the installed disk was created before that fix (no image rebuild needed):

```bash
# From Ubuntu, with the ChromiumOS NVMe idle:
sudo ./tools/copy-auth-to-disk.sh /dev/nvme0n1
```

VT2 also prints the URL.

### CLI (always works once the package is in the image)

**Sign out of Guest first.** An active Guest session makes
`PreparePersistentVault` fail with `CRYPTOHOME_ERROR_MOUNT_FATAL`. Use VT2 as
`root` after signing out (or reboot and stay on the login screen / VT2).

```bash
ensure-software-tpm.sh
cryptohome --action=unmount
# If a previous attempt half-created the user:
create-local-account.sh --force-remove --user localuser@localhost --password 'choose-a-password'
# Otherwise (default key label is local-password):
create-local-account.sh --user localuser@localhost --password 'choose-a-password'
# reboot, sign in as localuser@localhost
```

If `create-local-account.sh` is missing, this USB was built before `nvidia-generic-auth`
landed. Rebuild/flash with `./tools/rebuild-auth-image.sh --flash /dev/sdc`.

### Login shows Google verification instead of a password field

That means Ash chose `ONLINE_SIGN_IN` because `OAuthTokenStatus` was missing or
invalid for a regular user. Fix without rebuilding:

```bash
sudo ./tools/copy-auth-to-disk.sh /dev/nvme0n1   # from Ubuntu
# or on-device after account create:
register-local-login.sh --user localuser@localhost
restart ui
```

Confirm Local State has `"OAuthTokenStatus": { "localuser@localhost": 4 }` and
`chrome_dev.conf` has `--skip-force-online-signin-for-testing`.

### Do not use Chrome “Create local account” → Next

That screen is Chrome’s Gaia fallback. Without Google API keys, **Next hard-crashes
login Chrome and ChromeOS powerwashes**. Create the user on VT2 with
`create-local-account.sh`, reboot, then pick the existing user pod.

If you already have `--load-extension=.../local-account-ext` in `/etc/chrome_dev.conf`
on a running test image:

```bash
mount -o remount,rw /
sed -i '/local-account-ext/d' /etc/chrome_dev.conf
restart ui
```

## Verify

```bash
verify-local-account.sh --user localuser@localhost --password 'choose-a-password'
verify-crostini-host.sh   # kvm_host / Termina host side; then check Settings as local user
```

Host-side image check (no device boot):

```bash
./tools/confirm-auth-image.sh
```

### Gate before NVMe install

1. No Guest — create local user, sign in as that user.
2. Settings → Linux not grayed out (`verify-crostini-host.sh` PASS as root).
3. Then `install-to-disk.sh --dst /dev/<nvme> --dry-run` → install → recreate user on NVMe.

## Related

- [`docs/research-openfyde-auth.md`](research-openfyde-auth.md) — openFyde harvest
- [`docs/auth-debug-capture.md`](auth-debug-capture.md) — TPM/cryptohome dumps
- [`tools/install-to-disk.sh`](../tools/install-to-disk.sh) — NVMe install wrapper
