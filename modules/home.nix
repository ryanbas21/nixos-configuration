# Standalone home-manager machinery: consumes the same user modules as the
# NixOS host (homeManager.modules.base + users.<name>.home.base) and exports
# them as flake.homeConfigurations for non-NixOS machines. The desktop-only
# layer (users.<name>.home.pc: backups, NFS mount) is intentionally NOT
# merged here — it stays NixOS-side via users.<name>.nixos.base.
{config, lib, inputs, evalModulesModule, ...}: {
  options.home.configurations = lib.mkOption {
    type = lib.types.lazyAttrsOf (lib.types.submodule (homeArgs @ {name, ...}: {
      imports = [evalModulesModule];
      options = {
        username = lib.mkOption {type = lib.types.str;};
        system = lib.mkOption {type = lib.types.str;};
        homeDirectory = lib.mkOption {type = lib.types.str;};
      };
      config = {
        fn = inputs.home-manager.lib.homeManagerConfiguration;
        args.pkgs = let
          # x86_64-darwin was dropped from nixpkgs unstable (26.11); the
          # Intel Mac entry builds against the 26.05-darwin stable branch.
          isIntelMac = homeArgs.config.system == "x86_64-darwin";
          nixpkgsInput =
            if isIntelMac
            then inputs.nixpkgs-intel-mac
            else inputs.nixpkgs;
          extraConfig =
            lib.optionalAttrs isIntelMac {
              # 26.05 ships fzf 0.72; fishPlugins.fzf-fish (fzf.fish 11.0)
              # is meta-broken there against that fzf. It is source-only,
              # builds fine, and fzf-fish declares fzf >= 8.2 — warn and
              # move on.
              problems.handlers."fzf.fish".broken = "warn";
            };
        in
          import nixpkgsInput {
            system = homeArgs.config.system;
            config = {allowUnfree = true;} // extraConfig;
          };
        module = {
          imports = [
            config.homeManager.modules.base
            config.users.batman.home.base
          ];
          home = {
            username = homeArgs.config.username;
            homeDirectory = homeArgs.config.homeDirectory;
            # The NixOS-side stateVersion sync module reads
            # osConfig.system.stateVersion and must not land here: osConfig
            # is null under standalone home-manager.
            stateVersion = "26.05";
          };
          # nixpkgs-26.05-darwin (the last x86_64-darwin branch) ships
          # fzf 0.72.0, one minor below home-manager master's 0.73.0 floor
          # for its (default-on) nushell integration. No nushell here.
          programs.fzf.enableNushellIntegration = false;
        };
      };
    }));
  };
  config = {
    flake.homeConfigurations =
      lib.mapAttrs (name: {configuration, ...}: configuration) config.home.configurations;

    home.configurations = {
      ryan-linux = {
        username = "ryan";
        system = "x86_64-linux";
        homeDirectory = "/home/ryan";
      };
      ryan-intel-mac = {
        username = "ryan";
        system = "x86_64-darwin";
        homeDirectory = "/Users/ryan";
      };
    };
  };
}
