{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.vulnix-scan = pkgs.writeShellApplication {
        name = "vulnix-scan";
        runtimeInputs = [ pkgs.vulnix ];
        text = ''
          exec vulnix "$@"
        '';
      };
    };
}
