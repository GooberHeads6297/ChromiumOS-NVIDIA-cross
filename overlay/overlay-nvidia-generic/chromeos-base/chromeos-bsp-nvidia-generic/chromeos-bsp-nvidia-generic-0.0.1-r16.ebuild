# Copyright 2026 The ChromiumOS-NVIDIA-cross Authors
# Distributed under the terms of a BSD-style licence.

EAPI=7

DESCRIPTION="Board support package for nvidia-generic"
HOMEPAGE=""

LICENSE="BSD-Google"
SLOT="0"
KEYWORDS="-* amd64"
IUSE="nvidia_open"

RDEPEND="
	nvidia_open? (
		x11-drivers/nvidia-open-drivers
		x11-libs/nvidia-userspace
		sys-firmware/nvidia-gsp-firmware
	)
	sys-firmware/amdgpu-raphael-firmware
"
DEPEND=""

S="${WORKDIR}"

src_install() {
	exeinto /usr/share/chromiumos-nvidia-cross
	doexe "${FILESDIR}/gpu-guard.sh"
	doexe "${FILESDIR}/lib-common.sh"
	doexe "${FILESDIR}/release-nvidia-drm-master.sh"

	insinto /usr/share/chromiumos-nvidia-cross
	doins "${FILESDIR}/limits.conf"

	dosbin "${FILESDIR}/install-to-disk.sh"
	newsbin "${FILESDIR}/nvidia-gbm-probe.py" nvidia-gbm-probe
	newsbin "${FILESDIR}/nvidia-drm-dump.py" nvidia-drm-dump
	newsbin "${FILESDIR}/nvidia-rtx-debug.py" nvidia-rtx-debug

	insinto /etc/init
	doins "${FILESDIR}/gpu-guard.conf"
	doins "${FILESDIR}/release-nvidia-drm-master.conf"

	insinto /lib/udev/rules.d
	doins "${FILESDIR}/99-nvidia-generic-drm-acl.rules"
	doins "${FILESDIR}/99-nvidia-generic-drm-force.rules"

	insinto /usr/lib/tmpfiles.d
	newins "${FILESDIR}/nvidia-generic-drm-acl.conf" nvidia-generic-drm-acl.conf
	doins "${FILESDIR}/zz-nvidia-generic-drm-force.conf"

	insinto /etc/modprobe.d
	doins "${FILESDIR}/zz-nvidia-generic-modeset.conf"
	doins "${FILESDIR}/zz-nvidia-generic-blacklist-simpledrm.conf"
}

pkg_postinst() {
	elog "nvidia-generic BSP: fbdev=1, simpledrm blacklisted, fbcon master released"
	elog "before ui, DRM/NVIDIA nodes forced to 0666 for bring-up."
	elog "Diagnose GBM with: nvidia-gbm-probe"
	elog "Dump connectors with: nvidia-drm-dump"
	elog "Full RTX dump: nvidia-rtx-debug"
}
