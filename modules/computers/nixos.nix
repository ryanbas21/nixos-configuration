{config, ...}: {
  nixos.configurations.nixos = {
    module = {
      system.stateVersion = "26.05";
      imports = [config.nixos.modules.base config.users.batman.nixos.base ./../_hardware-configuration.nix];
    };
  };
}
