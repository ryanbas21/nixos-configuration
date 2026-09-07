# just is a command runner (nix shell nixpkgs#just). The repo's
# operational surface as one-word commands; the ritual behind them is
# docs/operations.md, the agent contract is AGENTS.md.

set shell := ["bash", "-c"]

# List all recipes
default:
    @just --list

# Evaluate every flake output (exactly CI's flake-check job)
[group('nix')]
check:
    nix flake check --no-build

# Update every input and commit the lockfile
[group('nix')]
up:
    nix flake update --commit-lock-file

# Update one input — nixpkgs and home-manager move together
[group('nix')]
upp input:
    nix flake update {{input}} --commit-lock-file

# Boot a host's VM test: the fresh-boot contract (nixos|framework|harmonia)
[group('nix')]
test-host host:
    nix build -L .#checks.x86_64-linux."{{host}}:vm-test"

# Execute + boot a host's disko layout (nixos|framework|harmonia)
[group('nix')]
test-disko host:
    nix build -L .#checks.x86_64-linux."disko:{{host}}"

# Build a host's real toplevel (what CI's build-hosts pushes to nix-configs)
[group('nix')]
build host:
    nix build --no-link .#nixosConfigurations.{{host}}.config.system.build.toplevel

# Switch the desktop or laptop in place (nixos|framework)
[group('deploy')]
rebuild host:
    sudo nixos-rebuild switch --flake .#{{host}}

# Set the next-boot profile without switching now
[group('deploy')]
boot host:
    sudo nixos-rebuild boot --flake .#{{host}}

# Deploy the cache server from the desktop (never rebuild on the box)
[group('deploy')]
deploy-harmonia:
    sudo nixos-rebuild switch --flake .#harmonia --target-host root@192.168.1.82

# Probe the LAN cache: which paths of a closure can .82 serve right now
[group('cache')]
warmth closure="/run/current-system":
    scripts/harmonia-warmth.sh {{closure}}
