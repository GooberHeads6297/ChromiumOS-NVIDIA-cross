# Copyright 2026 The ChromiumOS-NVIDIA-cross Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

DESCRIPTION="Chrome OS BSP virtual package"
HOMEPAGE="http://src.chromium.org"

LICENSE="metapackage"
SLOT="0"
KEYWORDS="-* amd64"
IUSE=""

# This file is what actually gets our board packages into the image, and without it none of
# them are installed at all.
#
# virtual/target-chromium-os depends on virtual/chromeos-bsp, not on any board package
# directly. chromiumos-overlay provides a generic chromeos-bsp-1-r5 stub whose docstring
# says it "is expected to be overridden in an overlay for each specialized board".
# amd64-generic never overrides it, because it has no BSP package of its own -- so
# inheriting from that board leaves the stub in place.
#
# The consequence was silent and total: chromeos-base/chromeos-bsp-nvidia-generic existed in
# this overlay with nothing depending on it, so the NVIDIA driver, the NVIDIA userspace, the
# GSP firmware and the Raphael firmware would all have been built-able but absent from the
# image. Portage would not have complained, because an orphaned package is not an error.
#
# Version 2 rather than 1-rN: portage resolves by highest version across the whole masters
# chain and only uses overlay priority as a tiebreak, so this has to sit above
# chromiumos-overlay's chromeos-bsp-1-r5. overlay-reven uses chromeos-bsp-2 for the same
# reason; overlay-grunt uses chromeos-bsp-2-r1.
#
# sys-kernel/linux-firmware is carried over from the stub we are replacing. Dropping it
# would remove the firmware every other device on the board needs.
RDEPEND="
	chromeos-base/chromeos-bsp-nvidia-generic
	!chromeos-base/chromeos-bsp-null
	sys-kernel/linux-firmware
"
DEPEND=""
