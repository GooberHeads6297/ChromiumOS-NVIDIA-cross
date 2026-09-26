#!/bin/bash
# tools/fetch-nvidia.sh -- stage the version-matched NVIDIA driver bundle.
#
# The kernel module, the userspace libraries and the GSP firmware must all be the
# same version or the module refuses to load. This script fetches all three from a
# single pinned version so they cannot drift apart.
#
# Nothing here is installed onto the host. The .run installer is EXTRACTED, never
# executed: running it would replace the host's working driver, which is our recovery
# path. Extraction is done with --extract-only, which only unpacks the archive.
#
# Output lands in vendor/ (gitignored -- the bundle is ~420 MB and not ours to
# redistribute).
#
# Usage:
#   ./tools/fetch-nvidia.sh              # fetch, verify, extract
#   ./tools/fetch-nvidia.sh --verify     # re-check what is already staged
#   ./tools/fetch-nvidia.sh --clean      # remove vendor/

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "${REPO_ROOT}/safety/lib-common.sh"

load_limits

VERSION="${NVIDIA_DRIVER_VERSION}"
VENDOR="${REPO_ROOT}/vendor"
RUN_FILE="NVIDIA-Linux-x86_64-${VERSION}.run"
RUN_URL="https://download.nvidia.com/XFree86/Linux-x86_64/${VERSION}/${RUN_FILE}"
OGKM_URL="https://github.com/NVIDIA/open-gpu-kernel-modules.git"

# Pinned upstream identities, retrieved from the publisher rather than trusted blindly.
#   sha256 from https://download.nvidia.com/.../${RUN_FILE}.sha256sum
#
# NVIDIA's release tags are annotated tag objects, so `ls-remote refs/tags/<v>` returns
# the tag object (26d82922...) while the clone checks out the commit it points at. The
# pin below is the peeled commit, i.e. `refs/tags/595.91.07^{}`.
RUN_SHA256="ca23c88dd24b07a191644e1e11cfb7bcdd7537305749af40f980018b095e6313"
OGKM_COMMIT="9f087a6d4e86d85acc0ce1d354d6276fe5047b29"
OGKM_TAG_OBJECT="26d82922dc1e444f274294505f73f1c0b8ca682d"

MODE=fetch
while [ $# -gt 0 ]; do
    case "$1" in
        --verify)  MODE=verify ;;
        --clean)   MODE=clean ;;
        -h|--help) sed -n '1,20p' "$0"; exit 0 ;;
        *)         die "unknown argument: $1" ;;
    esac
    shift
done

RUN_PATH="${VENDOR}/${RUN_FILE}"
EXTRACT_DIR="${VENDOR}/NVIDIA-Linux-x86_64-${VERSION}"
OGKM_DIR="${VENDOR}/open-gpu-kernel-modules"

if [ "$MODE" = clean ]; then
    log "removing ${VENDOR}"
    rm -rf "$VENDOR"
    exit 0
fi

# ---------------------------------------------------------------------------
verify_bundle() {
    local ok=0
    banner "verifying staged bundle (${VERSION})"

    if [ -f "$RUN_PATH" ]; then
        log "checking ${RUN_FILE} sha256"
        if printf '%s  %s\n' "$RUN_SHA256" "$RUN_PATH" | sha256sum -c --status 2>/dev/null; then
            log "  OK  installer checksum matches the published value"
        else
            err "  BAD installer checksum mismatch -- delete it and refetch"
            ok=1
        fi
    else
        warn "  --  installer not staged"
        ok=1
    fi

    if [ -d "$OGKM_DIR/.git" ]; then
        local have
        have="$(git -C "$OGKM_DIR" rev-parse HEAD 2>/dev/null)"
        if [ "$have" = "$OGKM_COMMIT" ]; then
            log "  OK  kernel module source at pinned commit ${OGKM_COMMIT:0:12}"
        else
            err "  BAD kernel module source at ${have:0:12}, expected ${OGKM_COMMIT:0:12}"
            ok=1
        fi
    else
        warn "  --  kernel module source not staged"
        ok=1
    fi

    # The single most important cross-check: does the module source claim the same
    # version as the userspace we extracted? A mismatch here is the classic cause of
    # "module loads but nvidia-smi says version mismatch".
    if [ -f "${OGKM_DIR}/version.mk" ]; then
        local src_ver
        src_ver="$(sed -n 's/^NVIDIA_VERSION *= *//p' "${OGKM_DIR}/version.mk" | tr -d ' ')"
        if [ "$src_ver" = "$VERSION" ]; then
            log "  OK  module source version.mk says ${src_ver}"
        else
            err "  BAD module source says ${src_ver}, expected ${VERSION}"
            ok=1
        fi
    fi

    if [ -d "$EXTRACT_DIR" ]; then
        log "  OK  userspace extracted to ${EXTRACT_DIR##*/}"
        local fw="${EXTRACT_DIR}/firmware/${NVIDIA_GSP_FIRMWARE}"
        if [ -f "$fw" ]; then
            log "  OK  GSP firmware ${NVIDIA_GSP_FIRMWARE} present ($(du -h "$fw" | cut -f1))"
        else
            err "  BAD GSP firmware ${NVIDIA_GSP_FIRMWARE} missing -- Ada cannot initialise without it"
            ok=1
        fi
        local lib
        for lib in libnvidia-egl-gbm.so libnvidia-allocator.so libEGL_nvidia.so libGLX_nvidia.so; do
            if find "$EXTRACT_DIR" -maxdepth 2 -name "${lib}*" -print -quit 2>/dev/null | grep -q .; then
                log "  OK  ${lib} present"
            else
                warn "  --  ${lib} not found (needed for the Chrome/Ozone display path)"
            fi
        done
    else
        warn "  --  userspace not extracted"
        ok=1
    fi

    printf '\n'
    if [ "$ok" -eq 0 ]; then
        banner "bundle verified"
    else
        banner "bundle incomplete or mismatched"
    fi
    return "$ok"
}

if [ "$MODE" = verify ]; then
    verify_bundle
    exit $?
fi

# ---------------------------------------------------------------------------
# Fetch.
# ---------------------------------------------------------------------------
need_cmd curl
need_cmd git
need_cmd sha256sum

mkdir -p "$VENDOR"

banner "staging NVIDIA ${VERSION} bundle"
log "this is the version already proven on this card (see docs/hardware.md),"
log "which is why it is pinned rather than the newer 610.x/615.x releases."

# --- 1. kernel module source ----------------------------------------------
if [ -d "${OGKM_DIR}/.git" ]; then
    log "kernel module source already present; fetching the pinned tag"
    git -C "$OGKM_DIR" fetch --depth 1 origin "refs/tags/${VERSION}:refs/tags/${VERSION}" || \
        warn "fetch failed; will verify whatever is on disk"
    # ^{} peels the annotated tag to its commit.
    git -C "$OGKM_DIR" checkout -q "refs/tags/${VERSION}^{}" 2>/dev/null || true
else
    log "cloning open-gpu-kernel-modules at tag ${VERSION}"
    git clone --depth 1 --branch "$VERSION" "$OGKM_URL" "$OGKM_DIR" || \
        die "clone failed"
fi

got_commit="$(git -C "$OGKM_DIR" rev-parse HEAD 2>/dev/null)"
if [ "$got_commit" != "$OGKM_COMMIT" ]; then
    die "commit mismatch: got ${got_commit}, expected ${OGKM_COMMIT}.

     Upstream retagged, or the clone is wrong. Investigate before building: the
     module source must match the userspace exactly."
fi
log "kernel module source pinned at ${OGKM_COMMIT:0:12}"

# --- 2. userspace installer ------------------------------------------------
if [ -f "$RUN_PATH" ] && printf '%s  %s\n' "$RUN_SHA256" "$RUN_PATH" | sha256sum -c --status 2>/dev/null; then
    log "installer already staged and verified"
else
    log "downloading ${RUN_FILE} (~420 MB)"
    curl -fL --progress-bar -o "${RUN_PATH}.part" "$RUN_URL" || die "download failed"
    mv "${RUN_PATH}.part" "$RUN_PATH"

    log "verifying against NVIDIA's published sha256"
    printf '%s  %s\n' "$RUN_SHA256" "$RUN_PATH" | sha256sum -c --status \
        || die "checksum mismatch on ${RUN_FILE}; refusing to use it"
    log "checksum OK"
fi

# --- 3. extract, never execute --------------------------------------------
if [ -d "$EXTRACT_DIR" ]; then
    log "already extracted at ${EXTRACT_DIR}"
else
    log "extracting with --extract-only (the installer is NOT run)"
    chmod +x "$RUN_PATH"
    ( cd "$VENDOR" && "./${RUN_FILE}" --extract-only ) \
        || die "extraction failed"
fi

[ -d "$EXTRACT_DIR" ] || die "expected ${EXTRACT_DIR} after extraction"

# --- 4. confirm Ada's firmware is there ------------------------------------
# Ada loads the ga10x GSP image. There is deliberately no gsp_ad10x.bin; NVIDIA
# groups Ampere and Ada onto the same GSP binary.
FW_SRC="${EXTRACT_DIR}/firmware/${NVIDIA_GSP_FIRMWARE}"
if [ ! -f "$FW_SRC" ]; then
    err "GSP firmware ${NVIDIA_GSP_FIRMWARE} not found under ${EXTRACT_DIR}/firmware/"
    log "available firmware files:"
    ls -1 "${EXTRACT_DIR}/firmware/" 2>/dev/null | sed 's/^/    /' || true
    die "Ada requires a GSP image; cannot proceed without it"
fi

printf '\n'
verify_bundle

cat <<EOF

Staged in vendor/ (gitignored):
  ${OGKM_DIR##*/}/            kernel module source, commit ${OGKM_COMMIT:0:12}
  ${EXTRACT_DIR##*/}/  userspace libraries and firmware
  ${RUN_FILE}          original installer (kept for checksum re-verification)

The board overlay ebuilds consume these directly. Next:
  ./sdk/build.sh --board nvidia-generic link
EOF
