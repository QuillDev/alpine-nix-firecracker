#!/usr/bin/env bash
set -euo pipefail

# Build once; each VM mounts the immutable Nix disk read-only with its own overlay.
# Use build.sh to fetch the pinned Firecracker binary/kernel first.
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
ALPINE_VERSION=3.24.0
case "$(uname -s)-$(uname -m)" in
  Linux-aarch64) arch=aarch64; ALPINE_SHA256=4b8cd66a6688b2a87276c39843ed89c3a06d9534fc6a5823c586aff2696c1f2a ;;
  Linux-x86_64) arch=x86_64; ALPINE_SHA256=de9a11c0e0e7e9c94db3ed8af7b450eafc0b13687bd7e9199d55050f20aa0a89 ;;
  *) echo 'Alpine Firecracker images require Linux aarch64 or x86_64' >&2; exit 1 ;;
esac
home=${FSTACK_FIRECRACKER_HOME:-$script_dir/out}
case "$home" in /|""|"$HOME") echo "unsafe asset directory: $home" >&2; exit 1 ;; esac
mkdir -p "$home/assets"
home=$(cd "$home" && pwd)
assets=$home/assets
firecracker=${FSTACK_FIRECRACKER_BIN:-$assets/firecracker}
kernel=${FSTACK_FIRECRACKER_KERNEL:-$assets/vmlinux-6.1.155}
for asset in "$firecracker" "$kernel"; do
  [[ -f $asset ]] || { echo 'Run build.sh to fetch the pinned runtime first.' >&2; exit 1; }
done
for tool in nix curl tar sha256sum mke2fs truncate du python3; do command -v "$tool" >/dev/null; done
export NIX_CONFIG="${NIX_CONFIG:-}
experimental-features = nix-command flakes"
profile=$(nix build --no-update-lock-file --no-link --print-out-paths "path:$script_dir/devtools#default")
[[ $profile == /nix/store/* && -d $profile ]] || { echo 'invalid Nix profile' >&2; exit 1; }
profile_id=$(basename "$profile")
tools_disk=$assets/$profile_id.ext4
build=$(mktemp -d "$home/alpine-build.XXXXXX")
cleanup() {
  find "$build" -type d -exec chmod u+w {} +
  rm -rf "$build"
}
trap cleanup EXIT
if [[ ! -f $tools_disk ]]; then
  nix copy --no-check-sigs --to "$build/tools" "$profile"
  printf '%s\n' "$profile" > "$build/tools/nix/.fstack-profile"
  mkdir -p "$build/tools/nix/var/nix/profiles" "$build/tools/nix/var/nix/gcroots"
  ln -s "$profile" "$build/tools/nix/var/nix/profiles/default"
  ln -s "$profile" "$build/tools/nix/var/nix/gcroots/fstack-devtools"
  used_mib=$(du -sm "$build/tools/nix" | cut -f1)
  truncate -s "$((used_mib + used_mib / 4 + 128))M" "$build/tools.ext4"
  mke2fs -q -t ext4 -F -i 8192 -L FSTACK_TOOLS -d "$build/tools/nix" "$build/tools.ext4"
  mv "$build/tools.ext4" "$tools_disk"
fi
archive=$assets/alpine-minirootfs-$ALPINE_VERSION-$arch.tar.gz
if [[ ! -f $archive ]]; then
  curl -fL --retry 3 "https://dl-cdn.alpinelinux.org/alpine/v3.24/releases/$arch/$(basename "$archive")" -o "$build/alpine.tar.gz"
  mv "$build/alpine.tar.gz" "$archive"
fi
printf '%s  %s\n' "$ALPINE_SHA256" "$archive" | sha256sum --check -
root=$build/root
mkdir -p "$root"
tar --no-same-owner -xzf "$archive" -C "$root"
mkdir -p "$root/usr/local/bin" "$root/etc/profile.d" "$root/etc/nix" "$root/nix" "$root/proc" "$root/sys" "$root/run" "$root/workspace"
install -m 0755 "$script_dir/guest-agent.py" "$root/usr/local/bin/fstack-guest-agent"
for name in boot start stop; do install -m 0755 "$script_dir/alpine/$name.sh" "$root/etc/fstack-$name"; done
printf '127.0.0.1 localhost fstack-alpine\n::1 localhost\n' > "$root/etc/hosts"
printf 'fstack-alpine\n' > "$root/etc/hostname"
cat > "$root/etc/inittab" <<'INIT'
::sysinit:/etc/fstack-boot
::once:/etc/fstack-start
::shutdown:/etc/fstack-stop
INIT
cat > "$root/etc/nix/nix.conf" <<'NIX'
experimental-features = nix-command flakes
build-users-group =
sandbox = true
ssl-cert-file = /nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt
NIX
cat > "$root/etc/profile.d/fstack-devtools.sh" <<'PROFILE'
export PATH=/nix/var/nix/profiles/default/bin:$PATH
export SSL_CERT_FILE=/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt
export NIX_SSL_CERT_FILE=$SSL_CERT_FILE
PROFILE
# The rootfs contents depend only on these pinned inputs and builder sources.
root_id=$(cat "$script_dir/setup-alpine.sh" "$script_dir/guest-agent.py" "$script_dir"/alpine/*.sh <(printf '%s' "$ALPINE_SHA256") | sha256sum | cut -c1-16)
rootfs=$assets/fstack-alpine-$ALPINE_VERSION-$root_id.ext4
if [[ ! -f $rootfs ]]; then
  truncate -s 64M "$build/rootfs.ext4"
  mke2fs -q -t ext4 -F -L FSTACK_ROOT -d "$root" "$build/rootfs.ext4"
  mv "$build/rootfs.ext4" "$rootfs"
fi
{
  printf 'export FSTACK_FIRECRACKER_BIN=%q\n' "$firecracker"
  printf 'export FSTACK_FIRECRACKER_KERNEL=%q\n' "$kernel"
  printf 'export FSTACK_FIRECRACKER_ROOTFS=%q\n' "$rootfs"
  printf 'export FSTACK_FIRECRACKER_TOOLS=%q\n' "$tools_disk"
  printf 'export FSTACK_FIRECRACKER_MKE2FS=%q\n' "$(command -v mke2fs)"
} > "$home/environment-alpine.part"
mv "$home/environment-alpine.part" "$home/environment-alpine"
printf 'Alpine + Nix assets ready. Source %s/environment-alpine\n' "$home"
