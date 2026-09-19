#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
FIRECRACKER_VERSION=1.15.1
CI_VERSION=v1.15
KERNEL_VERSION=6.1.155
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)
    arch=x86_64
    KERNEL_SHA256=e20e46d0c36c55c0d1014eb20576171b3f3d922260d9f792017aeff53af3d4f2
    FIRECRACKER_SHA256=d4a32ab2322d887ca1bc4a4e7afa9cc35393e6362dfc2b3becb389d362e4275a
    ;;
  Linux-aarch64)
    arch=aarch64
    KERNEL_SHA256=e3544b10603acbf3db492cb52e000d22ba202cb4b63b9add027565683e11c591
    FIRECRACKER_SHA256=00654ac1e702a22744121ea9f10a4f792ebd7c3a744cba587dfac9fcb79b41a5
    ;;
  *) echo "Firecracker setup requires Linux x86_64 or aarch64" >&2; exit 1 ;;
esac
home=${FSTACK_FIRECRACKER_HOME:-$script_dir/out}
case "$home" in /|""|"$HOME") echo "unsafe asset directory: $home" >&2; exit 1 ;; esac
mkdir -p "$home/assets"
home=$(cd "$home" && pwd)
assets=$home/assets
build=$(mktemp -d "$home/runtime-build.XXXXXX")
trap 'rm -rf "$build"' EXIT
fetch() {
  local url=$1 destination=$2 checksum=$3
  if [[ ! -f $destination ]]; then
    curl -fL --retry 3 "$url" -o "$build/download"
    printf '%s  %s\n' "$checksum" "$build/download" | sha256sum --check -
    mv "$build/download" "$destination"
  fi
  printf '%s  %s\n' "$checksum" "$destination" | sha256sum --check -
}
release=firecracker-v${FIRECRACKER_VERSION}-${arch}.tgz
fetch "https://github.com/firecracker-microvm/firecracker/releases/download/v${FIRECRACKER_VERSION}/$release" "$assets/$release" "$FIRECRACKER_SHA256"
tar -xzf "$assets/$release" -C "$build"
install -m 0755 "$build/release-v${FIRECRACKER_VERSION}-${arch}/firecracker-v${FIRECRACKER_VERSION}-${arch}" "$assets/firecracker.new"
mv "$assets/firecracker.new" "$assets/firecracker"
kernel=$assets/vmlinux-$KERNEL_VERSION
fetch "https://s3.amazonaws.com/spec.ccfc.min/firecracker-ci/$CI_VERSION/$arch/vmlinux-$KERNEL_VERSION" "$kernel" "$KERNEL_SHA256"
{
  printf 'export FSTACK_FIRECRACKER_BIN=%q\n' "$assets/firecracker"
  printf 'export FSTACK_FIRECRACKER_KERNEL=%q\n' "$kernel"
} > "$home/environment-runtime"
