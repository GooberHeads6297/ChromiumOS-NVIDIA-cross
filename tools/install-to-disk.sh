#!/bin/sh
# Install the running ChromiumOS image from the USB stick onto an internal disk.
#
# THIS RUNS ON THE DEVICE, not on the Ubuntu host. Boot the USB image first, open a
# shell, then run this. It is /bin/sh rather than bash because the ChromiumOS image
# ships dash as /bin/sh and bash is not guaranteed on a base image.
#
# It is a wrapper around /usr/sbin/chromeos-install. The wrapper exists for one reason:
# bare chromeos-install chooses a default destination disk when told nothing, and that
# default can land on the disk holding Ubuntu. This refuses to run without an explicit
# target and independently verifies that the target is not Ubuntu and not the USB we
# are currently booted from.
#
# Identification is by filesystem UUID and label, never by device name. Device names are
# not stable across operating systems: booting ChromiumOS reorders SATA discovery and the
# USB stick itself claims an sdX slot, so "nvme1n1" under Ubuntu may not be "nvme1n1"
# here.
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# On the device the safety files are installed flat beside the tools; in the repo they
# live in ../safety. Accept either.
for cand in "${SELF_DIR}/../safety" "${SELF_DIR}"; do
    if [ -r "${cand}/limits.conf" ]; then SAFETY_DIR="$cand"; break; fi
done
: "${SAFETY_DIR:?cannot locate limits.conf next to or above $0}"

log()    { printf '[install] %s\n' "$*"; }
warn()   { printf '[install] WARN: %s\n' "$*" >&2; }
err()    { printf '[install] ERROR: %s\n' "$*" >&2; }
die()    { err "$*"; exit 1; }
banner() { printf '\n=== %s ===\n' "$*"; }

# shellcheck disable=SC1090
. "${SAFETY_DIR}/limits.conf"

DST=""
ASSUME_YES=0
DRY_RUN=0

usage() {
    cat <<EOF
Usage: $0 --dst /dev/DEVICE [--dry-run] [--yes]

  --dst DEVICE   Whole-disk device to install onto, e.g. /dev/nvme1n1.
                 Required. There is deliberately no default.
  --dry-run      Run every safety check and print the command, but do not install.
  --yes          Skip the typed confirmation. Intended for a documented re-install,
                 not for the first run.

Run with --dry-run first. It is read-only and tells you whether the target you
picked is the one you think it is.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dst) DST="${2:?--dst needs a value}"; shift 2 ;;
        --dst=*) DST="${1#*=}"; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --yes) ASSUME_YES=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown argument: $1" ;;
    esac
done

[ -n "$DST" ] || { usage >&2; die "--dst is required; refusing to guess a disk to erase"; }
[ "$(id -u)" = "0" ] || die "must run as root (use sudo)"
[ -b "$DST" ] || die "not a block device: ${DST}"

DST_NAME=$(basename "$DST")

# A whole disk, not a partition. Installing to a partition would corrupt the disk's
# layout in a confusing way rather than failing cleanly.
#
# Tested via /sys/block, which contains an entry for whole disks only, plus lsblk TYPE as
# a cross-check. Note that "lsblk -no PKNAME $disk" does NOT work here: without -d it
# prints a row per descendant, so any partitioned disk has a non-empty PKNAME somewhere in
# its output and every real disk looks like a partition.
dst_type="$(lsblk -dno TYPE "$DST" 2>/dev/null | tr -d '[:space:]')"
if [ ! -d "/sys/block/${DST_NAME}" ] || [ "${dst_type:-disk}" = "part" ]; then
    die "${DST} is a partition. Pass the whole disk, e.g. /dev/nvme1n1 not /dev/nvme1n1p1"
fi
log "${DST} is a whole disk"

# Collect the target's filesystem UUIDs and labels once.
dst_uuids=$(lsblk -no UUID "$DST" 2>/dev/null | grep . || true)
dst_labels=$(lsblk -no LABEL "$DST" 2>/dev/null | grep . || true)

banner "target ${DST}"
lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINT "$DST" 2>/dev/null | sed 's/^/    /'
printf '\n'

has_uuid() {
    [ -n "$1" ] || return 1
    printf '%s\n' "$dst_uuids" | grep -qxF "$1"
}

# ---- refusal 1: the disk carrying Ubuntu ----------------------------------
# Checked by UUID so it holds regardless of what the disk is called here.
if has_uuid "${UBUNTU_ROOT_FS_UUID:-}"; then
    die "${DST} holds Ubuntu's root filesystem (${UBUNTU_ROOT_FS_UUID}). Never a target."
fi
if has_uuid "${UBUNTU_ESP_FS_UUID:-}"; then
    die "${DST} holds Ubuntu's EFI system partition (${UBUNTU_ESP_FS_UUID}). Never a target."
fi
log "does not contain Ubuntu's root or EFI partition"

# ---- refusal 2: the disk we are currently running from --------------------
# Overwriting the live USB mid-install would leave both the stick and the target broken.
root_src=$(findmnt -no SOURCE / 2>/dev/null || true)
if [ -n "$root_src" ]; then
    root_disk=$(lsblk -no PKNAME "$root_src" 2>/dev/null | head -1 || true)
    [ -n "$root_disk" ] || root_disk=$(basename "$root_src")
    if [ "$root_disk" = "$DST_NAME" ]; then
        die "${DST} is the disk this system is running from. Refusing to overwrite it."
    fi
    log "not the disk we booted from (running from ${root_disk})"
fi

# ---- refusal 3: removable media ------------------------------------------
# The point of this step is to escape the USB stick. Installing onto another removable
# device is almost certainly a mistyped target.
if [ "$(cat "/sys/block/${DST_NAME}/removable" 2>/dev/null || echo 0)" = "1" ]; then
    die "${DST} reports removable=1. The goal here is to install to an internal disk."
fi
log "${DST} is a fixed disk"

# ---- refusal 4: name-based allowlist, advisory only ----------------------
# Kept as a cross-check, but only a warning: the allowlist was written from Ubuntu's
# view of device names, which is not authoritative here.
allowed=0
for d in ${ALLOWED_TARGET_DISKS:-}; do
    [ "$d" = "$DST_NAME" ] && allowed=1
done
if [ "$allowed" = "1" ]; then
    log "${DST_NAME} is in ALLOWED_TARGET_DISKS"
else
    warn "${DST_NAME} is not in ALLOWED_TARGET_DISKS (\"${ALLOWED_TARGET_DISKS:-}\")."
    warn "That list was written from Ubuntu's device names, which can differ here."
    warn "The UUID checks above are the ones that actually matter. Read the layout."
fi

# ---- is this the disk we intended? ---------------------------------------
# A positive confirmation, distinct from the refusals above: does the target look like
# the disk the project designated for the OS?
if has_uuid "${INSTALL_TARGET_FS_UUID:-}"; then
    log "confirmed: carries ${INSTALL_TARGET_FS_LABEL:-target} (${INSTALL_TARGET_FS_UUID}), the designated install disk"
elif has_uuid "${STEAM_LIBRARY_FS_UUID:-}"; then
    warn "this is the disk reserved as the Steam games library (${STEAM_LIBRARY_FS_LABEL:-})."
    warn "Installing here is allowed but is not the documented plan; ${INSTALL_TARGET_DISK:-nvme1n1} is."
else
    warn "carries neither the designated install disk nor the games library UUID."
    warn "Either the disk was reformatted since limits.conf was written, or this is"
    warn "not the disk you meant. Check the layout printed above before continuing."
fi

INSTALLER=/usr/sbin/chromeos-install

# A dry run is strictly read-only and exits here: no unmounting, and a missing installer
# is only a warning. That is what makes it safe to run anywhere, including from the Ubuntu
# host just to confirm the UUID checks resolve to the disks you expect.
if [ "$DRY_RUN" = "1" ]; then
    banner "dry run"
    [ -x "$INSTALLER" ] || warn "${INSTALLER} not present -- expected if this is not the booted ChromiumOS image"
    for mp in $(lsblk -no MOUNTPOINT "$DST" 2>/dev/null | grep . || true); do
        log "would unmount ${mp}"
    done
    log "all safety checks passed; nothing was written"
    log "WOULD RUN: ${INSTALLER} --dst ${DST} --yes"
    exit 0
fi

[ -x "$INSTALLER" ] || die "${INSTALLER} not found. Are you running this on the booted ChromiumOS image?"

# ---- unmount anything on the target --------------------------------------
for mp in $(lsblk -no MOUNTPOINT "$DST" 2>/dev/null | grep . || true); do
    log "unmounting ${mp}"
    umount "$mp" 2>/dev/null || warn "could not unmount ${mp}; chromeos-install may fail"
done

# ---- typed confirmation --------------------------------------------------
banner "point of no return"
cat >&2 <<EOF
About to install ChromiumOS to ${DST}.

The ENTIRE disk is repartitioned. Every existing partition on it is destroyed,
including ${dst_labels:-its current filesystems}. This is not recoverable.

Ubuntu on its own disk is not touched by this operation.
EOF

if [ "$ASSUME_YES" = "0" ]; then
    printf '\nType exactly "erase %s" to proceed: ' "$DST_NAME" >&2
    read -r reply
    [ "$reply" = "erase ${DST_NAME}" ] || die "confirmation did not match; nothing was written"
fi

banner "installing"
log "running ${INSTALLER} --dst ${DST}"
"$INSTALLER" --dst "$DST" --yes

banner "done"
cat <<EOF
ChromiumOS is installed on ${DST}.

Next:
  1. poweroff
  2. Remove the USB stick.
  3. Boot, and in the UEFI menu select the ${DST_NAME} entry.
  4. Re-run the Stage 2 and Stage 3 gates on the installed system:
       tools/verify-stage2.sh
       tools/verify-stage3.sh
     They must pass here too. Passing from USB does not carry over: the installed
     system has its own kernel, module set and stateful partition.
  5. Only once both gates pass on this installed system, continue to Steam.
EOF
