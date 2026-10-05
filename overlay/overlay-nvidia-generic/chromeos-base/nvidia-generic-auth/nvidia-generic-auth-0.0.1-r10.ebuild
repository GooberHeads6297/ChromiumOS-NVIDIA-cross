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
	dosbin "${FILESDIR}/create-local-account.sh"
	dosbin "${FILESDIR}/register-local-login.sh"
	dosbin "${FILESDIR}/ensure-software-tpm.sh"
	dosbin "${FILESDIR}/collect-auth-debug.sh"
	dosbin "${FILESDIR}/verify-local-account.sh"
	dosbin "${FILESDIR}/verify-auth-bringup.sh"
	dosbin "${FILESDIR}/verify-crostini-host.sh"

	insinto /usr/share/chromiumos-nvidia-cross
	doins "${FILESDIR}/chrome_dev.conf.auth"
	doins "${FILESDIR}/chrome_dev.conf.display"
	doins "${FILESDIR}/local-account-setup.py"
	fperms 0755 /usr/share/chromiumos-nvidia-cross/local-account-setup.py

	insinto /usr/share/chromiumos-nvidia-cross/local-account-ext
	doins "${FILESDIR}/local-account-ext/manifest.json"
	doins "${FILESDIR}/local-account-ext/background.js"
	doins "${FILESDIR}/local-account-ext/popup.html"

	exeinto /usr/share/chromiumos-nvidia-cross
	newexe "${FILESDIR}/collect-auth-debug.sh" collect-auth-debug.sh
	newexe "${FILESDIR}/verify-local-account.sh" verify-local-account.sh
	newexe "${FILESDIR}/verify-auth-bringup.sh" verify-auth-bringup.sh
	newexe "${FILESDIR}/verify-crostini-host.sh" verify-crostini-host.sh

	insinto /etc/init
	doins "${FILESDIR}/nvidia-generic-auth-chrome.conf"
	doins "${FILESDIR}/local-account-setup.conf"

	insinto /etc
	newins "${FILESDIR}/chrome_dev.conf.auth" chrome_dev.conf.nvidia-generic-auth
}

pkg_postinst() {
	elog "nvidia-generic-auth installed. GUI: http://127.0.0.1:17891/"
}
