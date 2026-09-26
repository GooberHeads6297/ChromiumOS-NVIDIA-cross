# Copyright 2026 The ChromiumOS-NVIDIA-cross Authors
# Distributed under the terms of a BSD-style licence.

EAPI=7

DESCRIPTION="Board support package for nvidia-generic"
HOMEPAGE=""

LICENSE="BSD-Google"
SLOT="0"
KEYWORDS="-* amd64"
IUSE="nvidia_open"

# The BSP is what pulls the NVIDIA stack into the image. Gating on the nvidia_open USE
# flag means an otherwise identical image can be built without the driver, which is
# useful for isolating whether a problem is ours or ChromeOS's.
RDEPEND="
	nvidia_open? (
		x11-drivers/nvidia-open-drivers
		x11-libs/nvidia-userspace
		sys-firmware/nvidia-gsp-firmware
	)
"
DEPEND=""

S="${WORKDIR}"

src_install() {
	# The thermal watchdog runs on the device, not just on the build host. A guard that
	# only exists in the checkout protects nothing during an actual gaming session.
	exeinto /usr/share/chromiumos-nvidia-cross
	doexe "${FILESDIR}/gpu-guard.sh"
	doexe "${FILESDIR}/lib-common.sh"

	insinto /usr/share/chromiumos-nvidia-cross
	doins "${FILESDIR}/limits.conf"

	# Upstart is ChromeOS's init system.
	insinto /etc/init
	doins "${FILESDIR}/gpu-guard.conf"
}

pkg_postinst() {
	elog "nvidia-generic BSP installed."
	elog ""
	if use nvidia_open; then
		elog "NVIDIA stack included. Modesetting is off by default (Stage 2)."
	else
		elog "Built WITHOUT the NVIDIA stack (nvidia_open USE flag disabled)."
	fi
	elog ""
	elog "The GPU thermal watchdog starts automatically once /dev/nvidia0 exists."
	elog "Check it with:  status gpu-guard  /  tail -f /var/log/gpu-guard.log"
}
