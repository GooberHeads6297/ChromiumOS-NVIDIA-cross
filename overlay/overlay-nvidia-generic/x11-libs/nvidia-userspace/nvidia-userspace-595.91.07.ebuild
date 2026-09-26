# Copyright 2026 The ChromiumOS-NVIDIA-cross Authors
# Distributed under the terms of the NVIDIA Software License.

EAPI=7

DESCRIPTION="NVIDIA userspace libraries (EGL, GLX, Vulkan, GBM) for nvidia-generic"
HOMEPAGE="https://www.nvidia.com/"

# Staged by tools/fetch-nvidia.sh, which verifies the installer against NVIDIA's
# published sha256 and extracts it with --extract-only. The installer is never executed:
# running it would overwrite the host's working driver, which is our recovery path.
NVIDIA_VENDOR_DIR="${NVIDIA_VENDOR_DIR:-/mnt/host/source/src/platform/chromiumos-nvidia-cross/vendor}"
NV_DIST="${NVIDIA_VENDOR_DIR}/NVIDIA-Linux-x86_64-${PV}"

LICENSE="NVIDIA-r2"
SLOT="0"
KEYWORDS="-* amd64"
IUSE="vulkan"

RDEPEND="
	~sys-firmware/nvidia-gsp-firmware-${PV}
	media-libs/libglvnd
"
DEPEND=""

S="${WORKDIR}"

# libnvidia-egl-gbm carries its own version, independent of the driver version. As of
# driver 595.91.07 it is 1.1.3, confirmed in the extracted bundle. Hardcoding the driver
# version here would silently install nothing.
EGL_GBM_VER="1.1.3"

src_unpack() {
	if [[ ! -d ${NV_DIST} ]]; then
		die "NVIDIA userspace not staged at ${NV_DIST}.
		Run tools/fetch-nvidia.sh first."
	fi
	cp -a "${NV_DIST}" "${S}/dist" || die "failed to stage userspace"
}

# Install a versioned .so plus the SONAME and bare symlinks glvnd looks for.
donvlib() {
	local lib=$1 soname=$2
	[[ -f ${S}/dist/${lib} ]] || die "expected library missing from bundle: ${lib}"
	dolib.so "${S}/dist/${lib}"
	if [[ -n ${soname} ]]; then
		dosym "${lib}" "/usr/$(get_libdir)/${soname}"
	fi
}

src_install() {
	# --- core driver libraries -------------------------------------------------
	donvlib "libnvidia-glcore.so.${PV}"    ""
	donvlib "libnvidia-allocator.so.${PV}" "libnvidia-allocator.so.1"

	# --- EGL / GLX vendor libraries (dispatched via glvnd) ---------------------
	donvlib "libEGL_nvidia.so.${PV}" "libEGL_nvidia.so.0"
	donvlib "libGLX_nvidia.so.${PV}" "libGLX_nvidia.so.0"

	# --- the GBM backend, which is what makes the Chrome/Ozone path possible ---
	# Chrome on ChromeOS allocates through minigbm and presents through GBM. NVIDIA's
	# GBM support lives here rather than in Mesa, so this library plus its vendor JSON
	# are the load-bearing pieces of Stage 3.
	donvlib "libnvidia-egl-gbm.so.${EGL_GBM_VER}" "libnvidia-egl-gbm.so.1"

	# --- vendor configuration files -------------------------------------------
	# Paths and contents confirmed from the extracted bundle:
	#   10_nvidia.json       -> EGL vendor, points at libEGL_nvidia.so.0
	#   15_nvidia_gbm.json   -> GBM backend, points at libnvidia-egl-gbm.so.1
	#   nvidia_icd.json      -> Vulkan ICD, api_version 1.4.329
	insinto /usr/share/glvnd/egl_vendor.d
	doins "${S}/dist/10_nvidia.json"

	insinto /usr/share/egl/egl_external_platform.d
	doins "${S}/dist/15_nvidia_gbm.json"
	doins "${S}/dist/10_nvidia_wayland.json"

	if use vulkan; then
		insinto /usr/share/vulkan/icd.d
		doins "${S}/dist/nvidia_icd.json"
		insinto /usr/share/vulkan/implicit_layer.d
		doins "${S}/dist/nvidia_layers.json"
	fi

	# --- CUDA, for compute workloads and some Proton paths --------------------
	donvlib "libcuda.so.${PV}" "libcuda.so.1"

	# --- tools ----------------------------------------------------------------
	# nvidia-smi is not optional here: it is how every stage gate is verified, and how
	# safety/gpu-guard.sh reads temperature, power and fan speed.
	dobin "${S}/dist/nvidia-smi"
	dobin "${S}/dist/nvidia-modprobe"
	dobin "${S}/dist/nvidia-persistenced"

	# nvidia-modprobe normally runs setuid to create device nodes on demand. We create
	# them from udev instead (99-nvidia-dev.rules), so it stays unprivileged.

	# --- loader environment ---------------------------------------------------
	# ChromeOS normally has exactly one GL stack, so nothing tells the EGL/GBM/Vulkan
	# loaders that a second vendor exists. This sets the search paths that make
	# Chrome's Ozone/GBM backend able to find NVIDIA at all.
	insinto /etc/profile.d
	newins "${FILESDIR}/nvidia-egl-env.sh" nvidia-egl-env.sh

	# GBM backend directory. Mesa's GBM loader looks for a backend named after the DRM
	# driver, so libnvidia-egl-gbm is linked in as "nvidia-drm_gbm.so".
	dodir "/usr/$(get_libdir)/gbm"
	dosym "../libnvidia-egl-gbm.so.1" "/usr/$(get_libdir)/gbm/nvidia-drm_gbm.so"

	# Chrome flags for Stage 3, installed as a reference rather than applied. Appending
	# them to /etc/chrome_dev.conf is a deliberate step, not something a package should
	# do on the user's behalf.
	insinto /usr/share/chromiumos-nvidia-cross
	doins "${FILESDIR}/chrome_dev.conf.nvidia"
}

pkg_postinst() {
	elog "NVIDIA userspace ${PV} installed."
	elog ""
	elog "Version matching is critical: these libraries, the kernel modules and the GSP"
	elog "firmware must all be ${PV}. A mismatch shows up as nvidia-smi reporting a"
	elog "driver/library version mismatch."
	elog ""
	elog "Verify the staged bundle at any time with:  tools/fetch-nvidia.sh --verify"
}
