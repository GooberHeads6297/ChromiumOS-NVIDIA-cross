#!/bin/bash
# tools/fetch-openfyde-research.sh -- shallow-clone public openFyde repos for study.
#
# Output: vendor/openfyde-research/ (gitignored under /vendor/).
# Does not fetch FydeOS commercial images or binaries.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "${REPO_ROOT}/safety/lib-common.sh"

DEST="${REPO_ROOT}/vendor/openfyde-research"
REPOS=(
    getting-started
    project-openfyde-patches
    overlay-amd64-openfyde
    overlay-amd64-openfyde_apu
)

mkdir -p "$DEST"
banner "openFyde research clones -> ${DEST}"

for name in "${REPOS[@]}"; do
    url="https://github.com/openFyde/${name}.git"
    if [ -d "${DEST}/${name}/.git" ]; then
        log "updating ${name}"
        git -C "${DEST}/${name}" pull --ff-only || warn "pull failed for ${name}; keeping existing tree"
    else
        log "cloning ${name}"
        git clone --depth 1 "$url" "${DEST}/${name}" || die "clone failed: ${url}"
    fi
done

banner "done"
log "see docs/research-openfyde-auth.md"
