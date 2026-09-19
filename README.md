# Alpine + Nix for Firecracker

Build an Alpine Linux image for Firecracker with development tools installed through Nix.
Each VM gets its own workspace and shares a read-only tools disk.

## Build

You need Linux (ARM64 or x86_64), [Nix](https://nixos.org/download/), and about 15 GB of free disk space.
On Ubuntu, install the other dependencies with:

```sh
sudo apt-get install bash curl tar coreutils findutils e2fsprogs python3
```

Then build:

```sh
git clone https://github.com/QuillDev/alpine-nix-firecracker.git
cd alpine-nix-firecracker
./build.sh
```

The kernel, Firecracker binary, and disk images go in `out/`. Build output stays out of Git.
To run the images, you need a Linux host with KVM and a launcher that supports the
[guest setup](docs/guest.md).

## Tools

Includes Git, GitHub CLI, Pulumi, Node, Bun, Python, uv, Rust, GCC, and common shell tools.
Pulumi cloud-provider plugins are installed separately.

Edit [devtools/flake.nix](devtools/flake.nix) to change the tools, then run `./build.sh` again.
Package versions are pinned in `devtools/flake.lock`. To update them:

```sh
(cd devtools && nix flake update)
./build.sh
```

Use a new VM workspace after changing the toolset.
