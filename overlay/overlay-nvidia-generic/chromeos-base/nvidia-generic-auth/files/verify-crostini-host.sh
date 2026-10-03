#!/bin/bash
# tools/verify-crostini-host.sh -- host-side / on-device checks that Crostini can run
# for a persistent user (NOT Guest).
#
# On-device (after local login, or as root on VT2):
#   verify-crostini-host.sh
#
# Exit 0 means the board packages/flags look present. It cannot prove the Settings
# toggle is enabled (that requires a non-Guest Chrome profile).

set -uo pipefail

FAIL=0
ok()  { printf '  [ OK ]  %s\n' "$*"; }
bad() { printf '  [FAIL]  %s\n' "$*"; FAIL=$(( FAIL + 1 )); }
hdr() { printf '\n%s\n' "$*"; }

printf '================================================================\n'
printf '  Crostini host gate (persistent users only)\n'
printf '================================================================\n'

hdr "1. USE / ui flags"
if [ -f /etc/ui_use_flags.txt ] && grep -qw kvm_host /etc/ui_use_flags.txt; then
    ok "kvm_host in ui_use_flags.txt"
else
    bad "kvm_host missing from /etc/ui_use_flags.txt"
fi

hdr "2. VM / Termina packages"
for p in vm_host_tools concierge crostini_client; do
    if ls /var/db/pkg/chromeos-base/${p}-* >/dev/null 2>&1 || \
       command -v "$p" >/dev/null 2>&1 || \
       [ -e "/usr/bin/${p}" ] || [ -e "/usr/sbin/${p}" ]; then
        ok "${p} present"
    else
        # concierge is a daemon path
        if [ "$p" = "concierge" ] && [ -x /usr/bin/vm_concierge ] || status vm_concierge 2>/dev/null | grep -q start; then
            ok "concierge/vm_concierge present"
        else
            bad "${p} not found"
        fi
    fi
done

hdr "3. KVM device"
if [ -e /dev/kvm ]; then
    ok "/dev/kvm exists"
else
    bad "/dev/kvm missing — VMs cannot start"
fi

hdr "4. Guest session reminder"
echo "  [INFO]  Guest mode always grays out Linux. Sign in as a local persistent user."
if cryptohome --action=is_mounted 2>/dev/null | grep -qi guest; then
    bad "Guest (or guest-like) mount looks active — sign out before testing Linux"
else
    ok "no obvious guest mount string from is_mounted"
fi

printf '\n'
if [ "$FAIL" -eq 0 ]; then
    printf 'PASS — host side ready; enable Linux after local-user login\n'
    exit 0
fi
printf 'FAIL (%d checks)\n' "$FAIL"
exit 1
