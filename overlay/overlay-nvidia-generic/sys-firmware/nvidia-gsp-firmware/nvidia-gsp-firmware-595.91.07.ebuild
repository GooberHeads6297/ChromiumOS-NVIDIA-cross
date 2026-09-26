# Copyright 2026 The ChromiumOS-NVIDIA-cross Authors
# Distributed under the terms of the NVIDIA Software License.

EAPI=7

DESCRIPTION="NVIDIA GSP firmware for Ada (AD103) on the nvidia-generic board"
HOMEPAGE="https://www.nvidia.com/"

NVIDIA_VENDOR_DIR="${NVIDIA_VENDOR_DIR:-/mnt/host/source/src/platform/chromiumos-nvidia-cross/vendor}"
NV_DIST="${NVIDIA_VENDOR_DIR}/NVIDIA-Linux-x86_64-${PV}"

LICENSE="NVIDIA-r2"
SLOT="0"
KEYWORDS="-* amd64"
IUSE=""

S="${WORKDIR}"

# Ada Lovelace loads the ga10x GSP image. There is deliberately no gsp_ad10x.bin:
# NVIDIA ships one GSP binary covering Ampere and Ada. Confirmed in the 595.91.07
# bundle, which contains exactly gsp_ga10x.bin and gsp_tu10x.bin.
GSP_FIRMWARE="gsp_ga10x.bin"

src_unpack() {
	local fw="${NV_DIST}/firmware/${GSP_FIRMWARE}"
	if [[ ! -f ${fw} ]]; then
		die "GSP firmware not staged at ${fw}.
		Run tools/fetch-nvidia.sh first. Ada cannot initialise without this blob:
		the driver loads the GSP image at probe time and fails if it is absent."
	fi
	mkdir -p "${S}/firmware" || die
	cp "${fw}" "${S}/firmware/" || die
}

src_install() {
	# The driver looks for firmware under a version-specific directory, matching the
	# layout on the Ubuntu host: /lib/firmware/nvidia/595.91.07/gsp_ga10x.bin
	insinto "/lib/firmware/nvidia/${PV}"
	doins "${S}/firmware/${GSP_FIRMWARE}"

	# Only the Ada image is installed. gsp_tu10x.bin covers Turing and would add 30 MB
	# of firmware this board can never use; the ChromeOS rootfs partition is
	# size-constrained enough that 72 MB is already worth being deliberate about.
}

pkg_postinst() {
	elog "Installed ${GSP_FIRMWARE} to /lib/firmware/nvidia/${PV}/"
	elog ""
	elog "This blob must match the kernel module version exactly (${PV}). A mismatch"
	elog "makes the module refuse to load, which is a harmless failure -- the GPU is"
	elog "never at risk from it -- but the dmesg message is not obvious about the cause."
}
