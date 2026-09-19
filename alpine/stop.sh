#!/bin/sh
if [ -f /run/fstack-guest-agent.pid ]; then
  pid=$(cat /run/fstack-guest-agent.pid)
  kill -TERM "$pid" 2>/dev/null || true
  for _ in $(seq 1 60); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
  done
fi
sync
umount /nix /run/fstack-tools /workspace /run/fstack-config
sync
