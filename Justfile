# just is a command runner (installed via batman/packages.nix; the
# Justfile is the repo's operational surface as one-word commands; the ritual
# behind them is docs/operations.md, the agent contract is AGENTS.md).

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

# Switch the desktop or laptop in place (nixos|framework). Refuses to
# build another host's config: 2026-09-09 a `just rebuild nixos` run
# ON THE FRAMEWORK switched the desktop's config onto the laptop —
# black screen (desktop GPU stack on AMD iGPU), unbootable default
# entry (desktop's LUKS/ESP mounts), and secure boot rejecting the
# unsigned desktop bootloader. Rollback took a firmware-menu SB
# disable + booting an older generation.
[group('deploy')]
rebuild host:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ "{{host}}" == "$(hostname)" ]] || {
      echo "refusing: this machine is '$(hostname)', not '{{host}}' — build the host you are ON" >&2
      exit 1
    }
    sudo nixos-rebuild switch --flake .#{{host}}

# Set the next-boot profile without switching now (same wrong-host
# guard as rebuild)
[group('deploy')]
boot host:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ "{{host}}" == "$(hostname)" ]] || {
      echo "refusing: this machine is '$(hostname)', not '{{host}}' — build the host you are ON" >&2
      exit 1
    }
    sudo nixos-rebuild boot --flake .#{{host}}

# usbguard: allow a just-plugged device — prints its generated rule,
# appends it to the host's _usbguard.nix (above the marker), and
# runtime-allows it so it works before the next rebuild
[group('deploy')]
usbguard-add host="framework":
    #!/usr/bin/env bash
    set -euo pipefail
    file="modules/computers/{{host}}/_usbguard.nix"
    [[ -f "$file" ]] || { echo "no usbguard module for {{host}} at $file"; exit 1; }
    current="$(nix eval --raw .#nixosConfigurations.{{host}}.config.services.usbguard.rules)"
    new="$(sudo usbguard generate-policy | grep -vFxf <(printf '%s\n' "$current") || true)"
    if [[ -z "${new//[[:space:]]/}" ]]; then
        echo "usbguard: every connected device is already allowed"
        exit 0
    fi
    echo "new device rule(s):"
    echo "$new"
    while IFS= read -r rule; do
        [[ -z "${rule//[[:space:]]/}" ]] && continue
        sudo usbguard allow-device "$rule" \
            || echo "(runtime allow failed — rule still appended; works after rebuild)"
        # insert as a list element above the in-file marker — Nix `''…''`
        # string delimiters (a lone ' is an invalid Nix token), via
        # ENVIRON rather than -v: the rule text's quotes make -v fragile
        export INS="  ''$rule''"
        tmpf=$(mktemp)
        awk '
            /usbguard-add appends new rules above this marker/ { print ENVIRON["INS"] }
            { print }
        ' "$file" > "$tmpf" && mv "$tmpf" "$file"
    done <<< "$new"
    # self-check: an appended rule that breaks eval fails HERE, not at
    # rebuild time (this once shipped a lone-quote string form)
    nix eval --raw .#nixosConfigurations.{{host}}.config.services.usbguard.rules >/dev/null \
        || { echo "appended rule broke the eval — fix $file before rebuilding"; exit 1; }
    echo "appended to $file — review with git diff, then: just rebuild {{host}}"

# Deploy the cache server from the desktop (never rebuild on the box)
[group('deploy')]
deploy-harmonia:
    sudo nixos-rebuild switch --flake .#harmonia --target-host root@192.168.1.82

# Probe the LAN cache: which paths of a closure can .82 serve right now
[group('cache')]
warmth closure="/run/current-system":
    scripts/harmonia-warmth.sh {{closure}}
