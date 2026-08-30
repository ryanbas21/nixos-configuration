{config, ...}: {
  nixos.configurations.nixos = {
    # The box no longer imports a hardware file from this repo; it composes
    # its own /etc/nixos/hardware-configuration.nix with flake.nixosModules.host
    # via the wrapper flake in scripts/etc-nixos/flake.nix.
    #
    # hostPlatform stays here as host data: nixpkgs.hostPlatform has no
    # default and hardware files only ever set it with mkDefault, so this
    # keeps the repo-side eval (nix flake check) resolvable without fighting
    # the wrapper composition.
    #
    # The stand-in root fs only exists so the repo-side sanity eval passes the
    # `fileSystems does not specify your root file system` assertion; the
    # box's real hardware-configuration.nix defines `/` with plain priority
    # and overrides every field.
    module = {lib, ...}: {
      nixpkgs.hostPlatform = "x86_64-linux";
      system.stateVersion = "26.05";
      fileSystems."/" = {
        device = lib.mkDefault "/dev/disk/by-label/nixos-root";
        fsType = lib.mkDefault "ext4";
      };
      imports = [config.nixos.modules.base config.users.batman.nixos.base];
    };
  };
}
