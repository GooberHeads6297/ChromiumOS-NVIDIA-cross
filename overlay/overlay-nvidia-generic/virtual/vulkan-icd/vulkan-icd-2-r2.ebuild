# Copyright 2026 The ChromiumOS-NVIDIA-cross Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

DESCRIPTION="Virtual for presence of a Vulkan ICD (Installable Client Driver)"

LICENSE="metapackage"
SLOT="0"
KEYWORDS="*"
IUSE=""

# As with virtual/opengles, the ICD is chosen here rather than by VIDEO_CARDS.
# amd64-generic points this at media-libs/mesa-llvmpipe[vulkan], which is a software
# implementation -- fine for a VM target, useless for Steam.
#
# mesa-radv is the AMD hardware ICD, and is what chipset-cezanne, chipset-mendocino and
# overlay-grunt use. It covers the iGPU only; the RTX's Vulkan ICD comes from NVIDIA's own
# userspace package, which installs its own ICD JSON and so does not need to be named here.
#
# The -r2 is load-bearing for the same reason as virtual/opengles: portage resolves by
# highest version first and overlay priority only as a tiebreak, and amd64-generic ships
# vulkan-icd-2-r1. A plain vulkan-icd-2 here would lose to it. Verify with:
#
#   ls ~/chromiumos/src/overlays/overlay-amd64-generic/virtual/vulkan-icd/
RDEPEND="
	media-libs/vulkan-loader
	media-libs/mesa-radv
"
DEPEND=""
