# sudo-rs replaces classic sudo (the nixpkgs module disables
# security.sudo and asserts the two never coexist). System-wide, so it
# assigns to nixos.modules.base rather than a users.<name> slot.
# batman's wheel membership is declared once, statically, in
# modules/users.nix — no need to repeat it here.
{ ... }:

{
  nixos.modules.base = {
    security.sudo-rs.enable = true;
  };
}
