# Target hardware

Everything here was read off the machine, not inferred from model names. Where the
research that started this project guessed wrong, the correction is called out.

## GPU

```
01:00.0 VGA compatible controller [0300]:
        NVIDIA Corporation AD103 [GeForce RTX 4070 Ti SUPER] [10de:2705] (rev a1)
        Subsystem: ASUSTeK Computer Inc. [1043:8957]
        Kernel driver in use: nvidia
        Kernel modules: nvidiafb, nouveau, nvidia_drm, nvidia
01:00.1 Audio device [0403]:
        NVIDIA Corporation AD103 High Definition Audio Controller [10de:22bb]
```

| Property | Value |
| --- | --- |
| Marketing name | GeForce RTX 4070 Ti SUPER |
| Silicon | AD103, Ada Lovelace |
| PCI ID | `10de:2705` |
| Subsystem | `1043:8957` (ASUS) |
| VRAM | 16376 MiB |
| VBIOS | `95.03.45.80.6B` |
| GPU UUID | `GPU-3e1f769c-5840-5eab-3cb0-bb3e77dd9cea` |
| BAR1 | 16 GB prefetchable (resizable BAR active) |

**Correction to the source research.** The originating conversation assumed a plain
RTX 4070 Ti, which is **AD104** with PCI ID `10de:2782`. This machine has the
**SUPER**, which is **AD103** / `10de:2705` — different die, different device ID,
different entry in NVIDIA's support tables. Any support matrix lookup must use
`2705`.

### Confirmed driver support

`2705` appears explicitly in the supported-GPU list of
`NVIDIA/open-gpu-kernel-modules` at tag `595.91.07`:

```
| NVIDIA GeForce RTX 4070 Ti SUPER | 2705 |
```

That README states support for **Linux kernel 4.15 or newer**, so ChromeOS's newest
branch `chromeos-6.12` is comfortably in range.

### Thermal and power envelope

Read from `nvidia-smi -q -d TEMPERATURE` and `--query-gpu`. These are the numbers
`safety/limits.conf` is derived from:

| Property | Value | Enforced by |
| --- | --- | --- |
| Shutdown temperature | 97 C | Silicon |
| Slowdown temperature | 92 C | Silicon |
| Max operating | 90 C | Firmware |
| Target temperature | 84 C | Firmware |
| Power limit default | 285 W | VBIOS / VRM |
| Power limit range | 100-314 W | VBIOS / VRM |
| Max graphics clock | 3120 MHz | Stock |
| Max memory clock | 10501 MHz | Stock |

Measured idle reference: **18.8 W, 41 C, fan 0%, 345 MHz**.

The 0% fan reading at idle is this card's zero-RPM mode and is correct behaviour. It
is the reason `gpu-guard.sh` qualifies its fan-stall check with a temperature floor
instead of alarming on `fan == 0` alone.

## Host driver already in place

The host runs NVIDIA's **open** kernel module, which is the single most useful fact
for this project:

```
$ cat /proc/driver/nvidia/version
NVRM version: NVIDIA UNIX Open Kernel Module for x86_64  595.91.07
GCC version:  gcc version 15.2.0 (Ubuntu 15.2.0-16ubuntu1)
```

Installed packages:

```
nvidia-driver-595-open         595.91.07-0ubuntu0.26.04.1
nvidia-kernel-common-595       595.91.07-0ubuntu0.26.04.1
nvidia-kernel-source-595-open  595.91.07-0ubuntu0.26.04.1
```

So the open-source kernel module is already proven working on this exact silicon, on
a 7.0 kernel. That is why `595.91.07` is the pinned version rather than a newer
610.x/615.x tag: it is known-good here, and it doubles as the recovery path.

GSP firmware present on the host, which Ada requires:

```
/lib/firmware/nvidia/595.91.07/gsp_ga10x.bin   72 MB   <- Ada uses the ga10x image
/lib/firmware/nvidia/595.91.07/gsp_tu10x.bin   30 MB
```

Note that Ada loads `gsp_ga10x.bin`, not an `ad10x`-named file. There is no
`gsp_ad10x.bin`.

## Integrated GPU (the lockout safeguard)

```
0d:00.0 VGA compatible controller [0300]:
        AMD/ATI Raphael [1002:164e] (rev c2)
        Kernel driver in use: amdgpu
```

The 7900X's integrated Radeon is enabled and driven by `amdgpu`. This is the reason
bare-metal testing is low-risk: with the BIOS primary display set to the iGPU, a
broken NVIDIA modeset costs a reboot rather than access to the machine.
`preflight.sh` fails if `amdgpu` is not bound here.

## CPU, memory, platform

| Property | Value |
| --- | --- |
| CPU | AMD Ryzen 9 7900X, 12C/24T |
| Memory | 29 GiB usable (32 GB installed), 8 GiB swap |
| Motherboard | ASUSTeK TUF GAMING B850M-PLUS WIFI7 W, BIOS 1078 |
| Virtualization | AMD-V, `kvm_amd` loaded |
| IOMMU | Active, 31 groups |
| Secure Boot | Disabled |
| Host OS | Ubuntu 26.04.1 LTS, kernel 7.0.0-34-generic |

Chrome's link requires 8-28 GB of RAM to link; 29 GiB plus swap is adequate but not
generous. Expect to rely on binary packages rather than building Chrome from source.

### IOMMU isolation

Group 13 contains exactly the GPU and its audio function and nothing else:

```
/sys/kernel/iommu_groups/13/devices/0000:01:00.0
/sys/kernel/iommu_groups/13/devices/0000:01:00.1
```

Clean isolation means VFIO passthrough into a VM is available if a future stage wants
it. The iGPU sits in separate groups (24-29), so passing the RTX through would not
disturb the host console. This project targets bare metal, but the option costs
nothing to keep.

## Storage

| Device | Size | State | Role |
| --- | --- | --- | --- |
| `sda` | 931.5 GB | `sda1` /boot/efi, `sda2` / (779 GB free) | **Ubuntu. Never a target.** |
| `sdb` | 931.5 GB | Single partition, unmounted | Available bare-metal target |
| `sdc` | 29.1 GB | No partitions | Likely a USB stick |
| `nvme1n1` | 476.9 GB | No partitions, unmounted | **Preferred bare-metal target** |

`sda` is listed in `FORBIDDEN_TARGET_DISKS`; `sdb` and `nvme1n1` form the allowlist.
`preflight.sh` additionally rejects whatever disk currently carries `/`, so the
protection does not depend on the device name staying stable.

## Build environment notes

Findings that shape `sdk/bootstrap.sh`:

- **The interactive user is `gooberheads` (uid 1000), already in `sudo` and `lxd`.**
  `cros_sdk` refuses to run as root, so this is the correct setup and no user needs
  creating. (An earlier reading of `uid=0` came from a sandboxed shell, not the real
  environment.)
- **`kernel.apparmor_restrict_unprivileged_userns = 1`**, which breaks `cros_sdk`
  with errors like `Permission denied: '/proc/self/setgroups'`. Must be set to 0.
  `kernel.apparmor_restrict_unprivileged_unconfined` is also 1.
- **`umask` is `0002`**, which satisfies the ChromiumOS requirement that the last
  digit not exceed 2. Not persisted in `~/.bashrc`, so bootstrap makes it explicit.
- **Ubuntu 26.04 is newer than the documented SDK hosts** (22.04 Jammy, Debian
  Trixie). Membership in `lxd` gives a clean fallback: run the SDK inside a 24.04
  container.
- Missing tooling: `repo`, `depot_tools`, `docker`, `podman`, `virsh`.
  Present: `git` 2.53.0, `qemu-system-x86_64` 10.2.1, `python3` 3.14.4, `gcc`.
- `python3` is **3.14**, considerably newer than the SDK expects; another reason the
  container fallback exists.
