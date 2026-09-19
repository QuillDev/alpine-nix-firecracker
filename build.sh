#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
export FSTACK_FIRECRACKER_HOME=${FSTACK_FIRECRACKER_HOME:-$script_dir/out}
for tool in nix curl tar sha256sum mke2fs truncate du python3; do
  command -v "$tool" >/dev/null || { echo "missing build dependency: $tool" >&2; exit 1; }
done
"$script_dir/fetch-runtime.sh"
# shellcheck source=/dev/null
source "$FSTACK_FIRECRACKER_HOME/environment-runtime"
exec "$script_dir/setup-alpine.sh"
