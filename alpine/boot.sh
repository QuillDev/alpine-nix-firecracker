#!/bin/sh
set -eu
fail() { echo "FSTACK_GUEST_FAILED Alpine boot failed"; }
trap fail EXIT
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t tmpfs tmpfs /run
mkdir -p /dev/pts /dev/shm /run/fstack-config /workspace /run/fstack-tools /nix
mount -t devpts devpts /dev/pts
mount -t tmpfs tmpfs /dev/shm
mount -t ext4 -o ro /dev/vdb /run/fstack-config
mount -t ext4 /dev/vdc /workspace
mount -t ext4 -o ro /dev/vdd /run/fstack-tools
mkdir -p /workspace/.fstack-nix/upper /workspace/.fstack-nix/work
if [ -f /workspace/.fstack-nix/generation ]; then
  cmp /run/fstack-tools/.fstack-profile /workspace/.fstack-nix/generation || {
    echo 'FSTACK_GUEST_FAILED Nix tools generation changed; use a new workspace'
    exit 1
  }
else
  cp /run/fstack-tools/.fstack-profile /workspace/.fstack-nix/generation
fi
mount -t overlay overlay -o lowerdir=/run/fstack-tools,upperdir=/workspace/.fstack-nix/upper,workdir=/workspace/.fstack-nix/work /nix
hostname fstack-alpine
ip link set lo up
# FStack encodes the guest IPv4 address in the final four MAC octets.
IFS=: read -r prefix suffix a b c d < /sys/class/net/eth0/address
[ "$prefix:$suffix" = "06:00" ]
ip addr add "$((0x$a)).$((0x$b)).$((0x$c)).$((0x$d))/30" dev eth0
ip link set eth0 up
trap - EXIT
