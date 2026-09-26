# SAFETY

There is exactly one RTX 4070 Ti SUPER in this machine and no spare. This document
explains what can and cannot hurt it, and what this repository does about it.

Read the first section before worrying. The short version is that driver work is not
how graphics cards die.

## Why a driver fault cannot destroy the card

Every limit that protects this card sits **below** the host driver, in places a
buggy kernel module cannot reach:

- **Board power limit** is enforced by the VRM controller against values fused into
  the VBIOS. Measured on this card: 285 W default, 314 W absolute maximum, 100 W
  floor. The driver can request a number inside that window; it cannot widen it.
- **Thermal slowdown at 92 C** and **thermal shutdown at 97 C** are implemented in
  silicon. They do not require a working driver, a running daemon, or a booted OS.
- **Fan and power management live in GSP firmware.** On Ada the GPU System Processor
  owns the fan curve and power arbitration independently of the host kernel driver.
  This is precisely why a half-working driver still gets correct fan behaviour.

These are the values this card actually reports, not estimates:

```
GPU Shutdown Temp     : 97 C     <- silicon
GPU Slowdown Temp     : 92 C     <- silicon
GPU Max Operating Temp: 90 C
GPU Target Temperature: 84 C
Power limit           : 285 W default, 100 W min, 314 W max
```

So the realistic failure modes of this project are:

| What happens | Recovery |
| --- | --- |
| Xid error, GPU falls off the bus | Power cycle |
| Module refuses to load (GSP firmware/driver version mismatch) | Fix the version pin |
| Black screen after modeset | iGPU console, or power cycle |
| PCIe AER error storm | Power cycle |
| Kernel panic | Power cycle |

Every row ends in "power cycle". None ends in "buy a new GPU".

## The three things that genuinely could destroy it

All three are forbidden here, and two of them are checked by scripts rather than
left to memory.

### 1. Writing the VBIOS

A failed or mismatched firmware flash is the one reliable way to turn this card into
a brick. **This project never flashes firmware.** There is no step, stage, or
fallback that requires it.

`safety/lib-common.sh` defines `assert_no_flash_tools()`, and `safety/preflight.sh`
fails outright if `nvflash`, `nvflash64`, `nvidia-vbios-flash`, or `amdvbflash` is
found on `PATH`.

**A necessary clarification about `/sys/.../rom`.** `safety/vbios-backup.sh` does
write `1` to `/sys/bus/pci/devices/0000:01:00.0/rom`, and that is safe. The kernel's
`pci_write_rom()` handler treats that attribute as a read-enable toggle — writing to
it sets an internal flag and nothing more (`drivers/pci/pci-sysfs.c`). It has no path
to the card's EEPROM. Actual flashing requires a vendor tool driving the flash
controller directly. Do not let the word "write" here be confused with programming
firmware; they are unrelated operations.

### 2. Overvolting or overclocking

Running silicon outside its designed voltage/frequency envelope is a real,
cumulative damage mechanism. This project only ever moves limits **downward**.

`assert_caps_sane()` refuses to start if `limits.conf` asks for more than stock:

- `POWER_CAP_W` must be within `[100, 285]`. It is set to **200 W** during bring-up.
- `CLOCK_CEIL_MHZ` must be at or below the stock 3120 MHz. It is set to **2100 MHz**.

If someone edits `limits.conf` to raise a limit, the scripts stop instead of
complying.

### 3. Running hot with stalled fans

This is the only damaging state that host software can plausibly cause, so it gets
dedicated handling in `safety/gpu-guard.sh`.

The subtlety: **0% fan is normal on this card.** It uses zero-RPM idle, measured at
0% fan / 41 C / 18.8 W. A naive "fans stopped, panic" check would fire constantly and
get disabled, which is worse than no check. So the trip condition is fan at 0%
**while the GPU is at or above 70 C**, confirmed over 10 consecutive polls. That
combination is not a fan profile, it is a fan failure.

## What the guard does

`safety/gpu-guard.sh` polls once per second and escalates. Every level must be
confirmed over consecutive samples, because sensors glitch and `poweroff` is rude.

| Level | Trip | Action |
| --- | --- | --- |
| Warn | 78 C | Log only |
| Soft | 83 C x3 | Halve the graphics clock ceiling |
| Hard | 87 C x3 | Terminate GPU client processes |
| Critical | 90 C x3 | Kill clients, sync, power off |
| Fan stall | 0% fan at >=70 C x10 | Kill clients, sync, power off |

Critical fires at 90 C, two degrees below the silicon slowdown at 92 C. The intent is
that the hardware protection never has to engage — it is the backstop, not the plan.

The ladder is verified without touching the GPU:

```bash
./safety/gpu-guard.sh --self-test
```

This drives synthetic samples through `evaluate()` and asserts each level fires where
it should, including the two cases most likely to be got wrong: that idle 41 C with
0% fan stays silent, and that a single cool sample resets a pending trip.

## Bare-metal test protocol

Bare metal is the goal, so the protection is procedural as well as automated.

1. **The iGPU keeps the console.** Set the BIOS primary display to the CPU/iGPU.
   `preflight.sh` fails if `amdgpu` is not bound to `0000:0d:00.0`. As long as that
   holds, a broken NVIDIA modeset costs a reboot, not access to the machine.
2. **Never install to `sda`.** Ubuntu lives there. `limits.conf` puts `sda` in
   `FORBIDDEN_TARGET_DISKS`, the allowlist is `sdb` and `nvme1n1`, and
   `tools/flash.sh` refuses anything else. `preflight.sh` additionally rejects any
   target that is the disk currently carrying `/`.
3. **Physically unplugging the Ubuntu disk during early tests costs nothing** and is
   the strongest guarantee available. Recommended for the first NVIDIA-enabled boot.
4. **Build `test` images.** They accept SSH (`test0000`), so logs survive a black
   screen. Configure a serial console for panics.
5. **Arm the guard before applying load**, not after.
6. **Keep a recovery path**: an Ubuntu live USB, plus the known-good
   `nvidia-driver-595-open` package already installed on the host.

## Physical notes

- This card uses a **12V-2x6 / 12VHPWR connector**. Confirm it is fully seated once,
  at the start. A partially seated connector is a genuine thermal hazard and has
  nothing to do with software.
- Do not hot-plug the card. Power down fully before touching it.
- Standard ESD care when the case is open.

## Checklist before each bare-metal test

```bash
sudo ./safety/vbios-backup.sh          # once, insurance only
sudo ./safety/preflight.sh nvme1n1     # must exit 0
./safety/gpu-guard.sh --self-test      # must pass
sudo ./safety/gpu-guard.sh             # arm, leave running
```

If `preflight.sh` fails, stop and fix the failure. It is cheaper than the
alternative every single time.
