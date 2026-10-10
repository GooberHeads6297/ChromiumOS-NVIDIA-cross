#!/bin/bash
# Rebuild chromeos-chrome with Ozone 0003 (modeset commit / display ID / master).
# Must run in a real terminal (cros_sdk needs sudo). Hours.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${PATH}:${HOME}/depot_tools"
exec "${REPO_ROOT}/tools/rebuild-display-image.sh" --with-chrome "$@"
