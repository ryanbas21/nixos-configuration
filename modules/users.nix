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
            # Activation can legitimately block for minutes inside
            # reloadSystemd when a changed oneshot unit gets restarted
            # in-switch (2026-09-04: borgmatic's "sleep 3m" + backup
            # outran the 5min default start timeout and false-failed
            # the switch — while the backup actually succeeded and the
            # follow-up run completed everything). 15min tolerates that
            # class of wait instead of reporting phantom failures.
            systemd.services."home-manager-${name}".serviceConfig.TimeoutStartSec = lib.mkForce "15min";
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
