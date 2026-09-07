# Kernel-surface reduction by module blacklist: esp4/esp6 (IPsec ESP)
# and rxrpc (kAFS's RPC layer) have zero users on this fleet — VPN is
# WireGuard, there is no IPsec, no AFS — so they are pure attack
# surface, and Dirty-Frag-class LPEs have landed in exactly these
# forgotten modules. A plain blacklist stops manual modprobe but not
# autoloading (a socket() with the right family can still pull the
# module in); the `install … false` modprobe stubs close that path
# too. Pattern from ryan4yin/nix-config, modules/nixos/base/
# kernel-hardening.nix. Base tier — harmonia's minimal base skips it;
# opt in there only if the server ever wants it.
{ inputs, ... }:

let
  # Feature files close over inputs (no specialArgs in this pattern);
  # pkgs is not an argument the deferred-module merge provides.
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
in
{
  nixos.modules.base = {
    boot.blacklistedKernelModules = [
      "esp4"
      "esp6"
      "rxrpc"
    ];

    boot.extraModprobeConfig = ''
      install esp4 ${pkgs.coreutils}/bin/false
      install esp6 ${pkgs.coreutils}/bin/false
      install rxrpc ${pkgs.coreutils}/bin/false
    '';
  };
}
