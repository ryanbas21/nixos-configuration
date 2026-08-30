{config, ...}: {
  nixos.configurations.nixos = {
    # The underscore in ./nixos/_hardware.nix keeps import-tree from
    # auto-importing it as a flake-parts module; it is a NixOS module
    # (imports modulesPath + "/installer/scan/not-detected.nix") and is
    # imported manually here, as the host's data.
    module = {
      nixpkgs.hostPlatform = "x86_64-linux";
      system.stateVersion = "26.05";
      imports = [
        ./nixos/_hardware.nix
        config.nixos.modules.base
        config.users.batman.nixos.base
      ];
    };
  };
}
