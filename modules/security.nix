# Pareto Security: local security-posture checks (disk encryption,
# firewall, updates, ...) reported via a system daemon. trayIcon off —
# headless posture reporting only. System-wide, so nixos.modules.base.
{ ... }:

{
  nixos.modules.base = {
    services.paretosecurity = {
      enable = true;
      trayIcon = false;
    };
  };
}
