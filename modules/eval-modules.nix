{lib, ...}: {
  _module.args.evalModulesModule = evalModulesArg: let
    cfg = evalModulesArg.config;
  in {
    options = {
      fn = lib.mkOption {type = lib.types.functionTo lib.types.attrs;};
      module = lib.mkOption {type = lib.types.deferredModule;};
      # raw, not anything: values like a full pkgs import must not be
      # deep-merged (anything forces every attribute and trips nixpkgs'
      # AAAAAASomeThingsFailToEvaluate guard).
      args = lib.mkOption {type = lib.types.lazyAttrsOf lib.types.raw;};
      configuration = lib.mkOption {
        readOnly = true;
        type = lib.types.attrs;
        default = cfg.fn (cfg.args // {modules = [cfg.module];});
      };
    };
  };
}
