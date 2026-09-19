#!/bin/sh
export PATH=/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
if ! grep -q ' /nix overlay ' /proc/mounts; then
  echo 'FSTACK_GUEST_FAILED Nix tools disk was not mounted'
  exit 1
fi
echo $$ > /run/fstack-guest-agent.pid
exec python3 -u /usr/local/bin/fstack-guest-agent
