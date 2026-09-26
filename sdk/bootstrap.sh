#!/bin/bash
# sdk/bootstrap.sh -- prepare this host to build ChromiumOS, then sync the source.
#
# Handles the specific things that are wrong with *this* machine for a ChromiumOS
# build, all of which were verified rather than assumed (see docs/hardware.md):
#
#   - kernel.apparmor_restrict_unprivileged_userns is 1, which breaks cros_sdk with
#     "Permission denied: '/proc/self/setgroups'". Must be 0.
#   - Ubuntu 26.04 is newer than the documented SDK hosts (22.04 Jammy / Debian
#     Trixie), and python3 is 3.14. If the SDK rejects the host, --container sets up
#     a 24.04 LXD container instead (this user is already in the lxd group).
#   - depot_tools and repo are not installed.
#
# It does NOT need to create a user: the interactive account (uid 1000) is already
# non-root and in the sudo group, which is exactly what cros_sdk wants.
#
# Usage:
#   ./sdk/bootstrap.sh --check        # read-only: report what needs doing, change nothing
#   ./sdk/bootstrap.sh                # prepare host, install depot_tools, init + sync
#   ./sdk/bootstrap.sh --no-sync      # prepare host and init, skip the long repo sync
#   ./sdk/bootstrap.sh --container    # print the LXD 24.04 fallback recipe
#
# Environment:
#   CROS_CHECKOUT   checkout location (default ~/chromiumos)
#   CROS_BRANCH     manifest branch (default stable)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "${REPO_ROOT}/safety/lib-common.sh"

CROS_CHECKOUT="${CROS_CHECKOUT:-${HOME}/chromiumos}"
CROS_BRANCH="${CROS_BRANCH:-stable}"
DEPOT_TOOLS_DIR="${DEPOT_TOOLS_DIR:-${HOME}/depot_tools}"
MANIFEST_URL="https://chromium.googlesource.com/chromiumos/manifest"
SYSCTL_FILE="/etc/sysctl.d/99-chromiumos-sdk.conf"

MODE=apply
DO_SYNC=1

while [ $# -gt 0 ]; do
    case "$1" in
        --check)     MODE=check ;;
        --no-sync)   DO_SYNC=0 ;;
        --container) MODE=container ;;
        -h|--help)   sed -n '1,30p' "$0"; exit 0 ;;
        *)           die "unknown argument: $1" ;;
    esac
    shift
done

ISSUES=0
pass() { printf '  [ OK ]  %s\n' "$*"; }
need() { printf '  [TODO]  %s\n' "$*"; ISSUES=$(( ISSUES + 1 )); }
soft() { printf '  [WARN]  %s\n' "$*"; }

# ---------------------------------------------------------------------------
# The LXD fallback. Printed rather than executed, because whether it is needed only
# becomes clear when cros_sdk first runs, and because it wants an interactive shell.
# ---------------------------------------------------------------------------
if [ "$MODE" = container ]; then
    cat <<'EOF'
Ubuntu 24.04 SDK container fallback
===================================

Use this if cros_sdk rejects Ubuntu 26.04 or trips over python 3.14. This account is
already in the lxd group, so no extra setup is needed.

  lxc launch ubuntu:24.04 crosbuild \
      -c security.privileged=true \
      -c security.nesting=true

  # The build needs a lot of room; bind-mount a host directory rather than growing
  # the container's own disk.
  mkdir -p ~/chromiumos
  lxc config device add crosbuild src disk source=$HOME/chromiumos path=/home/ubuntu/chromiumos

  lxc exec crosbuild -- bash -lc '
      apt-get update
      apt-get install -y git gitk git-gui curl util-linux util-linux-extra \
                         python3 python3-venv sudo locales
      sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 || true
  '

  lxc exec crosbuild -- su - ubuntu

Then run this same bootstrap script inside the container.

Note: security.privileged and security.nesting are required because cros_sdk needs
user namespaces and mount operations.
EOF
    exit 0
fi

banner "ChromiumOS SDK bootstrap (${MODE})"

# ---------------------------------------------------------------------------
printf '\nUser and permissions\n'
# ---------------------------------------------------------------------------
if is_root; then
    die "do not run this as root.

     cros_sdk refuses to run as root and will sudo for itself when it needs to.
     Run as your normal user (uid 1000 here)."
fi
pass "running as non-root user $(id -un) (uid $(id -u))"

if id -nG | tr ' ' '\n' | grep -qx sudo; then
    pass "user is in the sudo group"
else
    need "user must be in the sudo group: sudo usermod -aG sudo $(id -un)"
fi

# ChromiumOS requires sources be world-readable inside the chroot, so the last digit
# of umask must not exceed 2. This host is 0002, which is fine, but it is not pinned
# in ~/.bashrc, so a future change would silently break the build.
cur_umask="$(umask)"
if [ "${cur_umask: -1}" -le 2 ]; then
    pass "umask ${cur_umask} is acceptable (last digit <= 2)"
else
    need "umask ${cur_umask} is too restrictive; sources must be world-readable in the chroot"
fi
if grep -qs '^umask 022' "${HOME}/.bashrc"; then
    pass "umask pinned in ~/.bashrc"
else
    need "pin umask in ~/.bashrc so it cannot drift"
fi

# ---------------------------------------------------------------------------
printf '\nKernel configuration\n'
# ---------------------------------------------------------------------------
userns_restrict="$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || echo unset)"
if [ "$userns_restrict" = "0" ] || [ "$userns_restrict" = "unset" ]; then
    pass "unprivileged user namespaces available (apparmor_restrict_unprivileged_userns=${userns_restrict})"
else
    need "kernel.apparmor_restrict_unprivileged_userns=${userns_restrict} breaks cros_sdk; must be 0"
fi

# ---------------------------------------------------------------------------
printf '\nFilesystem and space\n'
# ---------------------------------------------------------------------------
parent="$(dirname "$CROS_CHECKOUT")"
fstype="$(findmnt -no FSTYPE --target "$parent" 2>/dev/null || echo unknown)"
case "$fstype" in
    ext4|ext3|ext2) pass "checkout parent ${parent} is ${fstype} (supported)" ;;
    btrfs)          soft "checkout parent is btrfs: supported only without compression, which introduces xattrs and breaks squashfs/erofs steps" ;;
    nfs)            need "checkout parent is nfs, which the build system cannot use" ;;
    *)              soft "checkout parent filesystem is '${fstype}'; ext4 is the known-good choice" ;;
esac

avail="$(df -BG --output=avail "$parent" 2>/dev/null | tail -1 | tr -dc '0-9')"
if [ -n "$avail" ] && [ "$avail" -ge 200 ]; then
    pass "${avail} GB free at ${parent} (need 150-300 GB)"
else
    soft "only ${avail:-?} GB free at ${parent}; a checkout plus board build wants 150-300 GB"
fi

mem_gb="$(awk '/MemTotal/ {printf "%d", $2/1048576}' /proc/meminfo 2>/dev/null || echo 0)"
if [ "$mem_gb" -ge 28 ]; then
    pass "${mem_gb} GB RAM"
else
    soft "${mem_gb} GB RAM; linking Chrome wants 8-28 GB. Prefer prebuilt binary packages."
fi

# ---------------------------------------------------------------------------
printf '\nTooling\n'
# ---------------------------------------------------------------------------
for t in git curl python3; do
    if command -v "$t" >/dev/null 2>&1; then
        pass "${t} present ($("$t" --version 2>&1 | head -1))"
    else
        need "install ${t}"
    fi
done

if [ -x "${DEPOT_TOOLS_DIR}/repo" ]; then
    pass "depot_tools present at ${DEPOT_TOOLS_DIR}"
else
    need "clone depot_tools to ${DEPOT_TOOLS_DIR}"
fi

if [ -d "${CROS_CHECKOUT}/.repo" ]; then
    pass "checkout already initialised at ${CROS_CHECKOUT}"
else
    need "repo init ${CROS_CHECKOUT} (branch ${CROS_BRANCH})"
fi

# ---------------------------------------------------------------------------
if [ "$MODE" = check ]; then
    printf '\n'
    if [ "$ISSUES" -eq 0 ]; then
        banner "host is ready (${ISSUES} outstanding)"
    else
        banner "${ISSUES} item(s) need doing -- rerun without --check to apply"
    fi
    exit 0
fi

# ===========================================================================
# Apply phase.
# ===========================================================================
banner "applying host changes"

log "installing host packages (sudo will prompt)"
sudo add-apt-repository -y universe
sudo apt-get update
sudo apt-get install -y \
    git gitk git-gui curl \
    util-linux util-linux-extra \
    python3 python3-venv \
    locales lvm2 thin-provisioning-tools \
    xz-utils zstd cgpt

# Persist the userns sysctls. cros_sdk needs unprivileged user namespaces; without
# this it fails partway through chroot setup with a confusing setgroups error.
log "persisting user-namespace sysctls to ${SYSCTL_FILE}"
sudo tee "$SYSCTL_FILE" >/dev/null <<'EOF'
# Required by the ChromiumOS SDK (cros_sdk): it needs unprivileged user namespaces.
# Ubuntu 24.04+ restricts these by default, which surfaces as
#   Permission denied: '/proc/self/setgroups'
kernel.apparmor_restrict_unprivileged_userns = 0
kernel.apparmor_restrict_unprivileged_unconfined = 0
EOF
sudo sysctl -p "$SYSCTL_FILE"

if ! grep -qs '^umask 022' "${HOME}/.bashrc"; then
    log "pinning umask 022 in ~/.bashrc"
    {
        echo ''
        echo '# ChromiumOS build: sources must be world-readable inside the chroot.'
        echo 'umask 022'
    } >> "${HOME}/.bashrc"
fi

if [ ! -x "${DEPOT_TOOLS_DIR}/repo" ]; then
    log "cloning depot_tools to ${DEPOT_TOOLS_DIR}"
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT_TOOLS_DIR"
else
    log "updating depot_tools"
    git -C "$DEPOT_TOOLS_DIR" pull --ff-only || soft "depot_tools update failed; continuing with the existing copy"
fi

if ! grep -qs 'depot_tools' "${HOME}/.bashrc"; then
    log "adding depot_tools to PATH in ~/.bashrc"
    {
        echo ''
        echo '# ChromiumOS / depot_tools'
        echo "export PATH=\"\${PATH}:${DEPOT_TOOLS_DIR}\""
    } >> "${HOME}/.bashrc"
fi
export PATH="${PATH}:${DEPOT_TOOLS_DIR}"

mkdir -p "$CROS_CHECKOUT"
cd "$CROS_CHECKOUT"

if [ ! -d .repo ]; then
    banner "repo init (branch ${CROS_BRANCH})"
    # -b stable pins to a revision verified by upstream CI, 4-10 hours behind ToT.
    # Much better than main for a project that wants a reproducible baseline.
    "${DEPOT_TOOLS_DIR}/repo" init -u "$MANIFEST_URL" -b "$CROS_BRANCH"
else
    log "checkout already initialised; leaving the manifest alone"
fi

if [ "$DO_SYNC" -eq 1 ]; then
    banner "repo sync (this takes a long time and a lot of disk)"
    "${DEPOT_TOOLS_DIR}/repo" sync -j4
else
    log "skipping repo sync (--no-sync)"
fi

banner "bootstrap complete"
cat <<EOF
Checkout:  ${CROS_CHECKOUT}
Branch:    ${CROS_BRANCH}

Open a new shell (or 'source ~/.bashrc') so PATH and umask apply, then:

  ./sdk/build.sh --board amd64-generic

If cros_sdk fails on this Ubuntu 26.04 host, fall back to a container:

  ./sdk/bootstrap.sh --container
EOF
