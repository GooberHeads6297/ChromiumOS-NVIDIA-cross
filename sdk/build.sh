#!/bin/bash
# sdk/build.sh -- wire this repo into a ChromiumOS checkout and build an image.
#
# All cros commands run OUTSIDE the chroot; the cros CLI enters it as needed.
#
# Stages:
#   link      symlink our board overlay into src/overlays and install patches
#   setup     set up the board sysroot
#   packages  cros build-packages
#   image     cros build-image
#   all       everything above, in order
#
# Usage:
#   ./sdk/build.sh --check                          # report state, change nothing
#   ./sdk/build.sh --board amd64-generic all        # Stage 1 baseline (no NVIDIA)
#   ./sdk/build.sh --board nvidia-generic all       # Stage 2+ (with NVIDIA)
#   ./sdk/build.sh --board nvidia-generic link      # just re-sync overlay + patches
#
# Environment:
#   CROS_CHECKOUT   checkout location (default ~/chromiumos)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "${REPO_ROOT}/safety/lib-common.sh"

CROS_CHECKOUT="${CROS_CHECKOUT:-${HOME}/chromiumos}"
DEPOT_TOOLS_DIR="${DEPOT_TOOLS_DIR:-${HOME}/depot_tools}"

BOARD=nvidia-generic
IMAGE_TYPE=test
STAGE=""
CHECK=0

while [ $# -gt 0 ]; do
    case "$1" in
        --board)      BOARD="${2:?--board needs a value}"; shift ;;
        --image-type) IMAGE_TYPE="${2:?--image-type needs a value}"; shift ;;
        --check)      CHECK=1 ;;
        link|setup|packages|image|all) STAGE="$1" ;;
        -h|--help)    sed -n '1,22p' "$0"; exit 0 ;;
        *)            die "unknown argument: $1" ;;
    esac
    shift
done

is_root && die "do not run as root; cros_sdk sudoes for itself when needed"

export PATH="${PATH}:${DEPOT_TOOLS_DIR}"

OVERLAY_SRC="${REPO_ROOT}/overlay/overlay-${BOARD}"
OVERLAY_DST="${CROS_CHECKOUT}/src/overlays/overlay-${BOARD}"

# ---------------------------------------------------------------------------
check_state() {
    banner "build environment (${BOARD})"
    printf '\n'
    if [ -d "${CROS_CHECKOUT}/.repo" ]; then
        printf '  [ OK ]  checkout at %s\n' "$CROS_CHECKOUT"
    else
        printf '  [FAIL]  no checkout at %s -- run ./sdk/bootstrap.sh first\n' "$CROS_CHECKOUT"
    fi
    if command -v cros >/dev/null 2>&1 || [ -x "${CROS_CHECKOUT}/chromite/bin/cros" ]; then
        printf '  [ OK ]  cros CLI available\n'
    else
        printf '  [FAIL]  cros CLI not found (expected in chromite/bin after repo sync)\n'
    fi
    if [ "$BOARD" = "nvidia-generic" ]; then
        if [ -d "$OVERLAY_SRC" ]; then
            printf '  [ OK ]  board overlay source at %s\n' "$OVERLAY_SRC"
        else
            printf '  [FAIL]  missing board overlay %s\n' "$OVERLAY_SRC"
        fi
    fi
    if [ -L "$OVERLAY_DST" ] || [ -d "$OVERLAY_DST" ]; then
        printf '  [ OK ]  overlay linked into checkout\n'
    else
        printf '  [TODO]  overlay not linked yet (run: %s link)\n' "$0"
    fi
    printf '\n'
}

if [ "$CHECK" -eq 1 ]; then
    check_state
    exit 0
fi

[ -n "$STAGE" ] || die "no stage given. One of: link setup packages image all (or --check)"
[ -d "${CROS_CHECKOUT}/.repo" ] || die "no ChromiumOS checkout at ${CROS_CHECKOUT}; run ./sdk/bootstrap.sh"

cros_cmd() {
    if command -v cros >/dev/null 2>&1; then
        ( cd "$CROS_CHECKOUT" && cros "$@" )
    else
        ( cd "$CROS_CHECKOUT" && ./chromite/bin/cros "$@" )
    fi
}

# ---------------------------------------------------------------------------
# link: put our overlay and patches where portage will find them.
#
# A symlink keeps this repo the single source of truth: edits here take effect in
# the checkout without copying, and the checkout stays disposable.
# ---------------------------------------------------------------------------
stage_link() {
    banner "link: installing overlay and patches"

    if [ "$BOARD" != "amd64-generic" ]; then
        [ -d "$OVERLAY_SRC" ] || die "no overlay at ${OVERLAY_SRC}"
        mkdir -p "${CROS_CHECKOUT}/src/overlays"
        if [ -L "$OVERLAY_DST" ]; then
            log "overlay symlink already present; refreshing"
            rm -f "$OVERLAY_DST"
        elif [ -d "$OVERLAY_DST" ]; then
            die "${OVERLAY_DST} exists as a real directory; move it aside first"
        fi
        ln -s "$OVERLAY_SRC" "$OVERLAY_DST"
        log "linked ${OVERLAY_DST} -> ${OVERLAY_SRC}"
    else
        log "board is amd64-generic (stock); no overlay to link"
    fi

    # minigbm is a cros workon package, so its patch is applied to the checked-out
    # source tree rather than dropped into an ebuild files/ directory.
    local mg_src="${CROS_CHECKOUT}/src/platform/minigbm"
    local mg_patch="${REPO_ROOT}/patches/minigbm/0001-add-nvidia-drm-dumb-backend.patch"
    if [ "$BOARD" != "amd64-generic" ] && [ -d "$mg_src" ] && [ -f "$mg_patch" ]; then
        if git -C "$mg_src" apply --check "$mg_patch" 2>/dev/null; then
            log "applying minigbm nvidia-drm backend patch"
            git -C "$mg_src" apply "$mg_patch"
        elif git -C "$mg_src" apply --reverse --check "$mg_patch" 2>/dev/null; then
            log "minigbm patch already applied"
        else
            warn "minigbm patch does not apply cleanly against ${mg_src}."
            warn "Upstream has probably moved. Rebase patches/minigbm/ before continuing."
        fi
    elif [ "$BOARD" != "amd64-generic" ]; then
        warn "minigbm source not found at ${mg_src}; skipping patch (run repo sync?)"
    fi
}

stage_setup() {
    banner "setup: board sysroot for ${BOARD}"
    # setup-board is idempotent; --force would discard the sysroot, so it is not used.
    cros_cmd setup-board --board="$BOARD" || \
        die "setup-board failed.

     On Ubuntu 26.04 this is the most likely point for a host incompatibility.
     If the error mentions user namespaces, setgroups, or python, use the container
     fallback:  ./sdk/bootstrap.sh --container"
}

stage_packages() {
    banner "packages: cros build-packages --board=${BOARD}"
    log "first run takes roughly 90+ minutes and downloads several GB"
    # --autosetgov temporarily switches to the performance governor; --sticky makes
    # that the default for later runs.
    cros_cmd build-packages --board="$BOARD" --autosetgov --autosetgov-sticky
}

stage_image() {
    banner "image: cros build-image --board=${BOARD} (${IMAGE_TYPE})"
    # --no-enable-rootfs-verification is required: we need a writable rootfs to load
    # an out-of-tree kernel module and to iterate on the graphics stack.
    # A test image also accepts SSH (password test0000), which is how we retrieve logs
    # when the display path is broken.
    cros_cmd build-image --board="$BOARD" --no-enable-rootfs-verification "$IMAGE_TYPE"

    local latest="${CROS_CHECKOUT}/src/build/images/${BOARD}/latest"
    if [ -d "$latest" ]; then
        banner "image built"
        log "location: ${latest}"
        ls -1 "$latest" 2>/dev/null | sed 's/^/  /'
        cat <<EOF

Next steps:

  Try it in a VM first (costs nothing, catches obvious breakage):
    cros vm --start --image-path=${latest}/chromiumos_test_image.bin --board=${BOARD}

  Then bare metal, through the safety gate:
    sudo ./safety/preflight.sh nvme1n1
    sudo ./tools/flash.sh --board ${BOARD} --target nvme1n1

Remember each build consumes up to 8 GB. Delete old ones under
${CROS_CHECKOUT}/src/build/images/${BOARD}/.
EOF
    fi
}

case "$STAGE" in
    link)     stage_link ;;
    setup)    stage_setup ;;
    packages) stage_packages ;;
    image)    stage_image ;;
    all)      stage_link; stage_setup; stage_packages; stage_image ;;
esac
