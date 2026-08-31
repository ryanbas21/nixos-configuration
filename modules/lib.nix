{lib, ...}: {
  _module.args.mkModuleOption = args @ {key, static ? {}, ...}:
    lib.mkOption {
      type = lib.types.deferredModuleWith {staticModules = [static];};
      apply = module: {inherit key; imports = [module];};
      default = {};
    };

  # Package names (as lib.getName reports them) permitted despite an
  # unfree license. The single source for the
  # nixpkgs.config.allowUnfreePredicate set by modules/nixos/base.nix and
  # by the standalone home-manager exports in modules/home.nix. Verified
  # against meta.license at the locked revisions: everything else in the
  # fleet (ghostty, kodi, psysonic, rigup) is free-licensed. Names are
  # per-derivation (lib.getName), so wrapped packages list their
  # unwrapped halves too.
  _module.args.unfreeNames = [
    "discord"
    "discord-unwrapped"
    "obsidian"
  ];
}
