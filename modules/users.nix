{lib, mkModuleOption, ...}: {
  options.users = lib.mkOption {
    type = lib.types.lazyAttrsOf (lib.types.submodule (userArgs @ {name, ...}: {
      options = {
        nixos.base = mkModuleOption {
          key = "${name}-nixos-base";
          static = {
            users.users.${name} = {
              isNormalUser = true;
              description = name;
              extraGroups = ["networkmanager" "wheel"];
            };
            home-manager.users.${name} = userArgs.config.home.pc;
          };
        };
        home.base = mkModuleOption {key = "${name}-home-base";};
        home.pc = mkModuleOption {
          key = "${name}-home-pc";
          # The desktop variant: everything in home.base plus the
          # machine-bound extras (backups, local paths) that must not leak
          # into standalone home-manager exports.
          static.imports = [userArgs.config.home.base];
        };
      };
    }));
  };
}
