inputs:
inputs.flake-parts.lib.mkFlake {inherit inputs;} {
  imports = [((import inputs.import-tree) ./modules)];
  systems = ["x86_64-linux"];
}
