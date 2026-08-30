# Replicate what nixpkgs.lib.nixosSystem injects for flake-built systems:
# the pinned system flake registry / NIX_PATH (nixpkgs.flake.source) and the
# rev-aware system.nixos.version metadata (lib/flake-version-info.nix).
{
  inputs,
  lib,
  ...
}: {
  nixos.modules.base = {
    # mkDefault so any external composition (e.g. a plain nixosSystem call)
    # can win with its own injected plain-priority definitions instead
    # of relying on value-equality merging.
    nixpkgs.flake.source = lib.mkDefault inputs.nixpkgs.outPath;

    system.nixos = {
      versionSuffix = lib.mkDefault ".${lib.substring 0 8 (inputs.nixpkgs.lastModifiedDate or "19700101")}.${inputs.nixpkgs.shortRev or "dirty"}";
      revision = lib.mkDefault (inputs.nixpkgs.rev or null);
    };
  };
}
