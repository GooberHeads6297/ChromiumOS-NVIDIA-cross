#!/bin/bash
# tools/fetch-amdgpu-firmware.sh -- stage the amdgpu GC 10.3.6 (Raphael) firmware.
#
# Why this is needed:
#
#   This machine's iGPU is Raphael [1002:164e], graphics IP GC 10.3.6. In the 6.12 tree
#   amdgpu_ucode_legacy_naming() has no case for IP_VERSION(10, 3, 6), so the firmware name
#   falls through to the IP-derived form and amdgpu requests amdgpu/gc_10_3_6_*.bin.
#   ChromeOS's linux-firmware fork does not carry those files -- it has gc_10_3_7 and
#   gc_11_0_x -- so amdgpu would fail to initialise and the Stage 2 recovery console,
#   which the whole safety design rests on, would not exist.
#
# Source of the files, in preference order:
#
#   1. The running host. Ubuntu already drives this exact iGPU with amdgpu, so its copy is
#      known-good on this hardware. Files are zstd-compressed and are decompressed here,
#      because ChromeOS's kernel config does not guarantee CONFIG_FW_LOADER_COMPRESS_ZSTD.
#   2. Upstream linux-firmware over git, for reproducibility on a machine that lacks them.
#
# Usage:
#   ./tools/fetch-amdgpu-firmware.sh            # host first, then upstream
#   ./tools/fetch-amdgpu-firmware.sh --upstream # force the upstream clone
#   ./tools/fetch-amdgpu-firmware.sh --verify   # check what is staged, change nothing
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "${REPO_ROOT}/safety/lib-common.sh"

DEST="${REPO_ROOT}/overlay/overlay-nvidia-generic/sys-firmware/amdgpu-raphael-firmware/files"
HOST_FW_DIR=/lib/firmware/amdgpu
UPSTREAM_URL="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git"

# The full set Raphael's IP blocks request. Every one of these is on a fatal path -- the
# request sites all propagate their error up through amdgpu's early_init/sw_init, so a
# single missing file means the iGPU does not come up at all.
#
#   GC 10.3.6    gfx_v10_0_init_microcode()  "amdgpu/%s_{pfp,me,ce,rlc,mec,mec2}.bin"
#   SDMA 5.2.6   amdgpu_sdma_init_microcode()        "amdgpu/%s.bin"
#   PSP 13.0.5   psp_v13_0_init_microcode() -> psp_init_toc_microcode + psp_init_ta_microcode,
#                both "if (err) return err"
#   VCN 3.1.2    amdgpu_vcn_early_init()             "amdgpu/%s.bin"
#   DCN 3.1.6    display core, dmcub
#
# gc_10_3_6_mec2.bin is a symlink to gc_10_3_6_mec.bin upstream; resolved to a real file
# here because the kernel firmware loader resolves names, not links.
#
# No smu_13_0_5.bin: on this APU the SMU firmware comes from the platform BIOS, and
# upstream linux-firmware ships no such file.
FW_FILES=(
    gc_10_3_6_ce.bin
    gc_10_3_6_me.bin
    gc_10_3_6_mec.bin
    gc_10_3_6_mec2.bin
    gc_10_3_6_pfp.bin
    gc_10_3_6_rlc.bin
    sdma_5_2_6.bin
    psp_13_0_5_toc.bin
    psp_13_0_5_ta.bin
    vcn_3_1_2.bin
    dcn_3_1_6_dmcub.bin
)

MODE=auto
case "${1:-}" in
    --upstream) MODE=upstream ;;
    --verify)   MODE=verify ;;
    -h|--help)  sed -n '1,25p' "$0"; exit 0 ;;
    "")         ;;
    *)          die "unknown argument: $1" ;;
esac

verify_staged() {
    local ok=0 missing=0 f
    banner "staged firmware in ${DEST}"
    for f in "${FW_FILES[@]}"; do
        if [ -s "${DEST}/${f}" ]; then
            printf '  [ OK ]  %-24s %s bytes  %s\n' "$f" \
                "$(stat -c%s "${DEST}/${f}")" \
                "$(sha256sum "${DEST}/${f}" | cut -c1-16)"
            ok=$((ok + 1))
        else
            printf '  [MISS]  %s\n' "$f"
            missing=$((missing + 1))
        fi
    done
    printf '\n'
    if [ "$missing" -eq 0 ]; then
        log "all ${ok} files staged"
        return 0
    fi
    warn "${missing} file(s) missing"
    return 1
}

if [ "$MODE" = "verify" ]; then
    verify_staged
    exit $?
fi

mkdir -p "$DEST" || die "cannot create ${DEST}"

# ---- source 1: the running host ------------------------------------------
staged=0
if [ "$MODE" = "auto" ]; then
    banner "staging from the running host"
    if ! command -v zstd >/dev/null 2>&1; then
        warn "zstd not found; cannot decompress the host's firmware"
    else
        all_present=1
        for f in "${FW_FILES[@]}"; do
            [ -e "${HOST_FW_DIR}/${f}" ] || [ -e "${HOST_FW_DIR}/${f}.zst" ] || all_present=0
        done
        if [ "$all_present" -eq 1 ]; then
            for f in "${FW_FILES[@]}"; do
                if [ -e "${HOST_FW_DIR}/${f}.zst" ]; then
                    # -f because mec2 is a symlink to mec upstream and zstd follows it,
                    # producing a real file, which is what we want.
                    zstd -dqfc "${HOST_FW_DIR}/${f}.zst" > "${DEST}/${f}" \
                        || die "failed to decompress ${f}.zst"
                    log "decompressed ${f}"
                else
                    cp -L "${HOST_FW_DIR}/${f}" "${DEST}/${f}" || die "failed to copy ${f}"
                    log "copied ${f}"
                fi
            done
            staged=1
        else
            warn "the host does not have the full GC 10.3.6 set; falling back to upstream"
        fi
    fi
fi

# ---- source 2: upstream linux-firmware -----------------------------------
if [ "$staged" -eq 0 ]; then
    banner "staging from upstream linux-firmware"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    log "cloning ${UPSTREAM_URL} (shallow, no blobs until needed)"
    git clone --depth 1 --filter=blob:none --sparse "$UPSTREAM_URL" "${tmp}/lf" \
        || die "clone failed; no network, or the URL moved"
    ( cd "${tmp}/lf" && git sparse-checkout set amdgpu ) || die "sparse-checkout failed"
    for f in "${FW_FILES[@]}"; do
        src="${tmp}/lf/amdgpu/${f}"
        [ -e "$src" ] || die "upstream has no amdgpu/${f}"
        cp -L "$src" "${DEST}/${f}" || die "failed to copy ${f}"
        log "copied ${f}"
    done
fi

printf '\n'
verify_staged || die "staging incomplete"

cat <<EOF

These files are consumed by:
  overlay/overlay-nvidia-generic/sys-firmware/amdgpu-raphael-firmware/

They are deliberately NOT committed -- they are redistributable vendor blobs with their
own licence, and re-running this script reproduces them. See .gitignore.
EOF
