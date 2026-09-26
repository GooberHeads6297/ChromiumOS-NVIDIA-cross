# Research notes

Where this project came from, what the starting research got right, and what had to
be corrected once the hardware was actually inspected.

## Origin

The starting point was a conversation exploring whether a Ryzen 9 7900X desktop with
an NVIDIA card could run FydeOS, Brunch ChromeOS, or ChromeOS Flex, and whether
Steam and GPU acceleration would work. Its conclusions, condensed:

- FydeOS states NVIDIA GPUs are not officially supported; expect corruption, glitches
  or a black screen. It recommends disabling the discrete GPU and using an integrated
  Intel/AMD GPU.
- FydeOS removed Borealis Steam in v22, because Google discontinued Borealis on
  1 January 2026. Older "search for Steam, open Borealis" tutorials are obsolete.
- Brunch explicitly lists AMD Ryzen CPUs as supported and **dGPUs as unsupported**;
  `gumboz` is its Ryzen recovery image. A system stuck at the ChromeOS logo can be
  caused by an incompatible dedicated GPU.
- ChromeOS Flex picks one GPU when several are present and does not support dynamic
  GPU switching. Google lists NVIDIA GPUs as unstable under heavy GPU load.
- None of the prebuilt options turn the NVIDIA card into a usable gaming GPU.
- Its final recommendation: build a **ChromiumOS derivative** rather than patching
  FydeOS or Brunch after the fact, since ChromiumOS builds its own kernel and
  supports custom boards, and use **Nouveau + Mesa/NVK** as the realistic route
  because ChromiumOS already carries `libdrm_nouveau` and `CONFIG_DRM_NOUVEAU`.

The structural conclusion is sound and this project follows it: start from
ChromiumOS source, not from someone else's prebuilt image. Two of its specifics do
not survive contact with the actual machine.

## Correction 1: the card is AD103, not AD104

The conversation reasoned about a plain RTX 4070 Ti (`AD104`, PCI `10de:2782`). The
installed card is an **RTX 4070 Ti SUPER**, which is **AD103**, PCI **`10de:2705`**.

This matters because every vendor support matrix is keyed on device ID. Looking up the
wrong ID produces the wrong answer about whether a driver supports the card.

## Correction 2: Nouveau is not the pragmatic route here

The recommendation to prefer Nouveau rested on the premise that the proprietary
NVIDIA stack would be a much larger integration project. That premise is weaker than
it looks, for a reason the conversation could not have known: **this machine is
already running NVIDIA's open kernel module.**

```
NVRM version: NVIDIA UNIX Open Kernel Module for x86_64  595.91.07
```

`open-gpu-kernel-modules` is GPL/MIT source that builds against any kernel from 4.15
onward, and `2705` is explicitly in its supported list at tag `595.91.07`. So the
open modules are:

- source-available, therefore buildable inside the ChromeOS SDK as an ebuild,
- already proven on this exact silicon,
- paired with a userspace that delivers real Vulkan performance.

Nouveau, by contrast, cannot reclock on Ada. The GSP-based generations run at boot
clocks under Nouveau, which is fine for a desktop but not for the stated goal of
Steam gaming. Choosing Nouveau would mean accepting a permanent performance ceiling
to avoid an integration problem we have good reason to think is tractable.

Hence the driver decision: **NVIDIA open kernel modules 595.91.07 plus NVIDIA
userspace**, with Nouveau retained only as a diagnostic fallback for proving PCI and
DRM plumbing if the NVIDIA module misbehaves.

## Finding: minigbm already has a nouveau backend

The most encouraging discovery, and the one that changes the Stage 3 effort estimate.

ChromeOS allocates graphics buffers through `minigbm`, not Mesa's GBM. Inspecting
`chromiumos/platform/minigbm` on `main`:

`drv.c` registers a nouveau backend alongside the rest:

```c
extern const struct backend backend_nouveau;
...
    &backend_meson,     &backend_nouveau,   &backend_radeon,  &backend_rockchip,
```

and `dumb_driver.c` implements it as a generic DRM dumb-buffer backend:

```c
INIT_DUMB_DRIVER(marvell)
INIT_DUMB_DRIVER(meson)
INIT_DUMB_DRIVER(nouveau)
INIT_DUMB_DRIVER(radeon)
```

`INIT_DUMB_DRIVER(x)` expands to a backend matched by DRM driver name `"x"` that
allocates through the standard `DRM_IOCTL_MODE_CREATE_DUMB` path.

Two consequences:

1. There is **no `nvidia-drm` backend**, so out of the box minigbm cannot allocate on
   NVIDIA and the ChromeOS UI has nothing to draw into.
2. Adding one plausibly means following the same macro pattern with the DRM driver
   name `nvidia-drm`, because NVIDIA's `nvidia-drm` implements the dumb-buffer ioctls
   when loaded with `modeset=1`.

That turns "get the ChromeOS UI onto the RTX" from a rewrite into a targeted patch.
It is still a hypothesis to be tested, and dumb buffers are linear and unaccelerated,
so GPU-optimal scanout will additionally need `libnvidia-allocator`. But the first
pixel on screen looks cheap.

See `patches/minigbm/0001-add-nvidia-drm-dumb-backend.patch`.

## Finding: Steam cannot come from Borealis

Borealis is Google-internal and was discontinued on 1 January 2026. It was never part
of the open ChromiumOS tree, so building from source does not provide it and no amount
of board configuration will.

Steam therefore has to be delivered by this project. The approach taken is a Debian
container with **direct `/dev/nvidia*` access and the version-matched NVIDIA userspace
bind-mounted in**, deliberately bypassing Crostini's virtio-gpu path. Routing Vulkan
through virtio-gpu/venus would add a translation layer between Proton and the GPU,
which is exactly what we are trying to avoid.

## Upstream facts confirmed directly

Queried rather than assumed:

- ChromeOS kernel branches top out at **`chromeos-6.12`**
  (`chromiumos/third_party/kernel`). Older available: 6.6, 6.1, 5.15, 5.10, 5.4.
- Current release branches reach **`release-R155-16820.B`**.
- `open-gpu-kernel-modules` tags include the 595.x series (595.44.10 through
  595.104.02), 610.x, and 615.71.09.
- `NVIDIA-Linux-x86_64-595.91.07.run` is downloadable, 423,651,201 bytes.
- The ChromiumOS build flow is `repo init -u .../chromiumos/manifest -b stable`,
  `repo sync`, `cros build-packages --board=...`, `cros build-image ... test`,
  `cros flash`. The `amd64-generic` board targets generic x86-64.

## Why not FydeOS or Brunch

Both were considered and rejected as starting points, for the reason the original
conversation identified: each is a prebuilt system whose assumptions must be fought
rather than configured.

- Brunch is built around a custom kernel and initramfs and explicitly declares dGPUs
  unsupported. Forking it means inheriting those assumptions plus its packaging.
- FydeOS is a downstream distribution; its NVIDIA position is a support statement, not
  a technical limit, but working inside it means no control over the kernel build.

ChromiumOS from source gives direct control over the kernel config, the graphics
stack, firmware packaging, and board definitions, which is precisely what loading an
NVIDIA driver from the kernel stack requires.
