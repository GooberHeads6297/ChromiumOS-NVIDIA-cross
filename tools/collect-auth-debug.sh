#!/bin/bash
# tools/collect-auth-debug.sh -- dump TPM / cryptohome / login state.
#
# Run ON the ChromiumOS device (test image: root / test0000), or via SSH:
#   scp tools/collect-auth-debug.sh root@<device>:/tmp/
#   ssh root@<device> /tmp/collect-auth-debug.sh
#
# Writes a single report to stdout (redirect to a file if you want to keep it).

set -uo pipefail

section() { printf '\n======== %s ========\n' "$*"; }

section "host / time"
date
uname -a
cat /etc/lsb-release 2>/dev/null || true

section "TPM devices"
ls -l /dev/tpm* /dev/tspi* 2>&1 || true

section "tpm_manager_client status"
if command -v tpm_manager_client >/dev/null 2>&1; then
    tpm_manager_client status 2>&1 || true
    tpm_manager_client get_tpm_status 2>&1 || true
else
    echo "tpm_manager_client not installed"
fi

section "init jobs (tpm / cryptohome / ui)"
for j in tpm2-simulator vtpmd tpm_managerd trunksd cryptohomed ui; do
    if command -v status >/dev/null 2>&1; then
        status "$j" 2>&1 || echo "$j: unknown"
    fi
done

section "USE-relevant packages present?"
for p in tpm2-simulator cryptohome chromeos-login; do
    if equery l "$p" >/dev/null 2>&1; then
        equery l "$p" 2>&1
    else
        ls -d /var/db/pkg/*/${p}-* 2>/dev/null || echo "$p: not in vdb"
    fi
done

section "cryptohome system salt / login status"
if command -v cryptohome >/dev/null 2>&1; then
    cryptohome --action=get_system_salt 2>&1 || true
    cryptohome --action=get_login_status 2>&1 || true
else
    echo "cryptohome CLI missing"
fi

section "homes / shadow"
ls -la /home 2>&1 || true
ls -la /home/.shadow 2>&1 || true
df -h / /mnt/stateful_partition /home 2>&1 || true

section "cryptohomed.log (tail)"
tail -n 200 /var/log/cryptohomed.log 2>&1 || true

section "messages (cryptohome/tpm)"
grep -iE 'cryptohome|tpm|trunks|userdataauth' /var/log/messages 2>/dev/null | tail -n 80 || true

section "chrome log (tail)"
if [ -d /var/log/chrome ]; then
    # newest chrome log
    newest="$(ls -t /var/log/chrome/chrome 2>/dev/null | head -1)"
    if [ -n "$newest" ]; then
        echo "# $newest"
        grep -iE 'cryptohome|gaia|login|auth|mount|oobe|local.account' "$newest" 2>/dev/null | tail -n 80 || true
    else
        ls -la /var/log/chrome 2>&1 || true
    fi
else
    echo "no /var/log/chrome"
fi

section "chrome_dev.conf"
ls -la /etc/chrome_dev.conf 2>&1 || true
sed -n '1,120p' /etc/chrome_dev.conf 2>/dev/null || true

section "done"
echo "Paste this report into the host session if asking for help."
