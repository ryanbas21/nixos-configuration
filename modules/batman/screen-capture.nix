# Kooha screen recorder for batman. home.pc (not home.base): Wayland
# desktop app, no x86_64-darwin package, so it must not reach the
# standalone home-manager exports.
{ ... }:

{
  users.batman.home.pc = { pkgs, ... }: {
    home.packages = [ pkgs.kooha ];
  };
}
