# Kernel configuration for the nvidia-generic board

**The real config now lives in
`overlay/overlay-nvidia-generic/kernel-config/chromiumos-x86_64-nvidia.flavour.config`,
and `sdk/build.sh` installs it into the kernel tree during the `link` stage.**

`nvidia-generic-module-support.config` is kept only as a reference list of the symbols that
matter and why. It is not applied by anything. Earlier it claimed to be a fragment to merge
by hand, which meant it never ran at all — so the settings it describes were not actually
in any build.

## How board kernel config actually works here

`cros-kernel.eclass` reads `CHROMEOS_KERNEL_SPLITCONFIG` from the board's
`profiles/base/make.defaults` and hands it to `chromeos/scripts/prepareconfig`, which does:

```
flavourconf=$(find chromeos/config/${family} -name $1.flavour.config)
cat chromeos/config/${family}/base.config \
    ${archconfdir}/common.config \
    ${flavourconf} > .config
```

Three files concatenated, flavour last, so the flavour config wins any duplicate symbol.
Our board sets `CHROMEOS_KERNEL_SPLITCONFIG="chromiumos-x86_64-nvidia"`.

## Corrections to earlier assumptions

Three of the four "out-of-tree module blockers" this project was built around were never
real. Grepping the whole of `chromeos/config/` in the 6.12 tree:

| Symbol | Occurrences | Reality |
| --- | --- | --- |
| `CONFIG_CFI_CLANG` | 0 | Never enabled. Not a blocker. |
| `CONFIG_LTO_CLANG*` | 0 | Never enabled. Not a blocker. |
| `CONFIG_TRIM_UNUSED_KSYMS` | 0 | Never enabled. Not a blocker. |
| `CONFIG_MODULE_SIG_FORCE` | 1 | Real, but set **only** in the reven flavour config. Not inherited by this board. |

So no mitigation is needed for any of them on this base. The comments in
`nvidia-generic-module-support.config` describing them as problems are wrong, and are left
in place only because the reasoning would apply if a future board did enable them.

## What actually needed changing

These are the settings that genuinely differ from what `amd64-generic` produces, and each
one would break something if omitted:

| Symbol | amd64-generic | Ours | Why it matters |
| --- | --- | --- | --- |
| `CONFIG_DRM_AMDGPU` | absent | `m` | The iGPU is Raphael `[1002:164e]` and needs amdgpu. Without it there is no recovery console, which the entire Stage 2 design rests on. |
| `CONFIG_DRM_NOUVEAU` | `y` | `m` | Built in, nouveau cannot be blacklisted and would bind to the RTX before NVIDIA's driver. A blacklist only works on a module. |
| `CONFIG_DRM_FBDEV_EMULATION` | not set | `y` | Without it a DRM driver exposes no `/dev/fb0`, so `Ctrl+Alt+F2` gives no text console and there is no way to read an error when the session is broken. Also what `nvidia-drm fbdev=1` attaches to. |
| `CONFIG_DRM_SIMPLEDRM` | — | `y` | Last-resort console from the framebuffer UEFI already set up. Needs no driver and no firmware, so it survives amdgpu failing outright. |
| `CONFIG_HMM_MIRROR`, `CONFIG_ZONE_DEVICE`, `CONFIG_DEVICE_PRIVATE` | absent | `y` | Used by the NVIDIA modules. `ZONE_DEVICE` appears only under `termina/` in this tree; `HMM_MIRROR` nowhere. |
| `CONFIG_EFIVAR_FS` | not set | `y` | Reading and managing UEFI boot entries from the running system, which matters when installing to an internal disk. |
| `CONFIG_X86_MCE_AMD` | not set | `y` | Explicitly disabled upstream, which makes little sense on an AMD host. |

A note on simpledrm: it gives a **text console only**. minigbm has `backend_amdgpu`,
`backend_nouveau` and others but nothing for `simple-framebuffer`, so Chrome cannot
allocate buffers on it and there is no graphical session. That is acceptable — its job is
to let you read errors, not to run a desktop.

## Firmware, which is not a kernel config problem

Enabling `CONFIG_DRM_AMDGPU` is necessary but not sufficient. Raphael's graphics IP is GC
10.3.6, and `amdgpu_ucode_legacy_naming()` in `amdgpu_ucode.c` has cases for GC 10.3.0,
10.3.1, 10.3.2, 10.3.3, 10.3.4, 10.3.5, 10.1.3 and 10.1.4 — but **none for 10.3.6**. With
no legacy alias the name falls through to the IP-derived form, so
`gfx_v10_0_init_microcode()` requests `amdgpu/gc_10_3_6_*.bin`.

ChromeOS's `linux-firmware` fork carries `gc_10_3_7` and `gc_11_0_x` but not `gc_10_3_6`,
and its ebuild exposes only `amdgpu`, `amdgpu_gc_11_0_1`, `amdgpu_gc_11_0_4` and
`amdgpu_yellow_carp`. Those requests would fail and amdgpu would never initialise.

`sys-firmware/amdgpu-raphael-firmware` in the board overlay supplies the seven missing
files, staged by `tools/fetch-amdgpu-firmware.sh`. If the iGPU console is dead, check
`dmesg` for failed `amdgpu/gc_10_3_6_*` requests before suspecting the kernel config.
