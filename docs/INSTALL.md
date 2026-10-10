# Runbook: USB first, then internal disk, then Steam

This is the ordered procedure for this machine. Do the phases in order and do not skip
the gates between them — each gate exists to tell you *which* thing broke, which is the
difference between a ten-minute fix and a weekend.

**Steam is Phase 6.** It is not attempted until ChromiumOS is installed to an internal
disk and the driver gates have passed there. This is enforced in code, not just
documented: `steam/container/setup-steam-container.sh` refuses to run while the root
filesystem is on removable media.

| Phase | What | Where it runs | Reversible? |
| --- | --- | --- | --- |
| 1 | Build the image | Ubuntu host | yes |
| 2 | Flash to USB (`sdc`) | Ubuntu host | yes |
| 3 | Boot the USB, verify the driver | Booted USB | yes |
| 4 | Install to `nvme1n1` | Booted USB | **no — erases that disk** |
| 5 | Boot internal, re-verify | Installed system | yes |
| 6 | Steam | Installed system | yes |

Ubuntu lives on `sda` and is never written to at any point in this procedure.

---

## Phase 0 — Before anything

Two things to do from Ubuntu, both quick and both worth it.

### Back up the VBIOS

Read-only dump of the card's ROM, so you have a reference copy. This does not and cannot
write to the card: the kernel's `pci_write_rom()` only toggles a read-enable flag and has
no path to the EEPROM.

```bash
cd ~/CodeEnv/ChromiumOS-NVIDIA-cross
sudo ./safety/vbios-backup.sh
```

### Turn off GNOME automount

You are on GNOME, which auto-mounts removable devices the moment they appear. During a
long USB write, GNOME mounting the half-written partitions can corrupt the image and the
failure shows up later as a confusing boot problem.

```bash
gsettings set org.gnome.desktop.media-handling automount false
gsettings set org.gnome.desktop.media-handling automount-open false
```

Restore with `true` for both once you are done flashing.

---

## Phase 1 — Build the image

On the Ubuntu host. Expect this to be long: the first `repo sync` pulls tens of GB and
`build-packages` is a multi-hour from-scratch toolchain and world build.

```bash
cd ~/CodeEnv/ChromiumOS-NVIDIA-cross

# Read-only: shows what bootstrap will change before it changes anything.
./sdk/bootstrap.sh --check

# Then do it. This is the long one. Run it under tmux or screen.
./sdk/bootstrap.sh
```

Note `bootstrap.sh` is run as yourself, **not** under `sudo`. It calls `sudo` internally
for the host packages and the sysctl. `cros_sdk` refuses to run as root and the checkout
must be owned by you.

It sets `kernel.apparmor_restrict_unprivileged_userns=0` and persists it to
`/etc/sysctl.d/99-chromiumos-sdk.conf`. That is a machine-wide relaxation of an Ubuntu
hardening control, not something scoped to the build: `cros_sdk` needs unprivileged user
namespaces for its container and cannot work without them. `./sdk/bootstrap.sh --container`
prints an LXD 24.04 recipe if you would rather keep the change inside a container.

### Baseline board first

Build stock `amd64-generic` before the NVIDIA board. The biggest unknown at this point is
not our driver work — it is whether stock ChromiumOS boots on this motherboard at all,
which is an ordinary hardware-support question independent of this repo. Answering it on a
throwaway build means every later failure is attributable to the NVIDIA work rather than
ambiguous.

`build.sh` knows `amd64-generic` is a baseline: it skips both the overlay symlink and the
minigbm patch for that board, so the baseline really is stock.

```bash
./sdk/build.sh --board amd64-generic all
```

The stage is positional; `--stage all` also works. Flash this to USB (Phase 2), confirm it
boots (Phase 3), and only then build the real board.

### Stage the vendor blobs first

Two sets of firmware are not in git, because they are vendor blobs under their own licences
and both scripts reproduce them. `build.sh` refuses to start `build-packages` if either is
missing, so this fails fast rather than several hours in:

```bash
./tools/fetch-nvidia.sh            # NVIDIA 595.91.07 bundle, ~500 MB
./tools/fetch-amdgpu-firmware.sh   # amdgpu GC 10.3.6 (Raphael), 11 files, ~2.5 MB
```

The amdgpu set is taken from this host, which already drives the same iGPU, and
decompressed from its `.zst` form; pass `--upstream` to clone `linux-firmware` instead, or
`--verify` to check what is staged without changing anything. Without it amdgpu cannot
initialise the iGPU — which is the recovery console the whole safety argument rests on.

### Then the real board

```bash
./sdk/build.sh --board nvidia-generic all
```

Each board gets its own sysroot, so board packages rebuild rather than being shared. The
`repo sync` and the SDK chroot are shared, so the second build is the cheaper one.

If `amd64-generic` will not boot on this board, the fallback is `reven`, the ChromeOS Flex
board, which is the one actually designed for generic desktop PCs. Our overlay masters
`amd64-generic`, so that is a change rather than a flag — but it is the next thing to try,
not a dead end.

Note `cros_sdk` refuses to run as root and everything here runs as `gooberheads`, not
under `sudo`. The `cros` CLI enters the chroot itself; you never do it manually.

The image type is `test` with `--no-enable-rootfs-verification`, which gives you SSH, a
writable rootfs, and the `chronos` password `test0000`. All three matter for debugging.

---

## Phase 2 — Flash to the USB stick

`sdc` is the target: it is the only device on this machine reporting `removable=1`, at
29.1 GB. Confirm it is still true before flashing, since USB enumeration can shift:

```bash
lsblk -d -o NAME,SIZE,RM,MODEL
```

Then flash. Dry run first — it performs every safety check and writes nothing:

```bash
sudo ./tools/flash.sh --board nvidia-generic --target usb --dry-run
sudo ./tools/flash.sh --board nvidia-generic --target usb
```

This wraps `cros flash usb://`, which will prompt you to pick the device. **Read that
prompt.** It is the one moment in Phase 2 where a wrong answer matters.

### Why not Balena Etcher

Etcher would most likely work — a ChromiumOS image is a complete GPT disk image, not an
ISO needing a bootloader shim. It is still the second-best option here:

- `cros flash usb://` is the only method the upstream developer guide documents. Etcher,
  `dd`, Rufus and UNetbootin are all absent from it. When something fails you want to be
  on the documented path.
- Etcher writes the image byte-for-byte, leaving the GPT sized for the image rather than
  the 29 GB stick, so the stateful partition does not grow into the free space.
  `cros flash` handles that.
- It bypasses the disk allowlist in `tools/flash.sh` entirely. Etcher will happily offer
  you any disk it can see.

If you do use Etcher anyway, the image is at
`chromiumos/src/build/images/nvidia-generic/latest/chromiumos_test_image.bin`.

---

## Phase 3 — Boot the USB and verify the driver

### Firmware setup

On this board (ASUS TUF B850M-PLUS) there is no Chromebook developer-mode dance.
`crossystem dev_boot_usb=1` and the recovery-screen `Ctrl+D` sequence are Chromebook
firmware features and do not apply. You need:

- **Secure Boot off.** Already the case on this machine. The NVIDIA module is unsigned
  and `CONFIG_MODULE_SIG_FORCE` is disabled in our kernel config.
- **iGPU as primary display.** Plug the monitor into the motherboard, not the card. This
  is deliberate and is the core of the Stage 2 safety design, see below.
- **USB selected in the UEFI boot menu** (F8 on this board).

### Why the monitor goes in the motherboard

The image ships `options nvidia-drm modeset=0`. The NVIDIA driver loads completely and
`nvidia-smi` works, but `amdgpu` keeps the console. That split is the whole point: if
something is wrong you get a working screen and a shell to diagnose from, instead of a
black panel with no way in. It separates "the driver is broken" from "the display is
broken", and those have entirely different fixes.

### Verify

Log in as `chronos` / `test0000`, then `shell`. Or `Ctrl+Alt+F2`.

```bash
# Arm the thermal watchdog first.
sudo start gpu-guard
sudo tail -f /var/log/gpu-guard.log   # in another terminal, optional

sudo ./tools/verify-stage2.sh
```

Stage 2 passes when `/dev/nvidia0` exists, `nvidia-smi` reports the 4070 Ti SUPER,
`modeset=0` is in effect, and the console is still on the iGPU.

Then, and only then, switch the display over:

```bash
sudo ./tools/verify-stage3.sh
```

Stage 3 is the real research risk in this project. ChromeOS assumes Mesa EGL and NVIDIA
ships its own, so this is where Chrome-side patching may still be needed. The script
specifically checks for a silent fall back to software rendering, which is the trap here:
the UI comes up looking fine and you conclude it worked.

**Default diagnosis loop:** headless [auto-debug](AUTO-DEBUG.md) (arm flag from Ubuntu →
boot → pull logs). Current Ash-on-RTX status and open bugs (FPS / cursor / tearing):
[STAGE3-DISPLAY.md](STAGE3-DISPLAY.md).

**If Stage 3 fails, stop and fix it before Phase 4.** Installing a broken graphics stack
to the internal disk just means debugging the same problem with a slower edit loop.

### Local account (no Google / no FydeOS cloud)

Dual-boot leaves the hardware TPM with Ubuntu. The image uses the software TPM2 simulator
(`tpm2_simulator` + `vtpm_proxy`) and ships `chromeos-base/nvidia-generic-auth`.

**USB vaults do not transfer to NVMe.** Guest on USB: http://127.0.0.1:17891/ disk
picker (UUID allowlist). After NVMe boot, same URL for `localuser@localhost` password.
Do not use the Local Account extension or Chrome Create local account → Next.

```bash
# On the device after UI is up enough for cryptohomed:
ensure-software-tpm.sh
# GUI: http://127.0.0.1:17891/
create-local-account.sh --user localuser@localhost --password 'choose-a-password'
verify-local-account.sh --user localuser@localhost --password 'choose-a-password'
```

Diagnosis dump: `/usr/share/chromiumos-nvidia-cross/collect-auth-debug.sh` (also
`tools/collect-auth-debug.sh` on the host). See `docs/research-openfyde-auth.md`.

---

## Phase 4 — Install to the internal disk

Only after Stage 2 and Stage 3 pass from USB.

### Read this first

Both internal spare disks are formatted, labelled and auto-mounted under Ubuntu:

| Disk | Size | Partition | Label | Used |
| --- | --- | --- | --- | --- |
| `nvme1n1` | 477 GB | `nvme1n1p1` ext4 | `Data3` | 2.1 MB |
| `sdb` | 931 GB | `sdb1` ext4 | `Data` | 2.1 MB |

Each holds one empty `SteamLibrary` directory and nothing else, so **nothing real is
lost**. But they are not blank disks, and installing repartitions the *entire* disk, not
just that one partition.

The plan is **ChromiumOS on `nvme1n1`**, because NVMe is much faster for boot, package
installs and shader compilation, and **`sdb` kept as the games library**, because the
bigger slower disk is the right home for game files. If you want the 931 GB disk for the
OS instead, swap the targets — just know Phase 6 then has less room.

### Install

Run this **on the booted USB system**, not from Ubuntu:

```bash
# Read-only. Prints the target's real layout and runs every check.
sudo ./tools/install-to-disk.sh --dst /dev/nvme1n1 --dry-run

# Destructive.
sudo ./tools/install-to-disk.sh --dst /dev/nvme1n1
```

It asks you to type `erase nvme1n1` before doing anything.

`--dst` is required and has no default, on purpose. Bare `chromeos-install` picks a
default destination when told nothing, and that default can land on the disk holding
Ubuntu. The wrapper also refuses the Ubuntu disk by **filesystem UUID**, refuses the disk
it is currently running from, and refuses removable media.

The UUID check matters more than it sounds. Device names are not stable across operating
systems: booting ChromiumOS reorders SATA discovery and the USB stick itself takes an
`sdX` slot, so the `sdb` you see from Ubuntu may not be the `sdb` you see here. UUIDs do
not move. **Read the layout the dry run prints and confirm it is the disk you mean** —
trust that over the device name.

Then:

```bash
sudo poweroff
```

Remove the USB stick. Boot, and pick the `nvme1n1` entry in the UEFI boot menu.

---

## Phase 5 — Verify the installed system

Re-run both gates. This is not busywork: the installed system has its own kernel, its own
module set and a fresh stateful partition, so passing from USB does not carry over.

```bash
sudo start gpu-guard
sudo ./tools/verify-stage2.sh
sudo ./tools/verify-stage3.sh
```

Both must pass here. If the USB passed and the install does not, the difference is in the
install rather than the driver work, which is a much narrower thing to debug.

---

## Phase 6 — Steam

**Only now.** `setup-steam-container.sh` checks the root device's removable flag and hard-
refuses if you are still on the USB stick, so if you have skipped ahead it will tell you.

Why the ordering is enforced rather than merely suggested: a USB stateful partition cannot
fit a modern game, Proton rewrites its shader cache constantly which is slow and hard on
flash, everything in the container sits on the stateful partition and is destroyed by the
install anyway, and USB latency starving the GPU produces symptoms that look like driver
bugs. Setting up Steam from USB is wasted work that also generates false leads.

```bash
sudo ./steam/container/setup-steam-container.sh create
sudo ./steam/container/setup-steam-container.sh verify   # vkcube + NVIDIA Vulkan ICD

# Watchdog must be running; the script refuses to launch a game without it.
sudo start gpu-guard
sudo ./steam/container/setup-steam-container.sh steam
```

`verify` is the gate that matters. It confirms `vulkaninfo` reports the NVIDIA ICD rather
than lavapipe. If it reports lavapipe you are on the CPU, and no amount of Proton
configuration will fix that.

Point Steam at the `sdb` library for game installs so games land on the 931 GB disk
instead of filling the OS disk.

---

## Recovery

| Symptom | Recovery |
| --- | --- |
| Black screen on USB boot | Power off. The monitor should be on the motherboard, not the card. Nothing is written to any internal disk during Phase 3. |
| Driver loads, UI is black | Stage 3 problem, not Stage 2. Boot with `nvidia-drm.modeset=0` to get the iGPU console back and diagnose from there. |
| USB will not boot at all | Reflash. Check GNOME automount was actually off during the write. |
| `preflight.sh nvme1n1` fails with "has mounted partitions" from Ubuntu | Expected, and correct. GNOME auto-mounts `Data3`. You do not need preflight for the internal disk: the install runs on the device, where `install-to-disk.sh` unmounts the target itself. Host-side preflight is for the USB (`preflight.sh sdc`). |
| Installed system will not boot | Boot the USB again and reinstall. Ubuntu on `sda` is untouched and remains bootable from the UEFI menu throughout. |
| GPU temperature climbing | `gpu-guard` acts on its own: warn at 78C, halve the clock ceiling at 83C, kill GPU clients at 87C, power off at 90C. Critical sits below the card's own 92C slowdown on purpose. |
| Ubuntu itself | Never modified. Always available from the UEFI boot menu. It is the recovery environment for everything above. |

## Hard rules

These hold at every phase, and are enforced in `safety/lib-common.sh` and
`safety/limits.conf` rather than left to memory:

- **Never flash the VBIOS.** `vbios-backup.sh` reads only. No vendor flashing tool is
  installed, and `assert_no_flash_tools()` fails the preflight if one appears.
- **Never raise power or clock limits above stock.** `assert_caps_sane()` refuses any cap
  above the card's stock values. The configured caps are 200 W against a 285 W stock, and
  2100 MHz against a 3120 MHz stock — deliberately conservative, and only relaxed in
  Stage 5 after logged evidence supports it.
- **Never force the fans off under load.** On Ada the GSP firmware owns the fan curve;
  leave it alone. Note that 0% fan at idle is normal for this card, which is why the
  stall detector only trips at 0% fan above 70C for 10 consecutive seconds.
- **`sda` is never a target.** Five independent refusals in `tools/flash.sh`, plus a
  UUID-based refusal in `tools/install-to-disk.sh` that survives device renaming.
