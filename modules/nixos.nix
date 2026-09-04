{ config, lib, evalModulesModule, inputs, ... }: {

  options.nixos.configurations = lib.mkOption {
    type = lib.types.lazyAttrsOf (lib.types.submodule ({ name, ... }: {
      imports = [ evalModulesModule ];
      options.name = lib.mkOption { readOnly = true; type = lib.types.str; default = name; };
      config = {
        fn = import "${inputs.nixpkgs}/nixos/lib/eval-config.nix";
        # system feeds eval-config's `system ? builtins.currentSystem`
        # parameter default, which explodes under pure flake eval —
        # but it does NOT imply nixpkgs.hostPlatform, which is why
        # hostPlatform rides in extraModules (composed after the merged
        # host module, so host files stay platform-free and importable
        # by the VM tests — see harmonia/vm-test.nix).
        args = { system = "x86_64-linux"; };
        extraModules = [ { nixpkgs.hostPlatform = "x86_64-linux"; } ];
      };
    }));
  };
  config = {
    flake.nixosConfigurations =
      lib.mapAttrs (name: { configuration, ... }: configuration) config.nixos.configurations;

    flake.checks =
      lib.mkMerge (lib.mapAttrsToList
        (name: { configuration, ... }: {
          "${configuration.config.nixpkgs.hostPlatform.system}"."configurations:nixos:${name}" =
            configuration.config.system.build.toplevel;
        })
        config.nixos.configurations);
  };
}
