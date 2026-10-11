#!/bin/bash
# Rebuild GBM + AddFB LD_PRELOAD shims on the Ubuntu host (no cros_sdk).
#
#   ./tools/build-display-shims.sh
#   sudo ./tools/copy-sbin-scripts-to-disk.sh /dev/nvme1n1
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUTH="${REPO_ROOT}/overlay/overlay-nvidia-generic/chromeos-base/nvidia-generic-auth/files"
cd "$AUTH"

gcc -shared -fPIC -O2 -Wall -Wextra \
  -o libgbm-minigbm-compat.so gbm-minigbm-compat.c -ldl
echo "OK  $AUTH/libgbm-minigbm-compat.so"

# Forwards.S exports every libdrm symbol; compat C provides the hooks.
gcc -shared -fPIC -O2 -Wall \
  -o libdrm-addfb-compat.so drm-addfb-compat.c drm-addfb-forwards.S -ldl
echo "OK  $AUTH/libdrm-addfb-compat.so"

ls -l libgbm-minigbm-compat.so libdrm-addfb-compat.so
