{ config, inputs, mkModuleOption, ... }: {
  options.homeManager.modules.base = mkModuleOption { key = "home-manager-base"; };
  config = {
    homeManager.modules.base = { programs.home-manager.enable = true; };
    nixos.modules.base = { pkgs, ... }: {
      imports = [
        inputs.home-manager.nixosModules.home-manager
      ];
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        backupFileExtension = "bak";
        extraSpecialArgs.pkgs = pkgs;

        sharedModules = [
          config.homeManager.modules.base
          inputs.agenix.homeManagerModules.default
          ({ osConfig, ... }: { home.stateVersion = osConfig.system.stateVersion; })
          # The secret inputs of the identity-shaped home activation
          # hooks (batman/agenix.nix importGpgKey, cachix.nix
          # provisionCachix, hypnotix.nix hypnotixProviders). Declared
          # here — machinery — because the feature files are
          # deferredModules, which cannot carry top-level `options`;
          # they assign the REAL (1Password-bound) values, and the
          # fresh-boot VM tests (modules/vm-tests.nix) mkForce them to
          # committed throwaway material so the REAL hooks run in CI
          # without real key material ever leaving 1Password.
          ({ lib, ... }: {
            options.activationSecrets = {
              gpg.file = lib.mkOption {
                type = lib.types.path;
                description = "gpg secret .age imported (and ownertrust-pinned) at activation.";
              };
              gpg.fingerprint = lib.mkOption {
                type = lib.types.str;
                description = "40-char fingerprint: the already-imported check and the ownertrust pin.";
              };
              cachix.authToken = lib.mkOption {
                type = lib.types.path;
                description = "cachix auth-token .age materialized into cachix.dhall at activation.";
              };
              cachix.signingKey = lib.mkOption {
                type = lib.types.path;
                description = "cachix signing-key .age (the BARE secret) materialized into cachix.dhall.";
              };
              hypnotixProviders = lib.mkOption {
                type = lib.types.path;
                description = "hypnotix providers dconf value .age, applied at activation.";
              };
            };
          })
        ];
      };
    };
  };
}
