#!/bin/bash
# build-nvidia-modules.sh -- build NVIDIA's open kernel modules against a ChromeOS kernel.
#
# Called from nvidia-open-drivers-*.ebuild. Lives as a standalone script because the
# interesting part is kernel-config archaeology, and that is far easier to read, audit
# and run by hand here than inside an ebuild.
#
# What NVIDIA's build wants (from kernel-open/Makefile and utils.mk):
#   SYSSRC   kernel source tree
#   SYSOUT   kernel build output tree (becomes KBUILD_OUTPUT when it differs)
#   ARCH     x86_64
#   CC / LD  if unset, NVIDIA infers CC from CONFIG_CC_VERSION_TEXT in the kernel
#            .config, which is exactly the right behaviour for a clang-built ChromeOS
#            kernel -- the kernel interface layer must be built by the same toolchain
#            that built the kernel.
#
# `make modules` first builds the OS-agnostic nv-kernel.o and nv-modeset-kernel.o, then
# descends into kernel-open/ and runs kbuild to produce:
#   nvidia.ko  nvidia-modeset.ko  nvidia-drm.ko  nvidia-uvm.ko
#
# Usage:
#   build-nvidia-modules.sh --ogkm DIR --kernel-src DIR [--kernel-out DIR] [--output DIR]
#   build-nvidia-modules.sh --probe --kernel-src DIR      # report config blockers only

set -uo pipefail

OGKM=""
KSRC=""
KOUT=""
OUTDIR=""
PROBE=0
JOBS="$(nproc 2>/dev/null || echo 4)"

while [ $# -gt 0 ]; do
    case "$1" in
        --ogkm)       OGKM="${2:?}"; shift ;;
        --kernel-src) KSRC="${2:?}"; shift ;;
        --kernel-out) KOUT="${2:?}"; shift ;;
        --output)     OUTDIR="${2:?}"; shift ;;
        --jobs)       JOBS="${2:?}"; shift ;;
        --probe)      PROBE=1 ;;
        -h|--help)    sed -n '1,25p' "$0"; exit 0 ;;
        *)            echo "unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[nvidia-modules] $*" >&2; }

[ -n "$KSRC" ] || die "--kernel-src is required"
[ -d "$KSRC" ] || die "kernel source not found: ${KSRC}"
KOUT="${KOUT:-$KSRC}"

# ---------------------------------------------------------------------------
# Inspect the kernel configuration for the things that break out-of-tree modules.
#
# This is the single most useful diagnostic in the whole project: every one of these
# produces a confusing failure much later if missed.
# ---------------------------------------------------------------------------
CONFIG=""
for c in "${KOUT}/.config" "${KSRC}/.config"; do
    [ -f "$c" ] && { CONFIG="$c"; break; }
done

cfg() {
    [ -n "$CONFIG" ] || { echo "?"; return; }
    if grep -q "^${1}=y" "$CONFIG" 2>/dev/null; then echo y
    elif grep -q "^${1}=m" "$CONFIG" 2>/dev/null; then echo m
    else echo n
    fi
}

BLOCKERS=0
probe_config() {
    if [ -z "$CONFIG" ]; then
        log "WARNING: no kernel .config found under ${KOUT} or ${KSRC}; cannot pre-check"
        return 0
    fi
    log "inspecting ${CONFIG}"

    local modules cfi lto sig_force sig_all trim drm
    modules="$(cfg CONFIG_MODULES)"
    cfi="$(cfg CONFIG_CFI_CLANG)"
    lto="$(cfg CONFIG_LTO_CLANG_FULL)$(cfg CONFIG_LTO_CLANG_THIN)"
    sig_force="$(cfg CONFIG_MODULE_SIG_FORCE)"
    sig_all="$(cfg CONFIG_MODULE_SIG_ALL)"
    trim="$(cfg CONFIG_TRIM_UNUSED_KSYMS)"
    drm="$(cfg CONFIG_DRM)"

    # Loadable module support is non-negotiable.
    if [ "$modules" != "y" ]; then
        log "BLOCKER CONFIG_MODULES=${modules} -- the kernel cannot load any module"
        BLOCKERS=$(( BLOCKERS + 1 ))
    else
        log "ok      CONFIG_MODULES=y"
    fi

    # DRM must be present for nvidia-drm to register a KMS device.
    if [ "$drm" = "n" ]; then
        log "BLOCKER CONFIG_DRM=n -- nvidia-drm cannot register without DRM"
        BLOCKERS=$(( BLOCKERS + 1 ))
    else
        log "ok      CONFIG_DRM=${drm}"
    fi

    # Clang CFI instruments indirect calls and routinely rejects out-of-tree modules
    # whose function pointers cross the kernel boundary. This is the expected Stage 2
    # obstacle; patches/kernel/ disables it for this board.
    if [ "$cfi" = "y" ]; then
        log "BLOCKER CONFIG_CFI_CLANG=y -- indirect-call checks will reject this module."
        log "        Apply patches/kernel/nvidia-generic-module-support.config"
        BLOCKERS=$(( BLOCKERS + 1 ))
    else
        log "ok      CONFIG_CFI_CLANG=n"
    fi

    # Kernel-wide LTO requires every module be built into the same LTO plan. NVIDIA's
    # prebuilt OS-agnostic objects are not, so full/thin LTO must be off.
    case "$lto" in
        *y*)
            log "BLOCKER CONFIG_LTO_CLANG is enabled -- NVIDIA's OS-agnostic objects are not LTO bitcode."
            log "        Apply patches/kernel/nvidia-generic-module-support.config"
            BLOCKERS=$(( BLOCKERS + 1 ))
            ;;
        *) log "ok      CONFIG_LTO_CLANG disabled" ;;
    esac

    # A forced signature requirement rejects unsigned out-of-tree modules outright.
    if [ "$sig_force" = "y" ]; then
        log "BLOCKER CONFIG_MODULE_SIG_FORCE=y -- unsigned modules are refused at load time."
        log "        Either disable it for this board or sign the modules after build."
        BLOCKERS=$(( BLOCKERS + 1 ))
    else
        log "ok      CONFIG_MODULE_SIG_FORCE=n"
    fi
    [ "$sig_all" = "y" ] && log "note    CONFIG_MODULE_SIG_ALL=y (in-tree modules signed; ours will need signing too)"

    # Symbol trimming removes exported symbols no in-tree module uses, which is fatal
    # for a module added after the kernel was configured.
    if [ "$trim" = "y" ]; then
        log "BLOCKER CONFIG_TRIM_UNUSED_KSYMS=y -- symbols NVIDIA needs may have been trimmed away."
        BLOCKERS=$(( BLOCKERS + 1 ))
    else
        log "ok      CONFIG_TRIM_UNUSED_KSYMS=n"
    fi

    # Informational: what built the kernel. NVIDIA will match this automatically.
    local cc_text
    cc_text="$(sed -n 's/^CONFIG_CC_VERSION_TEXT="\(.*\)"$/\1/p' "$CONFIG" 2>/dev/null | head -1)"
    [ -n "$cc_text" ] && log "note    kernel built by: ${cc_text}"

    return 0
}

probe_config

if [ "$PROBE" -eq 1 ]; then
    if [ "$BLOCKERS" -eq 0 ]; then
        log "no blocking kernel config options found"
        exit 0
    fi
    log "${BLOCKERS} blocking kernel config option(s) found"
    exit 1
fi

[ -n "$OGKM" ] || die "--ogkm is required to build"
[ -d "$OGKM" ] || die "module source not found: ${OGKM}"

if [ "$BLOCKERS" -gt 0 ]; then
    die "${BLOCKERS} kernel config blocker(s); fix the kernel config before building.
       Run with --probe for the list, and see patches/kernel/."
fi

# ---------------------------------------------------------------------------
# Build.
# ---------------------------------------------------------------------------
log "building modules (SYSSRC=${KSRC} SYSOUT=${KOUT} -j${JOBS})"

make -C "$OGKM" modules \
    -j"$JOBS" \
    SYSSRC="$KSRC" \
    SYSOUT="$KOUT" \
    ARCH=x86_64 \
    NV_VERBOSE=1 \
    || die "module build failed.

       If the failure mentions CFI, LTO, or an unresolved symbol, it is the ChromeOS
       kernel's hardening rejecting an out-of-tree module. Re-run with --probe and see
       docs/architecture.md, 'ChromeOS kernel toolchain versus an out-of-tree module'."

# ---------------------------------------------------------------------------
# Collect results.
# ---------------------------------------------------------------------------
EXPECTED="nvidia.ko nvidia-modeset.ko nvidia-drm.ko nvidia-uvm.ko"
missing=""
for m in $EXPECTED; do
    find "$OGKM/kernel-open" -name "$m" -print -quit 2>/dev/null | grep -q . || missing="${missing} ${m}"
done
[ -z "$missing" ] || die "build finished but these modules are missing:${missing}"

log "built:"
for m in $EXPECTED; do
    p="$(find "$OGKM/kernel-open" -name "$m" -print -quit 2>/dev/null)"
    log "  ${m}  ($(du -h "$p" 2>/dev/null | cut -f1))"
done

if [ -n "$OUTDIR" ]; then
    mkdir -p "$OUTDIR"
    for m in $EXPECTED; do
        p="$(find "$OGKM/kernel-open" -name "$m" -print -quit 2>/dev/null)"
        cp -v "$p" "$OUTDIR/" >&2
    done
    log "modules copied to ${OUTDIR}"
fi

log "done"
