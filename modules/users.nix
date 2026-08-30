{lib, mkModuleOption, ...}: {
  options.users = lib.mkOption {
    type = lib.types.lazyAttrsOf (lib.types.submodule (userArgs @ {name, ...}: {
      options = {
        nixos.base = mkModuleOption {
          key = "${name}-nixos-base";
          static = {
            users.users.${name} = {
              isNormalUser = true;
              description = "batman";
              extraGroups = ["networkmanager" "wheel"];
            };
            home-manager.users.${name} = userArgs.config.home.base;
          };
        };
        home.base = mkModuleOption {key = "${name}-home-base";};
      };
    }));
  };
}
