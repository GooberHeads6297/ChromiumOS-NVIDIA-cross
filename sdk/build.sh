#!/bin/bash
# sdk/build.sh -- wire this repo into a ChromiumOS checkout and build an image.
#
# All cros commands run OUTSIDE the chroot; the cros CLI enters it as needed.
#
# Stages:
#   link      symlink our board overlay into src/overlays and install patches
#   setup     set up the board sysroot (optional; build-packages does this itself)
#   packages  cros build-packages -- runs setup_board, then builds
#   image     cros build-image
#   all       link, packages, image
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
        # The stage is positional, but --stage is accepted too: it reads naturally and
        # silently failing on it is a poor trade for one case label.
        --stage)      STAGE="${2:?--stage needs a value}"; shift ;;
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
    # amd64-generic is the stock baseline board: it has no overlay by design, and
    # stage_link deliberately skips both the symlink and the minigbm patch for it.
    # Reporting a missing overlay as work to do would be wrong, not just noisy.
    if [ "$BOARD" = "amd64-generic" ]; then
        printf '  [ OK ]  stock baseline board: no overlay or minigbm patch applied\n'
    else
        if [ -d "$OVERLAY_SRC" ]; then
            printf '  [ OK ]  board overlay source at %s\n' "$OVERLAY_SRC"
        else
            printf '  [FAIL]  missing board overlay %s\n' "$OVERLAY_SRC"
        fi
        if [ -L "$OVERLAY_DST" ] || [ -d "$OVERLAY_DST" ]; then
            printf '  [ OK ]  overlay linked into checkout\n'
        else
            printf '  [TODO]  overlay not linked yet (run: %s --board %s link)\n' "$0" "$BOARD"
        fi
    fi
    printf '\n'
}

if [ "$CHECK" -eq 1 ]; then
    check_state
    exit 0
fi

case "${STAGE:-}" in
    ""|link|setup|packages|image|all) ;;
    *) die "unknown stage '${STAGE}'. One of: link setup packages image all" ;;
esac
[ -n "$STAGE" ] || die "no stage given. One of: link setup packages image all (or --check)"
[ -d "${CROS_CHECKOUT}/.repo" ] || die "no ChromiumOS checkout at ${CROS_CHECKOUT}; run ./sdk/bootstrap.sh"

# Path the checkout is mounted at inside the chroot (constants.CHROOT_SOURCE_ROOT).
CHROOT_SOURCE_ROOT=/mnt/host/source

cros_cmd() {
    if command -v cros >/dev/null 2>&1; then
        ( cd "$CROS_CHECKOUT" && cros "$@" )
    else
        ( cd "$CROS_CHECKOUT" && ./chromite/bin/cros "$@" )
    fi
}

# Run a command inside the SDK chroot. Needed for the few entrypoints that refuse to run
# outside it; the cros subcommands enter the chroot on their own.
cros_sdk_cmd() {
    ( cd "$CROS_CHECKOUT" && ./chromite/bin/cros_sdk -- "$@" )
}

# Get a sudo credential before starting anything long.
#
# Every cros command here sudoes to enter its container. Without this, the password prompt
# appears whenever sudo's timeout happens to lapse -- which for build-packages can be hours
# in, on a step that then sits waiting for input it may never get. Priming up front makes the
# prompt happen at a predictable moment, with context.
#
# Only refuse when there is genuinely no way to ask: no cached credential AND no terminal on
# stdin. Given a terminal, sudo can prompt, so asking beats failing and telling the user to
# run `sudo -v` themselves.
ensure_sudo() {
    sudo -n true 2>/dev/null && return 0

    if [ -t 0 ]; then
        log "cros_sdk needs sudo; authenticating now so it does not prompt later"
        sudo -v || die "sudo authentication failed or was cancelled."
        return 0
    fi

    die "sudo needs a password and stdin is not a terminal, so it cannot ask.

     cros_sdk sudoes for itself to enter its container. Run this from an interactive
     shell, or prime the credential first with:  sudo -v"
}

# ---------------------------------------------------------------------------
# link: put our overlay and patches where portage will find them.
#
# A symlink keeps this repo the single source of truth: edits here take effect in
# the checkout without copying, and the checkout stays disposable.
# Copy this project into the chromiumos checkout.
#
# WHY A COPY AND NOT A SYMLINK. This used to symlink
#   ~/chromiumos/src/overlays/overlay-nvidia-generic -> <this repo>/overlay/overlay-nvidia-generic
# which resolves fine on the host and is *dangling inside the chroot*. cros_sdk mounts only
# the checkout (as /mnt/host/source), plus out and depot_tools -- this repo lives outside all
# of them, so nothing under ~/CodeEnv exists in there.
#
# The failure was not obvious. portage_util._GetKnownOverlays() globs src/overlays/* and calls
# GetOverlayName() on each hit; for a dangling link that read fails, the overlay is skipped
# silently, and the board simply does not exist. What you see is
#   ValueError: No such board: nvidia-generic
# from build_query.Board.get, which reads like a missing profile rather than a broken mount.
#
# The same trap applied to the NVIDIA bundle. All three NVIDIA ebuilds default
# NVIDIA_VENDOR_DIR to /mnt/host/source/src/platform/chromiumos-nvidia-cross/vendor, a path
# that did not exist at all -- so those would have died partway through build-packages, hours
# in, long after the cheap gate had passed.
#
# So: put real content at both in-chroot paths and use no symlinks.
sync_project_into_checkout() {
    [ -d "$OVERLAY_SRC" ] || die "no overlay at ${OVERLAY_SRC}"

    # --- the board overlay -------------------------------------------------
    mkdir -p "${CROS_CHECKOUT}/src/overlays" || die "cannot create src/overlays"

    if [ -L "$OVERLAY_DST" ]; then
        # Left behind by an older version of this script. It is the bug described above.
        log "removing the old dangling symlink at ${OVERLAY_DST}"
        rm -f "$OVERLAY_DST" || die "could not remove ${OVERLAY_DST}"
    fi

    # --delete so a file removed here is removed there; a stale ebuild in the checkout would
    # otherwise keep being built. Excludes are editor and VCS noise only.
    #
    # -L copies symlink targets as real files. The BSP files/ directory links gpu-guard.sh,
    # lib-common.sh and limits.conf at safety/ in this repo. A preserved symlink still points
    # there after the copy, which is outside the checkout and invisible in the chroot, so
    # doexe dies with "cannot stat .../files/gpu-guard.sh".
    log "syncing overlay -> ${OVERLAY_DST}"
    rsync -aL --delete \
        --exclude '.git' --exclude '*.swp' --exclude '*~' \
        "${OVERLAY_SRC}/" "${OVERLAY_DST}/" \
        || die "rsync of the overlay into ${OVERLAY_DST} failed"

    # --- the NVIDIA vendor bundle ------------------------------------------
    # 2.2 GB, so copying it properly would be slow and waste real disk. cp -al makes a
    # hardlink farm instead: near-instant, no extra space, and the files are genuinely inside
    # the checkout so the chroot sees them. Hardlinks need one filesystem, hence the fallback.
    local vendor_src="${REPO_ROOT}/vendor"
    local platform_dst="${CROS_CHECKOUT}/src/platform/chromiumos-nvidia-cross"

    if [ -d "$vendor_src" ]; then
        mkdir -p "$platform_dst" || die "cannot create ${platform_dst}"
        if [ -e "${platform_dst}/vendor" ]; then
            rm -rf "${platform_dst}/vendor" || die "could not clear ${platform_dst}/vendor"
        fi
        if cp -al "$vendor_src" "${platform_dst}/vendor" 2>/dev/null; then
            log "hardlinked vendor/ -> ${platform_dst}/vendor"
        else
            warn "hardlinking failed (different filesystems?); copying 2.2 GB instead"
            cp -a "$vendor_src" "${platform_dst}/vendor" \
                || die "could not copy ${vendor_src} into ${platform_dst}"
            log "copied vendor/ -> ${platform_dst}/vendor"
        fi
    else
        warn "no vendor/ directory; run ./tools/fetch-nvidia.sh before building"
    fi
}

# ---------------------------------------------------------------------------
stage_link() {
    banner "link: installing overlay and patches"

    if [ "$BOARD" != "amd64-generic" ]; then
        sync_project_into_checkout
    else
        log "board is amd64-generic (stock); no overlay to install"
    fi

    # Install the board kernel flavour config into the kernel tree.
    #
    # This has to live in the kernel tree because that is the only place prepareconfig
    # looks: cros-kernel.eclass passes CHROMEOS_KERNEL_SPLITCONFIG to
    # chromeos/scripts/prepareconfig, which does
    #     find chromeos/config/${family} -name <name>.flavour.config
    # and concatenates base.config + <arch>/common.config + that file.
    #
    # Installed rather than patched because it is a new file, and a copy cannot conflict
    # with an upstream change the way a patch hunk can.
    if [ "$BOARD" != "amd64-generic" ]; then
        local fl_src="${REPO_ROOT}/overlay/overlay-${BOARD}/kernel-config"
        local kver="${KERNEL_VERSION:-v6.12}"
        local fl_dst="${CROS_CHECKOUT}/src/third_party/kernel/${kver}/chromeos/config/chromeos/x86_64"
        if [ -d "$fl_src" ] && [ -d "$fl_dst" ]; then
            for f in "${fl_src}"/*.flavour.config; do
                [ -e "$f" ] || continue
                cp -f "$f" "${fl_dst}/" || die "could not install $(basename "$f") into ${fl_dst}"
                log "installed $(basename "$f") -> ${fl_dst}/"
            done
        elif [ -d "$fl_src" ]; then
            die "kernel config dir not found: ${fl_dst}
     The board selects kernel ${kver}. If that is wrong, set KERNEL_VERSION.
     Without this the board would silently fall back to a config with no amdgpu,
     and the iGPU recovery console would not exist."
        fi
    fi

    # minigbm's nvidia-drm backend is owned by the overlay ebuild
    # media-libs/minigbm-0.0.1-r810, not by a git-apply here: a non-cros_workon
    # emerge builds CROS_WORKON_TREE and silently ignores a dirty
    # src/platform/minigbm, which is how stock minigbm reached a flashed image.
    local mg_patch="${REPO_ROOT}/patches/minigbm/0001-add-nvidia-drm-dumb-backend.patch"
    local mg_ebuild_patch="${REPO_ROOT}/overlay/overlay-nvidia-generic/media-libs/minigbm/files/0001-add-nvidia-drm-dumb-backend.patch"
    if [ "$BOARD" != "amd64-generic" ]; then
        if [ ! -f "$mg_ebuild_patch" ]; then
            warn "overlay minigbm patch missing: ${mg_ebuild_patch}"
        elif ! cmp -s "$mg_patch" "$mg_ebuild_patch"; then
            warn "patches/minigbm/ and the overlay copy differ; the ebuild one is what builds."
        else
            log "minigbm nvidia-drm backend ships via media-libs/minigbm-0.0.1-r810"
        fi
    fi

    # login_manager: de-Google first boot + always honour chrome_dev.conf.
    # Applied to platform2 like minigbm so emerge chromeos-login picks it up.
    # Do not pass --load-extension at login (OOBE crash / powerwash).
    local lm_src="${CROS_CHECKOUT}/src/platform2"
    local lm_patch="${REPO_ROOT}/patches/login_manager/nvidia-generic-local-accounts.patch"
    if [ "$BOARD" != "amd64-generic" ] && [ -d "${lm_src}/login_manager" ] && [ -f "$lm_patch" ]; then
        if git -C "$lm_src" apply --check "$lm_patch" 2>/dev/null; then
            log "applying login_manager local-account patch"
            git -C "$lm_src" apply "$lm_patch"
        elif git -C "$lm_src" apply --reverse --check "$lm_patch" 2>/dev/null; then
            log "login_manager local-account patch already applied"
        else
            warn "login_manager patch does not apply cleanly against ${lm_src}/login_manager."
            warn "Upstream has probably moved. Rebase patches/login_manager/ before continuing."
        fi
    elif [ "$BOARD" != "amd64-generic" ]; then
        warn "platform2/login_manager not found; skipping local-account patch"
    fi

    # chromeos-chrome: prefer a *connected* nvidia-drm card over amdgpu CRTCs.
    # Requires emerge chromeos-base/chromeos-chrome (tools/rebuild-display-image.sh).
    local ch_src=""
    local cand
    for cand in "${CROS_CHECKOUT}/chrome_root/src" \
                "${CROS_CHECKOUT}/src/aosp/external/chromium/src"; do
        if [ -f "${cand}/ui/ozone/platform/drm/common/drm_util.cc" ]; then
            ch_src="$cand"
            break
        fi
    done
    if [ "$BOARD" != "amd64-generic" ] && [ -n "$ch_src" ]; then
        local ch_patch
        for ch_patch in "${REPO_ROOT}/patches/chrome/"*.patch; do
            [ -f "$ch_patch" ] || continue
            if patch -d "$ch_src" -p1 --dry-run --reverse --batch < "$ch_patch" >/dev/null 2>&1; then
                log "$(basename "$ch_patch") already applied"
            elif patch -d "$ch_src" -p1 --dry-run --forward --batch < "$ch_patch" >/dev/null 2>&1; then
                log "applying $(basename "$ch_patch")"
                patch -d "$ch_src" -p1 --forward --batch < "$ch_patch"
            elif grep -q 'forcing legacy KMS\|PickDisplayCard' \
                    "${ch_src}/ui/ozone/platform/drm/common/drm_wrapper.cc" \
                    "${ch_src}/ui/ozone/platform/drm/host/drm_display_host_manager.cc" \
                    2>/dev/null; then
                log "$(basename "$ch_patch") already in tree (fuzz)"
            else
                warn "$(basename "$ch_patch") does not apply against ${ch_src}"
                warn "Rebase patches/chrome/ and retry."
            fi
        done
    elif [ "$BOARD" != "amd64-generic" ]; then
        warn "chrome ozone drm_util.cc not found; skipping nvidia-drm patches"
    fi
}

# setup: create the board sysroot.
#
# `cros setup-board` does not exist. It is not in chromite's subcommand list and there is
# no cros_setup_board.py in chromite/cli/cros/. The surviving entrypoint is the
# setup_board script, and chromite/service/sysroot.py raises NotInChrootError unless it is
# run inside the chroot, so it has to go through cros_sdk. Referenced by absolute in-chroot
# path from constants.CHROOT_SOURCE_ROOT ("/mnt/host/source") rather than trusting PATH.
#
# This stage is optional. `cros build-packages` runs setup_board itself unless told
# --skip-setup-board, and not skipping is the default, so the `all` stage does not call
# this. It stays available for setting up a sysroot without building into it.
stage_setup() {
    banner "setup: board sysroot for ${BOARD}"
    log "note: 'all' does not run this; cros build-packages sets the board up itself"
    ensure_sudo

    # setup_board is idempotent; --force would discard the sysroot, so it is not used.
    cros_sdk_cmd "${CHROOT_SOURCE_ROOT}/chromite/bin/setup_board" --board="$BOARD" || \
        die "setup_board failed for ${BOARD}.

     Read the error above before assuming a host problem. The usual causes, in order:
       - a profile or ebuild in overlay/overlay-${BOARD}/ that does not resolve,
         which is exactly what this stage exists to catch;
       - a masked or missing dependency, reported by portage as such;
       - a host incompatibility, which would mention user namespaces, setgroups or
         python. Only in that case try:  ./sdk/bootstrap.sh --container"
}

stage_packages() {
    # The Raphael firmware is not in git (redistributable vendor blobs), so a fresh clone
    # would otherwise fail deep inside the build with an ebuild die. Check it here, where
    # the fix is one command away.
    if [ "$BOARD" != "amd64-generic" ]; then
        local rfw="${REPO_ROOT}/overlay/overlay-${BOARD}/sys-firmware/amdgpu-raphael-firmware/files"
        if [ -d "$(dirname "$rfw")" ] && [ ! -e "${rfw}/gc_10_3_6_pfp.bin" ]; then
            die "amdgpu GC 10.3.6 firmware is not staged.

     Run:  ./tools/fetch-amdgpu-firmware.sh

     Without it amdgpu cannot initialise this machine's Raphael iGPU, which is the
     recovery console the Stage 2 bring-up depends on."
        fi
    fi

    # Re-sync before building. Now that the overlay is a copy rather than a symlink, an edit
    # here does not reach the checkout on its own, so running this stage alone after editing
    # would quietly build the previous contents. The sync is idempotent and takes moments.
    if [ "$BOARD" != "amd64-generic" ]; then
        sync_project_into_checkout
    fi

    ensure_sudo

    banner "packages: cros build-packages --board=${BOARD}"
    log "this also runs setup_board for ${BOARD} (build-packages does it unless"
    log "--skip-setup-board is passed, and not skipping is the default)"
    log "first run takes roughly 90+ minutes and downloads several GB"
    # --autosetgov temporarily switches to the performance governor; --sticky makes
    # that the default for later runs.
    #
    # The || die matters because this script runs without `set -e`. Without it, a failed
    # build-packages would fall through to build-image under the `all` stage, and build-image
    # can succeed against a partially-populated sysroot -- producing an image that looks
    # finished but is missing packages. That image could then be flashed.
    cros_cmd build-packages --board="$BOARD" --autosetgov --autosetgov-sticky || \
        die "build-packages failed for ${BOARD}; not continuing to build-image.

     Nothing was built into an image, so there is no partial image to mistake for a
     good one. Fix the reported package failure and re-run this stage."
}

stage_image() {
    ensure_sudo

    banner "image: cros build-image --board=${BOARD} (${IMAGE_TYPE})"
    # --no-enable-rootfs-verification is required: we need a writable rootfs to load
    # an out-of-tree kernel module and to iterate on the graphics stack.
    # A test image also accepts SSH (password test0000), which is how we retrieve logs
    # when the display path is broken.
    cros_cmd build-image --board="$BOARD" --no-enable-rootfs-verification "$IMAGE_TYPE" || \
        die "build-image failed for ${BOARD}.

     Do not flash whatever is in src/build/images/${BOARD}/ -- if an older image is
     still there, 'latest' may well point at it and look like a fresh success."

    local latest="${CROS_CHECKOUT}/src/build/images/${BOARD}/latest"
    if [ -d "$latest" ]; then
        banner "image built"
        log "location: ${latest}"
        ls -1 "$latest" 2>/dev/null | sed 's/^/  /'
        cat <<EOF

Next steps:

  Try it in a VM first (costs nothing, catches obvious breakage):
    cros vm --start --image-path=${latest}/chromiumos_test_image.bin --board=${BOARD}

  Then the USB stick, through the safety gate. USB before any internal disk:
  a failed boot costs a reflash instead of a reinstall. See docs/INSTALL.md.
    sudo ./safety/preflight.sh sdc
    sudo ./tools/flash.sh --board ${BOARD} --target usb

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
    # No stage_setup here on purpose: build-packages sets the board up itself, so running
    # it separately would do the same work twice.
    all)      stage_link; stage_packages; stage_image ;;
esac
