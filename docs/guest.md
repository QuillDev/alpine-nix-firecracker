# Guest setup

The image uses a Python supervisor to run commands from a launch plan. Your launcher
needs to provide the disks and networking described below.

Attach disks in this order:

1. `/dev/vda`: a **private writable copy** of the Alpine rootfs.
2. `/dev/vdb`: an ext4 config disk containing `plan.json` at its root.
3. `/dev/vdc`: a **private persistent** writable ext4 workspace disk.
4. `/dev/vdd`: the shared tools disk, with Firecracker `is_read_only: true`.

The guest mounts an OverlayFS filesystem at `/nix`: the shared tools disk is the lower
layer, and `/workspace/.fstack-nix` holds each VM's persistent upper layer. Nix profile
and store changes stay private. `/root` and other rootfs changes are ephemeral.
The workspace must have room for source, outputs, and new Nix packages.

Configure an `eth0` TAP interface with a MAC of `06:00:AA:BB:CC:DD`, where the final four
bytes encode its guest IPv4 address. For example `06:00:AC:1E:10:02` gives
`172.30.16.2/30`; the host TAP can use `172.30.16.1/30`. The launcher must allocate
non-conflicting addresses, create the TAP, and handle forwarding and cleanup.

Use a vsock device with guest CID 3 and a unique host socket per VM, plus an entropy
device (`"entropy": {}`). ARM64 boot arguments:

```text
keep_bootcon console=ttyS0 quiet loglevel=3 reboot=k panic=1 root=/dev/vda rw
```

For x86_64 omit `keep_bootcon` and add `pci=off`. The guest writes
`FSTACK_STACK_READY` to its serial console after commands report readiness.
See [examples/plan.json](../examples/plan.json) for a minimal launch plan. Its working
directory must exist on the workspace disk. Plan commands execute as root in the guest.

For graceful shutdown, connect to the VM's host vsock Unix socket, send
`CONNECT 10000\n`, read the `OK ...` handshake, then send `shutdown\n`.
The guest accepts shutdown requests only from host CID 2.


`out/environment-alpine` contains the asset paths for a compatible FStack launcher.
Run `source out/environment-alpine` to load them. Update the paths if you move the
images to another host.

The launcher handles internet access, DNS, credentials, and VM cleanup. The image
does not include a coding-agent service.
