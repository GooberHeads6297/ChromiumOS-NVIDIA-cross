# Copyright 2026 The ChromiumOS-NVIDIA-cross Authors
# Distributed under the terms of a BSD-style licence.

EAPI=7

DESCRIPTION="TPM/cryptohome resilience helpers and local-account bring-up for nvidia-generic"
HOMEPAGE=""

LICENSE="BSD-Google"
SLOT="0"
KEYWORDS="-* amd64"
IUSE=""

RDEPEND="
	chromeos-base/cryptohome
	dev-lang/python
"
DEPEND=""

S="${WORKDIR}"

src_install() {
	# PATH-visible helpers for live USB / installed system shells.
	dosbin "${FILESDIR}/create-local-account.sh"
	dosbin "${FILESDIR}/register-local-login.sh"
	dosbin "${FILESDIR}/ensure-software-tpm.sh"
	dosbin "${FILESDIR}/collect-auth-debug.sh"
	dosbin "${FILESDIR}/verify-local-account.sh"
	dosbin "${FILESDIR}/verify-auth-bringup.sh"
	dosbin "${FILESDIR}/verify-crostini-host.sh"

	insinto /usr/share/chromiumos-nvidia-cross
	doins "${FILESDIR}/chrome_dev.conf.auth"
	doins "${FILESDIR}/local-account-setup.py"
	fperms 0755 /usr/share/chromiumos-nvidia-cross/local-account-setup.py

	# Chrome MV3 extension (loaded via --load-extension).
	insinto /usr/share/chromiumos-nvidia-cross/local-account-ext
	doins "${FILESDIR}/local-account-ext/manifest.json"
	doins "${FILESDIR}/local-account-ext/background.js"
	doins "${FILESDIR}/local-account-ext/popup.html"

	# Keep share/ copies for docs that reference the old paths.
	exeinto /usr/share/chromiumos-nvidia-cross
	newexe "${FILESDIR}/collect-auth-debug.sh" collect-auth-debug.sh
	newexe "${FILESDIR}/verify-local-account.sh" verify-local-account.sh
	newexe "${FILESDIR}/verify-auth-bringup.sh" verify-auth-bringup.sh
	newexe "${FILESDIR}/verify-crostini-host.sh" verify-crostini-host.sh

	insinto /etc/init
	doins "${FILESDIR}/nvidia-generic-auth-chrome.conf"
	doins "${FILESDIR}/local-account-setup.conf"

	# Seed chrome_dev.conf on test images so flags exist before the merge job runs.
	insinto /etc
	newins "${FILESDIR}/chrome_dev.conf.auth" chrome_dev.conf.nvidia-generic-auth
}

pkg_postinst() {
	elog "nvidia-generic-auth installed."
	elog "  create-local-account.sh / ensure-software-tpm.sh / verify-local-account.sh"
	elog "  GUI:  http://127.0.0.1:17891/"
	elog "  install-to-disk.sh is in chromeos-bsp-nvidia-generic (/usr/sbin)"
}
