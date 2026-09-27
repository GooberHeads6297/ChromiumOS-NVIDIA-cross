# USB test: nvidia-generic text console on the RTX

Run this **after** `./sdk/build.sh --board nvidia-generic all` finishes and
`~/chromiumos/src/build/images/nvidia-generic/latest/chromiumos_test_image.bin` exists.

Milestone: a readable **text console** on a monitor plugged into the RTX 4070 Ti SUPER.
Not Chrome UI. Not Steam.

## Flash (USB only)

```bash
cd ~/CodeEnv/ChromiumOS-NVIDIA-cross
./tools/flash.sh --board nvidia-generic --target usb --device /dev/sdc
```

Do **not** wrap the whole script in `sudo` (`dd` will ask). Type `sdc` to confirm.
Never flash `sda`.

## BIOS and cables

- Primary Display → **iGPU / CPU Graphics**
- Monitor 1 → motherboard (recovery / SSH)
- Monitor 2 → RTX (under test)
- Boot from the USB stick

## Pass / fail

| Result | Meaning |
| --- | --- |
| Text / kernel messages on the **RTX** monitor | Milestone **passed** |
| RTX blank, machine stays up, SSH works | OS booted; dig into driver/DRM next |
| Reboot loop or dead machine | Stop; return to Ubuntu on `sda` |

SSH (test image), from Ubuntu on another session or after recovering:

```bash
ssh -i ~/chromiumos/src/build/images/nvidia-generic/latest/id_rsa \
    -o StrictHostKeyChecking=no root@<DEVICE-IP>
# password fallback: test0000
```

On the device if the RTX is blank:

```bash
lspci -k -s 01:00.0
ls /sys/class/drm/
ls /dev/fb*
dmesg | grep -iE 'nvidia|nouveau|amdgpu|drm|gsp' | tail -50
```

## Ordered bring-up (do not skip)

1. Confirm fbdev / modules (`CONFIG_DRM_FBDEV_EMULATION`, nouveau or nvidia bound).
2. Copy and run `tools/verify-stage2.sh` with modesetting **off**.
3. Path A: nouveau on the RTX (control experiment).
4. Path B: `nvidia-drm modeset=1 fbdev=1` only after stage 2 passes.

## Out of scope until later

- Chrome / Ozone / EGL on NVIDIA
- Install to `nvme1n1`
- Steam (blocked in code until the OS is on a fixed disk)

See also: [HANDOFF.md](HANDOFF.md), [INSTALL.md](INSTALL.md), [SAFETY.md](../SAFETY.md).
