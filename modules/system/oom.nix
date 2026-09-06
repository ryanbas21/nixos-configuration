# Proactive out-of-memory killing, every NixOS host.
#
# zramSwap (system/hardware.nix; harmonia's own module) cushions a
# memory spike — but nothing KILLS the spike's source, so a browser
# eating its way through 32G still freezes the session before the OOM
# reaper gets aggressive. earlyoom watches /proc/meminfo directly (no
# cgroup games, no D-Bus) and SIGTERMs the fattest offender once free
# memory drops below its thresholds — the browser dies, Plasma lives.
# Defaults kept (mem/swap 10%): visible headroom, no premature kills.
#
# Assigned twice (maintenance.nix pattern): harmonia skips the base
# tier but its cache daemon deserves the same mercy.
{ ... }:
{
  nixos.modules.base.services.earlyoom.enable = true;
  nixos.configurations.harmonia.module.services.earlyoom.enable = true;
}
