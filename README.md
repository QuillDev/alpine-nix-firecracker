# Alpine + Nix for Firecracker

Build a small Alpine guest with a pinned Nix developer toolset. Build the images once,
cache them on each Linux host, and boot without an ISO or package installation.

**This repository contains source only.** VM disks, downloaded binaries, caches, and
build output are excluded from Git. No large images or Git LFS objects are required.

## Build

Use Linux `aarch64` or `x86_64`, with Nix installed and these system tools available:
Bash, curl, tar, coreutils, findutils, e2fsprogs (`mke2fs`), and Python 3.
On Ubuntu the non-Nix dependencies can be installed with:

```sh
sudo apt-get install bash curl tar coreutils findutils e2fsprogs python3
```

Install Nix using its [official installation instructions](https://nixos.org/download/).
Then, as a normal user:

```sh
git clone https://github.com/QuillDev/alpine-nix-firecracker.git
cd alpine-nix-firecracker
./build.sh
source out/environment-alpine
```

Building requires internet access, several GiB of downloads, and sufficient disk space
for the Nix store, export staging, and output images (allow at least 15 GiB free).
Building the images does not require KVM or mounting filesystems as root. Running them
requires Linux/KVM and a Firecracker launcher.

On macOS, run the build and Firecracker inside a Linux VM that exposes `/dev/kvm`.
The ARM64 prototype was tested using Lima with nested virtualization on an Apple M4 Max.
This script does not install or configure a host VM for you.

Override the output directory with `FSTACK_FIRECRACKER_HOME=/absolute/path ./build.sh`.
Do not run multiple builders against the same output directory concurrently.

## What it produces

| Artifact under `out/assets/` | Purpose |
| --- | --- |
| `firecracker` | Checksum-verified Firecracker 1.15.1 binary |
| `vmlinux-6.1.155` | Checksum-verified guest kernel |
| `fstack-alpine-3.24.0-*.ext4` | Private 64 MiB Alpine rootfs template |
| `*-fstack-devtools.ext4` | Shared read-only Nix tools disk, about 4.1 GiB on ARM64 |

`out/environment-alpine` exports absolute paths for a compatible FStack launcher.
It is host-specific: regenerate or adjust those paths when deploying to another machine.
The builder never uploads artifacts. Copy matching-architecture assets to runtime hosts
separately and verify checksums before use.

The Alpine, kernel, and Firecracker downloads are checksum-pinned; `devtools/flake.lock`
pins nixpkgs. Ext4 UUIDs/timestamps are not normalized, so the filesystem images are not
claimed to be byte-for-byte reproducible between builds.

## Included tools

GitHub CLI (`gh`), Pulumi CLI and language hosts, Git, OpenSSH, curl, jq, ripgrep, fd,
Bash, coreutils, tmux, Node, Bun, Python, uv, Rust/Cargo, GCC, Make, CMake, pkg-config,
Nix, and CA certificates.

Edit `devtools/flake.nix` to change the tools. Pulumi cloud-provider plugins are excluded
from the base image; projects provision their own plugins. No credentials are baked in.
To deliberately update the package pin:

```sh
(cd devtools && nix flake update)
./build.sh
```

Use a fresh guest workspace after changing the tools profile. The boot script rejects
an existing Nix overlay paired with a different base profile.

## Runtime contract

This is an image builder, not a VM fleet manager. The included Python supervisor speaks
the FStack stack-launch protocol. Another launcher can use the images by implementing
the same disk and launch-plan contract; no FStack source checkout is needed to build.

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
See [examples/plan.json](examples/plan.json) for a minimal launch plan. Its working
directory must exist on the workspace disk. Plan commands execute as root in the guest.

For graceful shutdown, connect to the VM's host vsock Unix socket, send
`CONNECT 10000\n`, read the `OK ...` handshake, then send `shutdown\n`.
The guest accepts shutdown requests only from host CID 2.

## Validation and limits

`./check.sh` runs source checks, also used by GitHub Actions. CI does not build or upload
multi-gigabyte images. `alpine/verify-devtools.sh` is an optional in-guest smoke test;
set `INSTANCE` to a unique VM identity and run it from a writable workspace directory.

The original ARM64 implementation passed two concurrent VM launches, tool execution,
C/Rust compilation, offline Nix profile installation, private Nix state, restart
persistence, graceful shutdown, application failure, and cleanup tests. Boot-only samples
were approximately 5.8 seconds per VM under nested virtualization with cached assets.
The complete tool smoke test took about 51 seconds per guest and is not a startup step.
The extracted standalone builder also regenerated the images and passed the full
two-VM lifecycle test (7.86 seconds per initial launch with other demo VMs running).
These are prototype measurements, not a performance guarantee. x86_64 inputs are provided
but have not been runtime-tested on the ARM64 development laptop.

The guest does not configure internet egress, DNS forwarding, GitHub/cloud authentication,
or a coding-agent session service. The Python supervisor runs stack commands; it is not
an AI coding agent. Network policy, jailer configuration, resource limits, credentials,
source staging, and lifecycle management are the launcher's responsibility.

The fetched third-party software retains its respective licenses; this repository does
not redistribute its binaries.
