# Copyright 2026 The ChromiumOS-NVIDIA-cross Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

DESCRIPTION="amdgpu GC 10.3.6 (Raphael) firmware missing from ChromeOS linux-firmware"
HOMEPAGE="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git"

# linux-firmware ships these under LICENSE.amdgpu, a redistributable-with-notice licence.
LICENSE="linux-fw-redistributable"
SLOT="0"
KEYWORDS="-* amd64"
IUSE=""

S="${WORKDIR}"

# Why this package exists at all.
#
# This board's iGPU is Raphael [1002:164e]. In the 6.12 tree,
# amdgpu_ucode_legacy_naming() (drivers/gpu/drm/amd/amdgpu/amdgpu_ucode.c) has no case for
# IP_VERSION(10, 3, 6), so with no legacy alias amdgpu_ucode_ip_version_decode() falls
# through to the IP-derived name and the driver requests "amdgpu/gc_10_3_6_<part>.bin".
#
# ChromeOS's linux-firmware fork carries gc_10_3_7_* and dcn_3_1_6_dmcub.bin but nothing
# for GC 10.3.6, SDMA 5.2.6, PSP 13.0.5 or VCN 3.1.2. Worse, its ebuild has no USE flag
# that installs general amdgpu firmware at all: the only amdgpu flags are
# amdgpu_gc_11_0_1, amdgpu_gc_11_0_4 and amdgpu_yellow_carp, and video_cards_amdgpu
# affects only LICENSE. So dcn_3_1_6_dmcub.bin is present in that source tree but is never
# installed by anything, and is therefore shipped here too.
#
# Shipped as our own package rather than by overriding the linux-firmware ebuild: that
# ebuild lives in chromiumos-overlay and overriding it would mean carrying a copy of a
# file we do not own, which rots on every uprev.
FW_DIR="/lib/firmware/amdgpu"

# Every file here is on a fatal path. The request sites all propagate their error up
# through amdgpu's early_init/sw_init, so one missing file means no iGPU at all -- and the
# iGPU is the recovery console.
#
#   GC 10.3.6    gfx_v10_0_init_microcode()   "amdgpu/%s_{pfp,me,ce,rlc,mec,mec2}.bin"
#   SDMA 5.2.6   amdgpu_sdma_init_microcode() "amdgpu/%s.bin"
#   PSP 13.0.5   psp_v13_0_init_microcode() -> psp_init_toc_microcode then
#                psp_init_ta_microcode, both guarded by "if (err) return err"
#   VCN 3.1.2    amdgpu_vcn_early_init()      "amdgpu/%s.bin"
#   DCN 3.1.6    display core, dmcub
#
# mec2 is a symlink to mec upstream; it is installed as a real copy because the firmware
# loader resolves names, not links, and a 262 KB duplicate is not worth the subtlety.
#
# No smu_13_0_5.bin: on this APU the SMU firmware comes from the platform BIOS, and
# upstream linux-firmware ships no such file.
RAPHAEL_FW="
	gc_10_3_6_ce.bin
	gc_10_3_6_me.bin
	gc_10_3_6_mec.bin
	gc_10_3_6_mec2.bin
	gc_10_3_6_pfp.bin
	gc_10_3_6_rlc.bin
	sdma_5_2_6.bin
	psp_13_0_5_toc.bin
	psp_13_0_5_ta.bin
	vcn_3_1_2.bin
	dcn_3_1_6_dmcub.bin
"

src_unpack() {
	local missing=() f
	for f in ${RAPHAEL_FW}; do
		[[ -f ${FILESDIR}/${f} ]] || missing+=( "${f}" )
	done

	if [[ ${#missing[@]} -gt 0 ]]; then
		die "Raphael firmware not staged: ${missing[*]}

		Run tools/fetch-amdgpu-firmware.sh first. Without these files amdgpu cannot
		initialise the iGPU, and the iGPU is the recovery console that makes bringing
		up the NVIDIA driver safe. Check dmesg for 'amdgpu/gc_10_3_6' on failure."
	fi
}

src_install() {
	insinto "${FW_DIR}"
	local f
	for f in ${RAPHAEL_FW}; do
		doins "${FILESDIR}/${f}"
	done
}

pkg_postinst() {
	elog "Installed GC 10.3.6 (Raphael) firmware to ${FW_DIR}/"
	elog ""
	elog "This is what lets amdgpu bind to the iGPU [1002:164e]. If the iGPU console is"
	elog "dead, check dmesg for failed 'amdgpu/gc_10_3_6_*' firmware requests before"
	elog "suspecting the kernel config."
}
