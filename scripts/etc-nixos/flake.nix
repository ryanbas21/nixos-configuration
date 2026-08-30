# Wrapper flake for the machine to compose its own hardware configuration
# with the shared configuration in github:ryanbas21/nixos-configuration.
#
# This file is a TEMPLATE meant to be copied to /etc/nixos/flake.nix on the
# box. The repo itself no longer carries any hardware-configuration.nix
# (machine-local data) and gitignores `hardware-configuration.nix` everywhere,
# so the daily auto-backup timer (`git add -A` in scripts/git-backup.sh) can
# never commit a machine-local hardware file.
#
# First-time on-box setup:
#   1. Copy this file to /etc/nixos/flake.nix:
#        sudo cp /home/batman/programming/nixos/scripts/etc-nixos/flake.nix \
#          /etc/nixos/flake.nix
#   2. Ensure /etc/nixos/hardware-configuration.nix exists. It is normally
#      created by `nixos-generate-config` at install time. If it is missing,
#      FIRST recover the last-known-good hardware config from the repo's git
#      history (it was removed from the tree just after commit 8eb6ab6):
#        cd /home/batman/programming/nixos
#        git show 8eb6ab6:modules/_hardware-configuration.nix | \
#          sudo tee /etc/nixos/hardware-configuration.nix
#   3. Build and switch:
#        sudo nixos-rebuild switch --flake /etc/nixos
#
# Picking up repo updates later:
#   cd /etc/nixos && sudo nix flake update nixcfg
#   sudo nixos-rebuild switch --flake /etc/nixos
#
# NOTE: home-manager, nvf, ryan-nvim and fzf-git-sh are all closed over inside
# the repo's modules (modules/home-manager.nix, modules/batman/*.nix) — this
# wrapper needs NO other inputs. `nixpkgs.follows = "nixcfg/nixpkgs"` makes
# the wrapper always use exactly the repo's nixpkgs pin.
{
  description = "Machine-local composition of ryanbas21/nixos-configuration";

  inputs = {
    nixcfg.url = "github:ryanbas21/nixos-configuration";

    nixpkgs.follows = "nixcfg/nixpkgs";
  };

  outputs = {nixcfg, nixpkgs, ...}: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixcfg.nixosModules.host
        ./hardware-configuration.nix
      ];
    };
  };
}
