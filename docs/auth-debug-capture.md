# Auth / cryptohome diagnosis capture

Host was on Ubuntu (`sda`) with ChromiumOS USB on `/dev/sdc` at capture time — live
DUT SSH was not available. `tools/collect-auth-debug.sh` is the on-device dump; run it
after the next USB boot and append the output below.

## Host-side evidence (2026-10-02)

| Check | Result |
| --- | --- |
| Ubuntu rootfs | `/dev/sda2` mounted at `/` |
| ChromiumOS USB | `/dev/sdc` labeled STATE/ROOT-A/OEM (R156 test image previously flashed) |
| Hardware TPM sysfs | `/sys/class/tpm/tpm0` → `MSFT0101:00`, `tpm_version_major` present |
| Hardware TPM device node | **No** `/dev/tpm0` or `/dev/tpmrm0` in this Ubuntu session (sysfs only) |
| Image contents (base image package sizes) | Ships `chromeos-base/tpm2-simulator`, `vtpm`, `tpm_manager`, `cryptohome` |
| Board inheritance | `amd64-generic` sets `-tpm tpm2 tpm2_simulator tpm2_simulator_manufacturer vtpm_proxy` |

## Working diagnosis

1. Dual-boot TPM conflict remains the default risk: when ChromiumOS *does* see the
   hardware TPM, Ubuntu may already own it → seal/unseal failures look like
   “cryptohome corrupted”.
2. The nvidia-generic image **already includes** the software TPM stack. Failures seen
   at the Get Started / Gaia screen are therefore more often **OOBE/Gaia without API
   keys** or a half-created vault than a missing simulator.
3. Mitigation in-tree: affirm simulator USE flags, `oobe_skip_to_login`, and
   `chromeos-base/nvidia-generic-auth` (`create-local-account.sh` + chrome_dev flags).

## On-device capture (fill after USB boot)

```bash
ssh -i ~/chromiumos/src/build/images/nvidia-generic/latest/id_rsa \
    -o StrictHostKeyChecking=no root@<DEVICE-IP>
# password: test0000

/usr/share/chromiumos-nvidia-cross/collect-auth-debug.sh | tee /tmp/auth-debug.txt
# or scp tools/collect-auth-debug.sh if the package is not in the image yet
```

Paste / archive `/tmp/auth-debug.txt` next to this note when available.
