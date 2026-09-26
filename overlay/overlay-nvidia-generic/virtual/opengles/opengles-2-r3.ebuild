# Copyright 2026 The ChromiumOS-NVIDIA-cross Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

DESCRIPTION="Virtual for OpenGLES implementations"

LICENSE="metapackage"
SLOT="0"
KEYWORDS="*"
IUSE=""

# This override exists because VIDEO_CARDS alone does not choose the GL implementation on
# ChromeOS. ChromeOS does not build one media-libs/mesa with a set of gallium drivers
# selected by VIDEO_CARDS -- it ships split packages (mesa-amd, mesa-iris, mesa-radv,
# mesa-llvmpipe, mesa-freedreno, mesa-panfrost, mesa-reven), each hardcoding its driver.
# media-libs/mesa-amd passes -Dgallium-drivers=radeonsi unconditionally and reads no
# VIDEO_CARDS at all.
#
# Which one a board gets is decided here, by virtual/opengles. amd64-generic overrides it
# to media-libs/mesa-llvmpipe, so inheriting from that board unchanged would give software
# rendering no matter what VIDEO_CARDS or the kernel config said -- the iGPU would be
# driven by amdgpu in the kernel and then never used for GL.
#
# mesa-amd is what every real AMD board uses: chipset-cezanne, chipset-mendocino and
# overlay-grunt all point virtual/opengles at it.
#
# WHY THE -r3. Being in a higher-priority overlay is not enough to win here. Portage picks
# the highest *version* across the whole masters chain, and only breaks ties by overlay
# priority. amd64-generic ships opengles-2-r2, so a plain opengles-2 from this overlay
# (which is -r0) would lose to it and this file would be silently ignored -- leaving
# mesa-llvmpipe and a software-rendered image, with nothing obviously wrong.
#
# This revision therefore has to stay above amd64-generic's highest. That coupling is real
# and will break quietly on an uprev, so check it before trusting a build:
#
#   ls ~/chromiumos/src/overlays/overlay-amd64-generic/virtual/opengles/
#
# chromiumos-overlay is at version 1, so it does not enter into this. The in-tree boards
# solve it the same way: overlay-grunt ships opengles-2-r4, chipset-mendocino opengles-2-r1.
DEPEND="media-libs/mesa-amd"
RDEPEND="${DEPEND}"
