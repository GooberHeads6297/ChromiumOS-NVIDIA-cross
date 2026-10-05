# Copyright 2026 The ChromiumOS-NVIDIA-cross Authors
# Distributed under the terms of the MIT/GPL dual licence used by
# NVIDIA/open-gpu-kernel-modules.

EAPI=7

DESCRIPTION="NVIDIA open GPU kernel modules for the nvidia-generic board"
HOMEPAGE="https://github.com/NVIDIA/open-gpu-kernel-modules"

# The module source is staged by tools/fetch-nvidia.sh into vendor/ rather than fetched
# by portage. That keeps the version pin, its published checksum and its peeled tag
# commit in one auditable place, and keeps this ebuild offline.
NVIDIA_VENDOR_DIR="${NVIDIA_VENDOR_DIR:-/mnt/host/source/src/platform/chromiumos-nvidia-cross/vendor}"
OGKM_DIR="${NVIDIA_VENDOR_DIR}/open-gpu-kernel-modules"

LICENSE="MIT GPL-2"
SLOT="0"
KEYWORDS="-* amd64"
IUSE=""

# Modules must match the kernel they were built against, so the kernel is a build-time
# dependency and this package is rebuilt whenever the kernel is.
DEPEND="virtual/linux-sources"
RDEPEND="
	~x11-libs/nvidia-userspace-${PV}
	~sys-firmware/nvidia-gsp-firmware-${PV}
"

S="${WORKDIR}/open-gpu-kernel-modules"

# Where the board's kernel source and build output live inside the sysroot. These are
# the values most likely to need adjusting against a fresh checkout, so they are named
# once here instead of being scattered through the phases.
kernel_src_dir() {
	local d
	for d in \
		"${SYSROOT}/usr/src/linux" \
		"${SYSROOT}/usr/src/linux-headers-$(best_version sys-kernel/chromeos-kernel-6_12 2>/dev/null)" \
		"${SYSROOT}"/usr/src/linux-* ; do
		[[ -d ${d} ]] && { echo "${d}"; return 0; }
	done
	return 1
}

src_unpack() {
	# Copy rather than build in place: portage expects a writable ${S}, and the vendor
	# tree is a pinned git checkout that must not be modified.
	if [[ ! -d ${OGKM_DIR} ]]; then
		die "NVIDIA module source not staged at ${OGKM_DIR}.
		Run tools/fetch-nvidia.sh first (it pins commit and verifies checksums)."
	fi
	mkdir -p "${S}" || die
	cp -a "${OGKM_DIR}/." "${S}/" || die "failed to stage module source"

	# Refuse to build if the staged source is not the version this ebuild is named for.
	# A silent mismatch here produces a module that loads but reports a version error
	# against the userspace, which is a confusing failure to debug later.
	local src_ver
	src_ver=$(sed -n 's/^NVIDIA_VERSION *= *//p' "${S}/version.mk" | tr -d ' ')
	if [[ ${src_ver} != ${PV} ]]; then
		die "staged module source is ${src_ver} but this ebuild is ${PV}"
	fi
	einfo "module source version ${src_ver} confirmed"
}

src_configure() {
	KERNEL_SRC=$(kernel_src_dir) || die "cannot locate kernel source in ${SYSROOT}/usr/src"
	KERNEL_OUT="${KERNEL_SRC}"
	einfo "kernel source: ${KERNEL_SRC}"

	# Fail early and legibly on the hardening options that reject out-of-tree modules,
	# rather than after a long compile with an inscrutable link error.
	"${FILESDIR}/build-nvidia-modules.sh" --probe --kernel-src "${KERNEL_SRC}" \
		|| die "kernel config rejects out-of-tree modules.
		Apply patches/kernel/nvidia-generic-module-support.config to the board kernel.
		See docs/architecture.md for why each option matters."
}

src_compile() {
	# CC/LD are left unset on purpose: NVIDIA's build reads CONFIG_CC_VERSION_TEXT from
	# the kernel .config and selects the same compiler that built the kernel. That is
	# exactly what an out-of-tree module needs, and hardcoding a compiler here would
	# break it for a clang-built ChromeOS kernel.
	"${FILESDIR}/build-nvidia-modules.sh" \
		--ogkm "${S}" \
		--kernel-src "${KERNEL_SRC}" \
		--kernel-out "${KERNEL_OUT}" \
		--jobs "$(nproc)" \
		|| die "NVIDIA module build failed"
}

src_install() {
	local kv modules_dir
	kv=$(basename "${KERNEL_SRC}")
	modules_dir="/lib/modules/${kv}/extra"

	insinto "${modules_dir}"
	local m
	for m in nvidia nvidia-modeset nvidia-drm nvidia-uvm; do
		local ko
		ko=$(find "${S}/kernel-open" -name "${m}.ko" -print -quit)
		[[ -n ${ko} ]] || die "built module ${m}.ko not found"
		doins "${ko}"
	done

	# Load order matters: nvidia, then nvidia-modeset, then nvidia-drm. modprobe works
	# it out from dependencies, but the softdep makes it explicit.
	insinto /etc/modprobe.d
	doins "${FILESDIR}/nvidia.conf"

	# RTX KMS, no NVIDIA fbcon (fbdev=0) so Ash can drmSetMaster.
	newins "${FILESDIR}/nvidia-modeset.conf" nvidia-modeset.conf

	# Device nodes. ChromeOS has no nvidia-modprobe running as root at login, so the
	# nodes are created by udev instead.
	insinto /lib/udev/rules.d
	doins "${FILESDIR}/99-nvidia-dev.rules"
}

pkg_postinst() {
	elog "NVIDIA open kernel modules ${PV} installed."
	elog ""
	elog "Modesetting is ENABLED (/etc/modprobe.d/nvidia-modeset.conf):"
	elog "    options nvidia-drm modeset=1 fbdev=0"
	elog "Plug the GUI monitor into the RTX. iGPU/amdgpu stays loaded for recovery."
	elog ""
	elog "Driver + iGPU gate:"
	elog "    lspci -k | grep -A3 10de:2705    # driver in use should be 'nvidia'"
	elog "    lspci -k | grep -A3 1002:164e    # iGPU should be 'amdgpu'"
	elog "    cat /sys/module/nvidia_drm/parameters/modeset   # expect Y or 1"
	elog "    nvidia-smi                       # should report the 4070 Ti SUPER"
}
