# Kernel hardening, two halves:
#
# 1. Kernel-surface reduction by module blacklist: esp4/esp6 (IPsec
#    ESP) and rxrpc (kAFS's RPC layer) have zero users on this fleet
#    — VPN is WireGuard, there is no IPsec, no AFS — so they are pure
#    attack surface, and Dirty-Frag-class LPEs have landed in exactly
#    these forgotten modules. A plain blacklist stops manual modprobe
#    but not autoloading (a socket() with the right family can still
#    pull the module in); the `install … false` modprobe stubs close
#    that path too. Pattern from ryan4yin/nix-config, modules/nixos/
#    base/kernel-hardening.nix.
#
# 2. Kernel-image protection and sysctl floors: protectKernelImage
#    (in THIS nixpkgs: "nohibernate" + kexec_load_disabled — nothing
#    more; older folklore credits it kptr_restrict etc., which this
#    tree does NOT do) plus pins for the strong values the fleet
#    already runs on (verified live 2026-09-07 on the framework).
#    They were inherited kernel/nixpkgs defaults, not repo state —
#    without pins, an upstream default change would silently regress
#    them. nohibernate costs nothing here: sleep is s2idle (the
#    pinned mem_sleep_default in framework/_power.nix), never S4.
#
# Base tier — harmonia's minimal base skips it; opt in there only if
# the server ever wants it.
{ inputs, ... }:

let
  # Feature files close over inputs (no specialArgs in this pattern);
  # pkgs is not an argument the deferred-module merge provides.
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
in
{
  nixos.modules.base = {
    security.protectKernelImage = true;

    boot.kernel.sysctl = {
      "kernel.kptr_restrict" = 1;
      "kernel.dmesg_restrict" = 1;
      # 2 (not 1): unprivileged BPF off AND irrevocable at runtime —
      # a compromised process cannot re-enable it even with a cap.
      "kernel.unprivileged_bpf_disabled" = 2;
      "kernel.yama.ptrace_scope" = 1;
      "kernel.perf_event_paranoid" = 2;
    };

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
