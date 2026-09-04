{lib, ...}: {
  _module.args.evalModulesModule = evalModulesArg: let
    cfg = evalModulesArg.config;
  in {
    options = {
      fn = lib.mkOption {type = lib.types.functionTo lib.types.attrs;};
      module = lib.mkOption {type = lib.types.deferredModule;};
      # Modules composed AFTER the merged `module` value (which others
      # may read — e.g. the harmonia VM test imports it directly, so
      # anything test-hostile like nixpkgs.hostPlatform, which the
      # NixOS test framework sets read-only, must live here instead).
      extraModules = lib.mkOption {
        type = lib.types.listOf lib.types.deferredModule;
        default = [];
      };
      # raw, not anything: values like a full pkgs import must not be
      # deep-merged (anything forces every attribute and trips nixpkgs'
      # AAAAAASomeThingsFailToEvaluate guard).
      args = lib.mkOption {type = lib.types.lazyAttrsOf lib.types.raw;};
      configuration = lib.mkOption {
        readOnly = true;
        type = lib.types.attrs;
        default = cfg.fn (cfg.args // {modules = [cfg.module] ++ cfg.extraModules;});
      };
    };
  };
}
