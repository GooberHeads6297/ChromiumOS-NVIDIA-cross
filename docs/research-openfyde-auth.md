# openFyde research: TPM / cryptohome / local accounts

Harvested from **public** openFyde repositories only. No FydeOS commercial
binaries. Clones live under `vendor/openfyde-research/` (gitignored via `/vendor/`).

Refresh with:

```bash
./tools/fetch-openfyde-research.sh
```

## Sources

| Repo | Why |
| --- | --- |
| [openFyde/getting-started](https://github.com/openFyde/getting-started) | Build flow; Google / FydeOS API keys for cloud login |
| [openFyde/project-openfyde-patches](https://github.com/openFyde/project-openfyde-patches) | TPM simulator, chromeos-init, cryptohome lockbox, login_manager patches |
| [openFyde/overlay-amd64-openfyde](https://github.com/openFyde/overlay-amd64-openfyde) | Intel PC board USE flags for TPM |
| [openFyde/overlay-amd64-openfyde_apu](https://github.com/openFyde/overlay-amd64-openfyde_apu) | AMD PC board overlay (sibling) |

## What is open vs closed

**Reusable (open):**

- Board USE that prefers a **software TPM2 simulator** over a hardware TPM that another OS may own:
  ```
  USE="${USE} -tpm_dynamic -tpm -tpm_insecure_fallback tpm2_simulator tpm2_simulator_manufacturer"
  USE="${USE} vtpm_proxy"
  ```
  (`overlay-amd64-openfyde/profiles/base/make.defaults`)
- Optional `tpm2_simulator_deprecated` + `tpm_insecure_fallback` for older simulator / lockbox behaviour (commented in the same file; patches under `chromeos-init/files/tpm/` and cryptohome lockbox-cache replacements).
- `apply-chrome-dev-flags-in-base-mode.patch` — apply `/etc/chrome_dev.conf` even when not a “developer end user”.
- Upstream cryptohome AuthSession API (`StartAuthSession` → `CreatePersistentUser` → `PreparePersistentVault` → `AddAuthFactor`).

**Not reused:**

- FydeOS cloud accounts (`account.fydeos.com`) and Developer API keys.
- License / wallpaper / Widevine / ARC sideload patches that are product-specific.
- Any closed FydeOS OOBE “Use local account” Chrome UI (not published as a clean patch in these trees). We implement our own helper + chrome_dev.conf path instead.

## Mapping to nvidia-generic

| openFyde idea | Our tree |
| --- | --- |
| Software TPM2 simulator USE | Already inherited from `amd64-generic` (`-tpm tpm2 tpm2_simulator … vtpm_proxy`). Affirmed in our `profiles/base/make.defaults`. |
| lockbox-cache for simulator | Optional files in `chromeos-base/nvidia-generic-auth` |
| Local username/password | `create-local-account.sh` + HTTP UI `:17891` + Chrome extension |
| OOBE / Gaia skip | `patches/login_manager/nvidia-generic-local-accounts.patch` (always apply chrome_dev.conf, skip Gaia, load extension) |
| Diagnosis | `tools/collect-auth-debug.sh` |
| USB vs NVMe order | [`docs/LOCAL-ACCOUNTS.md`](LOCAL-ACCOUNTS.md) |

## Dual-boot note

This machine dual-boots Ubuntu on `sda` (hardware TPM) and ChromiumOS from USB. openFyde’s PC boards avoid fighting that TPM by using `tpm2_simulator` + `vtpm_proxy`. Our board already builds that stack (confirmed in the R156 image package list: `tpm2-simulator`, `vtpm`, `tpm_manager`, `cryptohome`). Remaining “cryptohome corrupted” failures are therefore more often **OOBE/Gaia without API keys** or a half-created vault than a missing simulator.

Host-side capture: [`docs/auth-debug-capture.md`](auth-debug-capture.md).

## Implemented in this repo

| Piece | Path |
| --- | --- |
| Research clones | `./tools/fetch-openfyde-research.sh` → `vendor/openfyde-research/` |
| Board USE affirm + `oobe_skip_to_login` | `overlay/.../profiles/base/make.defaults` |
| Auth package | `chromeos-base/nvidia-generic-auth` (via `virtual/chromeos-bsp`) |
| SSH create helper | `/usr/sbin/create-local-account.sh` |
| Diagnosis / gate | `tools/collect-auth-debug.sh`, `tools/verify-local-account.sh` |


for c in /sys/class/drm/card[0-9]; do echo "== $(basename "$c") =="; basename "$(readlink -f "$c/device/driver" 2>/dev/null)" 2>/dev/null || echo no-driver; done; echo simple-framebuffer.0 > /sys/bus/platform/drivers/simple-framebuffer/unbind 2>/dev/null || true; rmmod simpledrm 2>/dev/null || true; echo Y > /sys/module/nvidia_drm/parameters/fbdev 2>/dev/null || true; sed -i 's/fbdev=0/fbdev=1/g' /etc/modprobe.d/zz-nvidia-generic-modeset.conf /etc/modprobe.d/nvidia-modeset.conf 2>/dev/null || true; grep -qF -- '--disable-gpu-sandbox' /etc/chrome_dev.conf || echo '--disable-gpu-sandbox' >> /etc/chrome_dev.conf; restart ui; sleep 3; echo "fbdev=$(cat /sys/module/nvidia_drm/parameters/fbdev 2>/dev/null)"; grep -iE 'Permission denied|Failed to authenticate|Unable to initialize GBM|Couldn.t create Gbm' /var/log/chrome/chrome | tail -40