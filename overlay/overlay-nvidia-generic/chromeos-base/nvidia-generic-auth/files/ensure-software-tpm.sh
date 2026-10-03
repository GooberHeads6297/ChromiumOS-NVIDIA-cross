#!/bin/bash
# ensure-software-tpm.sh -- sanity-check the software TPM path before login work.
#
# Dual-boot: Ubuntu may own the hardware TPM. nvidia-generic inherits amd64-generic's
# tpm2_simulator + vtpm_proxy stack so cryptohome should not need /dev/tpm0.
# This script only reports and, when safe, starts missing simulator jobs.

set -euo pipefail

ok=0
warn() { echo "[sw-tpm] WARN: $*" >&2; }
log()  { echo "[sw-tpm] $*"; }

if [ -e /dev/tpm0 ] || [ -e /dev/tpmrm0 ]; then
    log "hardware TPM node present (may be owned by another OS): $(ls /dev/tpm* 2>/dev/null | tr '\n' ' ')"
else
    log "no hardware TPM device node — expected on this dual-boot host when Ubuntu holds ownership or nodes are gated"
fi

for job in tpm2-simulator vtpmd trunksd tpm_managerd cryptohomed; do
    if command -v status >/dev/null 2>&1; then
        st="$(status "$job" 2>&1 || true)"
        log "$st"
        if ! printf '%s' "$st" | grep -q "start/running"; then
            warn "$job not running"
            if [ "$job" = "tpm2-simulator" ] || [ "$job" = "vtpmd" ]; then
                start "$job" 2>/dev/null || warn "could not start $job"
            fi
            ok=1
        fi
    fi
done

if cryptohome --action=get_system_salt >/tmp/sw-tpm-salt.out 2>&1; then
    log "cryptohome get_system_salt OK"
else
    warn "cryptohome get_system_salt failed:"
    sed 's/^/  | /' /tmp/sw-tpm-salt.out
    exit 1
fi

exit "$ok"
