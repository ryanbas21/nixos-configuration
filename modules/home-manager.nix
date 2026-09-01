{ config, inputs, mkModuleOption, ... }: {
  options.homeManager.modules.base = mkModuleOption { key = "home-manager-base"; };
  config = {
    homeManager.modules.base = { programs.home-manager.enable = true; };
    nixos.modules.base = { ... }: {
      imports = [
        inputs.home-manager.nixosModules.home-manager
      ];
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        backupFileExtension = "bak";
        sharedModules = [
          config.homeManager.modules.base
          inputs.agenix.homeManagerModules.default
          ({ osConfig, ... }: { home.stateVersion = osConfig.system.stateVersion; })
        ];
      };
    };
  };
}
