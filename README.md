# ChromiumOS-NVIDIA-cross

Building a ChromiumOS derivative that loads NVIDIA's open kernel modules from its own
kernel stack, drives the ChromeOS UI on an RTX 4070 Ti SUPER, and runs Steam/Proton
with native Vulkan. Developed and tested on bare metal.

Read [SAFETY.md](SAFETY.md) first. There is one GPU and no spare, and the short version
is that driver faults cannot damage it — but the reasoning matters, and the guardrails
are enforced in code rather than left to memory.

## Status

| Stage | What it proves | State |
| --- | --- | --- |
| 0 | Safety harness; watchdog ladder verified | Implemented, self-test passing |
| 1 | Stock ChromiumOS boots bare metal | Tooling ready, needs a build |
| 2 | Driver loads fully, display still on iGPU | Overlay + gate script ready |
| 3 | ChromeOS UI composited by the RTX | Patch + config ready |
| 4 | Steam/Proton on native Vulkan | Container ready |
| 5 | Sustained thermal validation | Logger + analysis ready, verified on synthetic data |

Everything is written and locally validated as far as it can be without a ChromiumOS
checkout. Stages 1 onward need a long build and physical access, so they are yours to
run; each has a gate script that tells you plainly whether it passed.

## The hardware this targets

Verified on the machine, not inferred (details in [docs/hardware.md](docs/hardware.md)):

- **RTX 4070 Ti SUPER**, AD103, PCI `10de:2705`, VBIOS `95.03.45.80.6B`, 16 GB.
  Not the plain 4070 Ti (AD104) — that distinction matters for every support lookup.
- NVIDIA lists `0x2705` with the **`kernelopen`** feature flag, so the open kernel
  modules are explicitly supported on this silicon.
- The host already runs **open kernel module 595.91.07**, which is why that version is
  pinned: known-good here, and it doubles as the recovery path.
- Ryzen 9 7900X with an **active Raphael iGPU on `amdgpu`** — the reason bare metal is
  low-risk, since the console survives any NVIDIA failure.
- Ubuntu 26.04 build host; `sdb` and `nvme1n1` free as install targets; `sda` carries
  Ubuntu and is hard-blocked everywhere.

## Quick start

```bash
# 0. Safety first. Verify the watchdog ladder without touching the GPU.
./safety/gpu-guard.sh --self-test

# Optional insurance; nothing here ever writes firmware back.
sudo ./safety/vbios-backup.sh

# 1. Check the build host, then prepare it and sync the source (long).
./sdk/bootstrap.sh --check
./sdk/bootstrap.sh

# 2. Stage the pinned NVIDIA bundle (verifies NVIDIA's published sha256).
./tools/fetch-nvidia.sh

# 3. Baseline build with no NVIDIA at all -- prove the boot path first.
./sdk/build.sh --board amd64-generic all

# 4. Build the NVIDIA board.
./sdk/build.sh --board nvidia-generic all

# 5. Flash to the USB stick. Refuses sda five different ways.
sudo ./safety/preflight.sh sdc
sudo ./tools/flash.sh --board nvidia-generic --target usb

# 6. Boot the USB with the monitor on the motherboard, then on the device:
#      sudo start gpu-guard
#      sudo ./tools/verify-stage2.sh     # driver loads, iGPU keeps the console
#      sudo ./tools/verify-stage3.sh     # UI renders on the RTX

# 7. Only once both gates pass, install to the internal disk (from the booted USB):
#      sudo ./tools/install-to-disk.sh --dst /dev/nvme1n1 --dry-run
#      sudo ./tools/install-to-disk.sh --dst /dev/nvme1n1

# 8. Reboot from nvme1n1, re-run both gates there, and only then set up Steam.
```

**USB before internal disk, and Steam last.** The ordering is not a style preference:
Stage 3 is the part most likely to fail, and failing it from a USB stick costs a reflash
instead of a reinstall. Steam is gated in code — `setup-steam-container.sh` refuses to run
while the root filesystem is on removable media, because a USB stateful partition cannot
hold a modern game and anything set up there is destroyed by the install anyway.

Full procedure with firmware settings and recovery paths: **[docs/INSTALL.md](docs/INSTALL.md)**.

## Layout

| Path | Purpose |
| --- | --- |
| [SAFETY.md](SAFETY.md) | What can and cannot hurt the card; test protocol |
| `safety/limits.conf` | Every threshold, in one place, derived from measured values |
| `safety/gpu-guard.sh` | 1 Hz watchdog with `--self-test` |
| `safety/preflight.sh` | Bare-metal gate: iGPU primary, disk allowlist, no flash tools |
| `safety/vbios-backup.sh` | Read-only VBIOS dump |
| `safety/thermal-log.sh` | Stage 5 logging plus verdict analysis |
| `sdk/bootstrap.sh` | Host prep; `--check` reports without changing anything |
| `sdk/build.sh` | Overlay linking, board setup, packages, image |
| `overlay/overlay-nvidia-generic/` | Board overlay: modules, userspace, firmware, BSP |
| `patches/minigbm/` | The `nvidia-drm` dumb-buffer backend |
| `patches/kernel/` | Config fragment that lets an out-of-tree module load |
| `steam/container/` | Steam + Proton with direct `/dev/nvidia*` access |
| `tools/verify-stage{2,3}.sh` | Gate checks, run on the device |
| `tools/flash.sh` | Image writer with a disk allowlist and label guard |
| `tools/install-to-disk.sh` | USB-to-internal install; refuses Ubuntu by filesystem UUID |
| [docs/HANDOFF.md](docs/HANDOFF.md) | **Start here. Current state, settled facts, and the next milestone** |
| [docs/INSTALL.md](docs/INSTALL.md) | **The runbook: USB, then internal disk, then Steam** |
| [docs/architecture.md](docs/architecture.md) | Target stack, stage gates, known hard problems |
| [docs/hardware.md](docs/hardware.md) | Measured hardware facts |
| [docs/research.md](docs/research.md) | Origin research and where it was wrong |

## Two findings that shaped the design

**minigbm already has a nouveau backend.** ChromeOS allocates buffers through minigbm,
which matches backends by DRM driver name. `dumb_driver.c` contains
`INIT_DUMB_DRIVER(nouveau)` — a generic dumb-buffer backend. There is no `nvidia-drm`
entry, but adding one follows the identical macro pattern, because `nvidia-drm`
implements the dumb-buffer ioctls when loaded with `modeset=1`. That turned the display
problem from a rewrite into [a small patch](patches/minigbm/0001-add-nvidia-drm-dumb-backend.patch)
which applies cleanly to upstream `main`.

**Steam cannot come from Borealis.** Borealis is Google-internal and was discontinued on
1 January 2026; it was never in the open tree. So Steam is delivered here by a Debian
container with direct device access, deliberately bypassing Crostini's virtio-gpu path
to keep Proton talking straight to the driver.

## The honest risk

Stages 0-2 are high-confidence. **Stage 3 is the real research risk**: ChromeOS's
graphics path assumes Mesa's EGL, NVIDIA ships its own, and bridging them may need
Chrome-side patching rather than configuration. Stage 4's performance depends on Stage
3's allocator work.

None of that is hardware risk. The worst realistic outcome is a project that stalls at a
black screen with a working iGPU console, not a dead card.
