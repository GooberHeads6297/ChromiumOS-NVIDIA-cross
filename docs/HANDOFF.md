# Handoff: dGPU-first kernel output

Written to hand this project to a fresh agent team with as little re-derivation as possible.
Everything below was **verified against the synced tree or the running host**, not inferred.
Where something is unverified it says so.

Read this file, then `SAFETY.md`. Do not re-research the sections marked SETTLED.

---

## 1. The new direction

**Goal: get kernel-level display output on the dedicated RTX 4070 Ti SUPER, before doing
anything further with the integrated GPU.**

Previously the plan was iGPU-first: bring up amdgpu on the Raphael iGPU as a guaranteed
recovery console, then attach the NVIDIA driver alongside it. That work is **done and
committed** (see §4) and stays in the tree as a fallback. It is no longer the starting point.

The reason the new order is reasonable: driving output on the dGPU is a *smaller* change than
it sounds. It does not need NVIDIA's proprietary EGL, minigbm changes, or Chrome patches. It
needs a kernel that can modeset on the card and put a console on it. That is a narrow,
testable goal with a clear pass/fail, which makes it a good first milestone.

### What this reorder costs, stated plainly

The iGPU was the safety net, and going dGPU-first means the first boot has no second display
path. Be precise about what that risks:

- **It cannot damage the card.** Nothing in this project writes VBIOS, raises power or clock
  limits, or forces fans off; those are prohibited by `SAFETY.md` and are not reachable from
  anything here. GSP firmware is pushed into volatile GPU RAM at probe and is gone on reset.
  `pci_write_rom()` treats the sysfs `rom` node as a read-enable toggle and cannot reach the
  EEPROM. A driver fault costs a reboot.
- **It can cost you the display.** A failed modeset on the only active output means a blind
  machine. That is the real risk, and it is an inconvenience, not damage.

**Therefore: keep the BIOS primary display on the iGPU with a monitor physically attached to
the motherboard, and test the dGPU as a secondary output first.** That preserves the recovery
path at zero cost while still making the dGPU the thing under test. Do not set the dGPU as
primary until it has modeset successfully at least once.

Also keep the serial/`MAGIC_SYSRQ` escape hatches already enabled in the board kernel config
(§4.2); they exist precisely for a blind boot.

---

## 2. Hardware (SETTLED — verified on the host, do not re-derive)

| Item | Value |
| --- | --- |
| dGPU | NVIDIA GeForce RTX 4070 Ti SUPER (AD103), `0000:01:00.0`, PCI ID `10de:2705` |
| dGPU VBIOS | 95.03.45.80.6B |
| iGPU | AMD Raphael `[1002:164e]` rev c2, `0000:0d:00.0`, driven by `amdgpu` |
| CPU | AMD Ryzen 9 7900X (Zen 4) |
| Host OS | Ubuntu, kernel 7.0.0-34-generic, 24 cores, 29 GB RAM |
| Host NVIDIA driver | 595.91.07, `card1: driver=nvidia` |

Raphael IP versions, which matter for firmware: GC **10.3.6**, SDMA **5.2.6**, PSP **13.0.5**,
VCN **3.1.2**, DCN **3.1.6**.

### Disks — read `safety/limits.conf`, it is authoritative

| Device | Contents | Role |
| --- | --- | --- |
| `sda` | Ubuntu (root UUID `b77baffd-…`, ESP `E9F8-543C`) | **NEVER a target.** Refused by name and by UUID. |
| `sdb1` | ext4 label `Data`, 931.5 G | Steam library |
| `sdc` | removable, 29.1 GB DataTraveler | USB test target |
| `nvme1n1p1` | ext4 label `Data3`, 476.9 G | Install target |

All four UUIDs in `limits.conf` were verified against the real disks.

---

## 3. Build system facts (SETTLED — these cost real time to find)

- `cros setup-board` **does not exist**. `cros build-packages` runs `setup_board` itself
  (`--no-skip-setup-board` is the default; `cros_build_packages.py:440` calls
  `sysroot.SetupBoard`). The standalone `chromite/bin/setup_board` requires the chroot.
- All `cros` commands run **outside** the chroot; the CLI enters it itself. `cros_sdk`
  refuses to run as root, and it sudoes for itself — so it needs an interactive terminal or a
  primed `sudo -v`. An agent sandbox cannot run it.
- `CHROOT_SOURCE_ROOT = /mnt/host/source` (`chromite/lib/constants.py:31`).
- `cros flash usb:///dev/sdX board/latest` — explicit device paths **are** supported and
  documented.
- Kernel config mechanism: `cros-kernel.eclass` passes `CHROMEOS_KERNEL_SPLITCONFIG` to
  `chromeos/scripts/prepareconfig`, which does
  `cat chromeos/config/chromeos/base.config chromeos/config/chromeos/x86_64/common.config <name>.flavour.config > .config`.
  **Flavour is last, so it wins on duplicate symbols.**
- **Portage precedence trap, hit twice.** Portage resolves by *highest version across the
  whole masters chain* and uses overlay priority only as a tiebreak. Being in a
  higher-priority overlay is **not** enough. Our `virtual/opengles` had to become `-r3` to beat
  amd64-generic's `-r2`, and `virtual/vulkan-icd` `-r2` to beat its `-r1`. Before trusting any
  build, re-check:
  ```bash
  ls ~/chromiumos/src/overlays/overlay-amd64-generic/virtual/opengles/
  ls ~/chromiumos/src/overlays/overlay-amd64-generic/virtual/vulkan-icd/
  ```
- **Nothing outside the chromiumos checkout exists inside the chroot.** `cros_sdk` mounts only
  the checkout (as `/mnt/host/source`), plus `out` and `depot_tools`. This repo lives at
  `~/CodeEnv/ChromiumOS-NVIDIA-cross`, outside all of them.

  This bit twice. `stage_link` used to **symlink** the overlay into `src/overlays/`, which
  resolves on the host and **dangles in the chroot**; and all three NVIDIA ebuilds default
  `NVIDIA_VENDOR_DIR` to `/mnt/host/source/src/platform/chromiumos-nvidia-cross/vendor`, a
  path that did not exist at all.

  The overlay failure was deceptive: `portage_util._GetKnownOverlays()` globs `src/overlays/*`
  and calls `GetOverlayName()` on each hit; for a dangling link that read fails, the overlay
  is **skipped silently**, and the board simply ceases to exist. The symptom is
  `ValueError: No such board: nvidia-generic` from `build_query.Board.get`, which reads like a
  missing profile rather than a broken mount. The vendor failure would have surfaced hours
  into `build-packages`, well after the cheap gate passed.

  `sync_project_into_checkout()` in `sdk/build.sh` now places **real content** at both paths
  and uses no symlinks: `rsync -a --delete` for the overlay, and `cp -al` for the 2.2 GB
  vendor bundle (a hardlink farm — instant, no extra disk, same filesystem here, with a copy
  fallback). `stage_packages` re-syncs too, so editing the repo and running that stage alone
  cannot build stale contents. **If you add a new in-chroot path, check it against this.**
- **`virtual/chromeos-bsp` must be overridden or the board's packages are silently absent.**
  `virtual/target-chromium-os` depends on the virtual, never on a board package directly.
  amd64-generic does not override it. An orphaned package is not a portage error, so this
  fails without any message.

### Corrections to earlier project assumptions — all four were wrong

The project was partly designed around out-of-tree module blockers that **do not exist**.
Grepping all of `chromeos/config/` in the 6.12 tree, and confirmed again by searching the
assembled 887-line config for our board:

| Symbol | Occurrences | Reality |
| --- | --- | --- |
| `CONFIG_CFI_CLANG` | 0 | Never enabled. Not a blocker. |
| `CONFIG_LTO_CLANG*` | 0 | Never enabled. Not a blocker. |
| `CONFIG_TRIM_UNUSED_KSYMS` | 0 | Never enabled. Not a blocker. |
| `CONFIG_MODULE_SIG_FORCE` | 1 | Only in **reven**'s flavour config, not inherited here. |

So nothing needs relaxing and no exploit mitigation is being traded away. The kernel is still
built with clang, so the NVIDIA interface layer must use the same toolchain — ordinary
cross-compilation, not a blocker.

Also settled: ChromeOS's v5.15 is **24,741 commits ahead of upstream** and contains 36
references to `IP_VERSION(10, 3, 6)`, so an earlier worry that 5.15 could not support Raphael
was unfounded. We use 6.12 anyway.

---

## 4. Current state of the tree

Board is `nvidia-generic`, an overlay whose master chain includes `amd64-generic`.
`profiles/base/parent` is `amd64-generic:kernel-6_12`, which pins kernel 6.12 via the
supported chain (`../base` + `deselect-all-kernels`, then `USE=kernel-6_12`).

**Critical context: `amd64-generic` is a virtual-machine target.** Almost every problem below
came from that. It ships no amdgpu, defaults to kernel 5.15, and pins GL to software
rendering.

### 4.1 What is done and verified

| Piece | Location | Verified how |
| --- | --- | --- |
| Board kernel flavour config | `overlay/…/kernel-config/chromiumos-x86_64-nvidia.flavour.config` | Reproduced `prepareconfig`'s concatenation on the real tree; every target symbol resolves as intended in the 887-line result |
| Flavour config actually installed | `sdk/build.sh` link stage | Ran the link stage; file lands in `kernel/v6.12/chromeos/config/chromeos/x86_64/` |
| Raphael firmware package | `overlay/…/sys-firmware/amdgpu-raphael-firmware/` | 11 files staged from host, 2.5 MB |
| Firmware fetch script | `tools/fetch-amdgpu-firmware.sh` | Ran it; `--verify` reports all 11 |
| GL driver overrides | `overlay/…/virtual/{opengles,vulkan-icd}/` | Versions checked against the whole masters chain |
| BSP wiring | `overlay/…/virtual/chromeos-bsp/chromeos-bsp-2.ebuild` | Pattern matched to `overlay-reven` / `overlay-grunt` |
| minigbm patch | `patches/minigbm/0001-add-nvidia-drm-dumb-backend.patch` | `git apply --check` clean |

### 4.2 Kernel config settings already in place, and why

These differ from what amd64-generic produces. Several are directly relevant to dGPU output.

| Symbol | Value | Why it matters for the new goal |
| --- | --- | --- |
| `CONFIG_DRM_NOUVEAU` | `m` | amd64-generic has `=y`. **Built-in cannot be blacklisted**, so it would bind to the RTX before NVIDIA's driver. As a module it can be blacklisted — or used deliberately, see §5. |
| `CONFIG_DRM_FBDEV_EMULATION` | `y` | Unset on amd64-generic. Without it a DRM driver exposes no `/dev/fb0`, so there is **no text console on the dGPU** and no way to read an error. Also what `nvidia-drm fbdev=1` attaches to. |
| `CONFIG_FRAMEBUFFER_CONSOLE` | `y` | Same reason. |
| `CONFIG_DRM_SIMPLEDRM`, `CONFIG_SYSFB_SIMPLEFB` | `y` | Console on the framebuffer UEFI already set up. Needs no driver and no firmware, so it survives any GPU driver failing outright. |
| `CONFIG_MAGIC_SYSRQ`, `CONFIG_SERIAL_8250_CONSOLE` | `y` | Escape hatches for a blind boot. Keep these. |
| `CONFIG_DRM_AMDGPU` | `m` | iGPU / fallback console. |
| `CONFIG_MODULES`, `CONFIG_MODULE_UNLOAD` | `y` | Load and, importantly, *unload* the NVIDIA module without rebooting. |
| `CONFIG_MMU_NOTIFIER`, `CONFIG_ZONE_DEVICE`, `CONFIG_HMM_MIRROR`, `CONFIG_DEVICE_PRIVATE` | `y` | Used by the NVIDIA modules. |
| `CONFIG_PCI_REALLOC_ENABLE_AUTO`, `CONFIG_PCIEAER` | `y` | BAR reallocation and PCIe error reporting. |
| `CONFIG_EFIVAR_FS` | `y` | UEFI boot entries, needed when installing to an internal disk. |

`CONFIG_DRM_SIMPLEDRM` gives a **text console only**. minigbm has `backend_amdgpu`,
`backend_nouveau` and others but **no simpledrm backend**, so Chrome cannot allocate buffers
on it and there is no graphical session on that path.

### 4.3 Overlay settings

```
VIDEO_CARDS="-* amdgpu radeonsi nouveau llvmpipe"
CHROMEOS_KERNEL_SPLITCONFIG="chromiumos-x86_64-nvidia"
USE="${USE} nvidia_open libglvnd amd_cpu native_gpu_memory_buffers gpu_sandbox_start_early"
LINUX_FIRMWARE="${LINUX_FIRMWARE} amd_ucode"
```

Three traps encoded here, do not "clean them up":

1. **`llvmpipe` is load-bearing.** In `media-libs/mesa` it maps to
   `gallium_enable video_cards_llvmpipe swrast` — it is the software rasteriser, the only GL
   needing no working kernel driver.
2. **There is no `linux_firmware_amdgpu` USE flag.** `sys-kernel/linux-firmware`'s
   `IUSE_LINUX_FIRMWARE` offers only `amd_ucode`, `amdgpu_gc_11_0_1`, `amdgpu_gc_11_0_4`,
   `amdgpu_yellow_carp`; `video_cards_amdgpu` only selects a `LICENSE` entry. Adding `amdgpu`
   would be silently ignored while reading as though it worked.
3. **`VIDEO_CARDS` does not choose the GL driver on ChromeOS.** See below.

### 4.4 ChromeOS uses split mesa packages (SETTLED, and non-obvious)

ChromeOS does **not** build one `media-libs/mesa` with gallium drivers selected by
`VIDEO_CARDS`. It ships `mesa-amd`, `mesa-iris`, `mesa-radv`, `mesa-llvmpipe`,
`mesa-freedreno`, `mesa-panfrost`, `mesa-reven`, each hardcoding its driver — `mesa-amd`
passes `-Dgallium-drivers=radeonsi` unconditionally and reads no `VIDEO_CARDS`.

The choice is made by **`virtual/opengles`** and **`virtual/vulkan-icd`**. amd64-generic pins
both to `mesa-llvmpipe`: its GL is **software**. We override to `mesa-amd` / `mesa-radv`.

**This is directly relevant to the new goal.** There is no `mesa-nvidia`. For the dGPU, GL/EGL
comes from NVIDIA's own userspace via glvnd's vendor-neutral dispatch
(`__EGL_VENDOR_LIBRARY_DIRS`), which is why `USE=libglvnd` is set. NVIDIA's Vulkan ICD ships
its own JSON and does not need a virtual. **None of that is needed for §5** — kernel modeset
and a text console involve no GL at all.

### 4.5 The iGPU firmware problem (SETTLED, fixed)

Raphael has no legacy firmware alias for *any* of its IP blocks:
`amdgpu_ucode_legacy_naming()` has no case for GC `10.3.6`, SDMA `5.2.6`, or VCN `3.1.2`, so
all fall through to IP-derived names. ChromeOS's `linux-firmware` carries none of them, has no
USE flag that installs general amdgpu firmware, and `cros-kernel.eclass` defines
`builtin_fw_amdgpu_gc_10_3_7` but no `10_3_6`.

`sys-firmware/amdgpu-raphael-firmware` ships all eleven. Every one is on a fatal path — the
request sites propagate errors up through `early_init`/`sw_init`, so one missing file means no
iGPU:

| IP block | Files | Requested by |
| --- | --- | --- |
| GC 10.3.6 | `gc_10_3_6_{pfp,me,ce,rlc,mec,mec2}.bin` | `gfx_v10_0_init_microcode()` |
| SDMA 5.2.6 | `sdma_5_2_6.bin` | `amdgpu_sdma_init_microcode()` |
| PSP 13.0.5 | `psp_13_0_5_{toc,ta}.bin` | `psp_v13_0_init_microcode()`, both `if (err) return err` |
| VCN 3.1.2 | `vcn_3_1_2.bin` | `amdgpu_vcn_early_init()` |
| DCN 3.1.6 | `dcn_3_1_6_dmcub.bin` | display core |

Two easy mistakes, both avoided — do not "fix" them back: ChromeOS's own Mendocino list uses
`yellow_carp_vcn.bin`, but that alias covers VCN **3.1.1** only, so ours is `vcn_3_1_2.bin`.
Their list also has a `psp_*_asd.bin`, which we do not need because
`psp_init_asd_microcode()` is never called for MP0 13.0.5. There is no `smu_13_0_5.bin`
anywhere; on this APU the SMU firmware comes from the platform BIOS.

If the iGPU console is ever dead, check `dmesg` for failed `amdgpu/gc_10_3_6_*` requests
before suspecting the kernel config.

---

## 5. The next milestone: kernel output on the dGPU

Nothing here has been attempted yet. This is the work.

### 5.1 Definition of done

A single, unambiguous pass condition: **a text console readable on a monitor plugged into the
RTX 4070 Ti SUPER, on the `nvidia-generic` image.** No Chrome, no GL, no Steam. If a login
prompt or kernel messages are legible on that monitor, the milestone is met.

Deliberately excluded: accelerated scanout, Chrome's GPU process, Ozone, Vulkan. Those are the
hard research problems (§7) and mixing them in destroys the pass/fail signal.

### 5.2 Two candidate paths — decide by testing, not by argument

Both should be tried, cheapest first. They are independent, which is the point.

**Path A — nouveau.** `CONFIG_DRM_NOUVEAU=m` is already in the config and minigbm already
ships `backend_nouveau`, so this needs **no new code**. It proves PCI enumeration, DRM/KMS,
modesetting and fbdev on the card as a control experiment. Ada support in nouveau is limited
and needs GSP firmware, so display-only is the realistic expectation — which is exactly the
milestone. Try this first because a failure here means the problem is not NVIDIA-specific.

**Path B — NVIDIA open modules with `nvidia-drm modeset=1 fbdev=1`.** The real target. The
ebuild and `build-nvidia-modules.sh` already exist in the overlay. Requires
`gsp_ga10x.bin` at `/lib/firmware/nvidia/595.91.07/` (already packaged as
`sys-firmware/nvidia-gsp-firmware`). `fbdev=1` is what creates the console, and it depends on
`CONFIG_DRM_FBDEV_EMULATION=y`, already set.

Only one of nouveau and `nvidia` may bind. Blacklist whichever is not under test —
`nvidia-modeset-off.conf` and `nvidia.conf` in the overlay exist for this.

### 5.3 Use the existing gate script as a free intermediate checkpoint

`tools/verify-stage2.sh` already exists and runs **on the device**. It was written for the
iGPU-first ordering: it asks whether the NVIDIA module, the GSP firmware and the userspace
libraries all load and agree **while modesetting is off and the display still belongs to the
iGPU**, and it warns if `nvidia_drm` is driving a display.

Do not discard it or rewrite it for the new ordering. Run it **before** Path B, exactly as
written. "Driver loads completely, display untouched" is a strictly weaker and safer condition
than "driver drives the display", it isolates driver problems from modeset problems, and it
costs one reboot. Only after it passes should `modeset=1 fbdev=1` be turned on.

It checks a trap worth knowing: module loaded but `/dev/nvidia*` nodes missing, which on
ChromeOS usually means nothing ran `nvidia-modprobe`. Get it onto the device with:

```bash
scp tools/verify-stage2.sh root@<device>:/tmp/     # test image password: test0000
ssh root@<device> /tmp/verify-stage2.sh
```

`tools/verify-stage3.sh` also exists, for the Chrome/EGL work in §7. Not needed yet.

### 5.4 Ordered steps

1. **Prove the overlay resolves.** Cheap gate, minutes not hours, and it must pass before any
   long build. Needs an interactive terminal because `cros_sdk` sudoes:
   ```bash
   cd ~/CodeEnv/ChromiumOS-NVIDIA-cross
   ./tools/fetch-amdgpu-firmware.sh --verify     # expect all 11 staged
   ./tools/fetch-nvidia.sh                       # if vendor/ is absent
   BOARD=nvidia-generic ./sdk/build.sh --stage setup
   ```
   **This has never been run since the overlay changes.** Expect the first failures here, most
   likely in the new virtuals or the firmware ebuild. Fix them before building.
2. **Build.** `./sdk/build.sh --board nvidia-generic all` — multi-hour.
3. **Flash to USB and boot-test before touching any internal disk.** `tools/flash.sh` refuses
   fixed disks and auto-detects the single removable device.
4. **Check the kernel actually got our config.** On the booted image, confirm
   `CONFIG_DRM_FBDEV_EMULATION`, `DRM_NOUVEAU=m`, `DRM_AMDGPU=m`. If they are wrong, the
   flavour config did not install — re-read §3.
5. **Run `verify-stage2.sh`** (§5.3) with modesetting off.
6. **Path A, then Path B**, as in §5.2. Monitor on the motherboard throughout; the dGPU
   monitor is the thing being tested, not the thing being relied on.

### 5.5 What to check when there is no output

In this order, because it goes cheapest-first and each step narrows the cause:

- `lspci -k -s 01:00.0` — is *any* driver bound?
- `dmesg | grep -iE 'nvidia|nouveau|drm|gsp'` — firmware load failures and probe errors.
- `ls /sys/class/drm/` — did a `card*` appear for the dGPU, and does it have connectors?
- `ls /dev/fb*` — fbdev emulation present? If not, the kernel config is wrong, not the driver.
- Module loaded but no console: suspect `fbdev=1` not passed, or simpledrm holding the
  framebuffer. Check for a `simple-framebuffer` device that never handed over.
- Monitor connected but blank: check connector status under
  `/sys/class/drm/card*/card*-*/status`, and try a different port — DP and HDMI do not always
  behave the same on first bring-up.

---

## 6. Safety rules — non-negotiable, do not relax

From `SAFETY.md` and `safety/limits.conf`. The user has one RTX 4070 Ti SUPER.

- **Never** flash or write VBIOS. Never raise power or clock limits above stock. Never force
  fans off under load.
- `sda` is Ubuntu and is **never** a flash or install target. Refused by name and by UUID.
- **Steam only after the OS is installed to an internal disk.** This is enforced in code:
  `steam/container/setup-steam-container.sh` calls `assert_installed_not_usb()` from both
  `do_create` and `do_steam` and hard-refuses on removable root. Do not weaken it.
- USB boot-test before any internal install. `tools/install-to-disk.sh` requires `--dst`, has
  no default, and refuses the Ubuntu disk by UUID, the running root disk, removable media, and
  anything that is not a whole disk.
- Run `safety/preflight.sh <target>` before destructive steps. `preflight.sh sdc` passes;
  `preflight.sh sda` fails with four refusals.
- `safety/vbios-backup.sh` is **diagnostic only**. Nothing in this project writes firmware,
  UEFI only *reads* the option ROM, and GSP firmware is volatile. It is not a safety
  prerequisite; earlier notes overstated it.

---

## 7. Still genuinely unsolved (do not start here)

**Stage 3: Chrome's Ozone/EGL on NVIDIA.** ChromeOS's graphics path assumes Mesa's EGL and
minigbm's allocator; NVIDIA ships its own EGL plus `libnvidia-egl-gbm` and
`libnvidia-allocator`. Bridging them may need patching Chrome's GPU initialisation rather than
just setting `__EGL_VENDOR_LIBRARY_DIRS`. The minigbm dumb-buffer patch should be enough for
pixels on screen because dumb buffers are linear and driver-agnostic; *accelerated* scanout is
the hard half.

This is the real research risk in the project, and §5 is deliberately scoped to avoid it.

---

## 8. Files worth reading, in order

| Path | Why |
| --- | --- |
| `SAFETY.md`, `safety/limits.conf` | Hard rules and verified disk UUIDs |
| `docs/INSTALL.md` | Six-phase runbook: build → USB → boot-test → install → verify → Steam |
| `docs/architecture.md` | Stage gates and the known-hard-problems list, now corrected |
| `docs/hardware.md` | Verified hardware, and the three changes the iGPU console needed |
| `sdk/build.sh` | Stages; `link` installs the flavour config, `packages` gates on firmware |
| `patches/kernel/README.md` | How board kernel config actually works, and the four false blockers |
| `overlay/overlay-nvidia-generic/profiles/base/make.defaults` | Board settings, each with rationale |

## 9. Outstanding user-side actions

- Run the §5.3 step 1 gate in a real terminal and report the output.
- Nothing has been flashed or installed yet. No disk has been written.
- The already-built `amd64-generic` baseline image was deliberately **not** flashed.
