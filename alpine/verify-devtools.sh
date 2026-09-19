#!/usr/bin/env bash
set -euo pipefail
SECONDS=0
grep -q '^ID=alpine$' /etc/os-release
grep -q ' /nix overlay ' /proc/mounts
grep -q ' /run/fstack-tools ext4 ro,' /proc/mounts
python3 -c 'import os; assert len(os.getrandom(32, os.GRND_NONBLOCK)) == 32'
for tool in gh git nix node bun python3 uv rustc cargo gcc make cmake pkg-config curl jq rg fd; do
  echo "tool=$tool elapsed=${SECONDS}s"
  "$tool" --version | sed -n '1p'
done
tmux -V
echo "tool=pulumi elapsed=${SECONDS}s"
PULUMI_SKIP_UPDATE_CHECK=true pulumi version
echo "tool=nix-profile elapsed=${SECONDS}s"
[[ $(nix eval --offline --expr '20 + 22') == 42 ]]
profile=$(cat /nix/.fstack-profile)
nix profile add --offline --profile /nix/var/nix/profiles/smoke "$profile"
[[ -x /nix/var/nix/profiles/smoke/bin/gh ]]
# A store-local write must be private to each VM and survive its restart.
marker=/nix/var/nix/fstack-smoke-instance
if [[ -f $marker ]]; then [[ $(cat "$marker") == "$INSTANCE" ]]; fi
printf '%s\n' "$INSTANCE" > "$marker"
printf '#include <stdio.h>\nint main(void) { puts("c-ok"); }\n' > smoke.c
gcc smoke.c -o smoke-c
[[ $(./smoke-c) == c-ok ]]
printf 'fn main() { println!("rust-ok"); }\n' > smoke.rs
rustc smoke.rs -o smoke-rust
[[ $(./smoke-rust) == rust-ok ]]
[[ $(node -e 'console.log("node-ok")') == node-ok ]]
[[ $(bun -e 'console.log("bun-ok")') == bun-ok ]]
echo "FSTACK_DEVTOOLS_VERIFIED elapsed=${SECONDS}s"
