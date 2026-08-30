{config, lib, evalModulesModule, inputs, ...}: {
  options.nixos.configurations = lib.mkOption {
    type = lib.types.lazyAttrsOf (lib.types.submodule ({name, ...}: {
      imports = [evalModulesModule];
      options.name = lib.mkOption {readOnly = true; type = lib.types.str; default = name;};
      config = {
        fn = import "${inputs.nixpkgs}/nixos/lib/eval-config.nix";
        args = {system = "x86_64-linux";};
      };
    }));
  };
  config = {
    flake.nixosConfigurations =
      lib.mapAttrs (name: {configuration, ...}: configuration) config.nixos.configurations;

    # The complete host module (base + users + stateVersion) for external
    # composition: a machine-local wrapper flake (scripts/etc-nixos/flake.nix)
    # builds nixosSystem { modules = [ this ./hardware-configuration.nix ]; }
    # so hardware config lives only on the box.
    flake.nixosModules.host = config.nixos.configurations.nixos.module;

    flake.checks =
      lib.mkMerge (lib.mapAttrsToList (name: {configuration, ...}: {
        "${configuration.config.nixpkgs.hostPlatform.system}"."configurations:nixos:${name}" =
          configuration.config.system.build.toplevel;
      }) config.nixos.configurations);
  };
}
