{
  description = "Pinned developer tools for FStack Firecracker guests";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      systems = [ "aarch64-linux" "x86_64-linux" ];
    in {
      packages = nixpkgs.lib.genAttrs systems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          # nixpkgs bundles every cloud provider by default. Keep the SDK/CLI only;
          # projects select provider plugins separately.
          pulumiCli = pkgs.pulumi-bin.overrideAttrs (old: {
            srcs = [ (builtins.head old.srcs) ];
            postUnpack = "";
          });
        in {
          default = pkgs.buildEnv {
            name = "fstack-devtools";
            paths = with pkgs; [
              nix cacert
              git gh openssh curl jq ripgrep fd
              bashInteractive coreutils findutils gnugrep gnused gawk
              gnutar gzip unzip which less tmux
              nodejs bun python3 uv
              rustc cargo gcc gnumake cmake pkg-config
              pulumiCli
            ];
            pathsToLink = [ "/bin" "/etc/ssl/certs" "/share/man" ];
          };
        });
    };
}
