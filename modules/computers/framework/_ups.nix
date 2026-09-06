# Rack-UPS awareness for the laptop (imported from framework.nix).
#
# The UPS feeds the network rack only (router, switch, NAS — and the
# hypervisor harmonia runs on; NUT verified serving on
# 192.168.1.30:3493, 2026-09-06). No NixOS host rides it, so the
# classic NUT shutdown choreography is pointless here — when mains
# dies, the DESKTOP dies with it before any UPS event could reach it
# (its outage story is btrfs + noauto NFS automounts + the digest's
# UPS forensics, plus the one-time BIOS "restore AC power state"
# knob). The LAPTOP is the fleet's only outage survivor on its own
# battery — the one host where an OB event is actionable in real
# time: save work, expect the NAS to vanish, become the ops console.
#
# Poll the Synology every 2 minutes; alert on TRANSITIONS only —
# on-battery, and back on mains. Unreachable (off-LAN, NAS down,
# roaming) is SILENT, not a false alarm; no news means no rack event
# AND no reachability claim. The digest's UPS section
# (observability.nix) is the weekly pull-side of this watcher.
#
# ntfy URL from the agenix secret secrets/ntfy-url.age at runtime
# (same pattern as observability.nix — this file cannot import that
# one's helper, so the read is restated).
{ pkgs, ... }:

let
  upsWatch = pkgs.writeShellScript "ups-watch" ''
    state=/var/lib/ups-watch/state
    mkdir -p "$(dirname "$state")"

    status=$(timeout 3 ${pkgs.nut}/bin/upsc ups@192.168.1.30 2>/dev/null \
      | sed -n 's/^ups\.status: //p' | head -n1)
    # Unreachable: not on-battery, not news. Stay silent.
    [ -z "$status" ] && exit 0

    cur=online
    case "$status" in OB*) cur=onbatt ;; esac
    prev=$(cat "$state" 2>/dev/null || echo unknown)

    if [ "$cur" != "$prev" ] && [ "$prev" != unknown ]; then
      ntfyUrl=$(cat /run/agenix/ntfy-url 2>/dev/null || true)
      if [ -n "$ntfyUrl" ] && [ "$cur" = onbatt ]; then
        detail=$(timeout 3 ${pkgs.nut}/bin/upsc ups@192.168.1.30 2>/dev/null \
          | sed -n 's/^battery\.charge: /charge %; /p; s/^battery\.runtime: /runtime s/p' | tr -d '\n')
        ${pkgs.curl}/bin/curl -sf -m 8 --retry 2 --retry-all-errors \
          -H "Title: rack UPS on battery" -H "Priority: high" -H "Tags: electric_plug" \
          -d "rack UPS on battery (ups.status=$status; $detail) — NAS/router on borrowed time; the desktop is already down." \
          "$ntfyUrl/$(hostname)" \
          || ${pkgs.util-linux}/bin/logger -t ups-watch "delivery failed"
      elif [ -n "$ntfyUrl" ]; then
        ${pkgs.curl}/bin/curl -sf -m 8 --retry 2 --retry-all-errors \
          -H "Title: rack UPS back on mains" -H "Priority: default" -H "Tags: plug" \
          -d "rack UPS is back on line power." \
          "$ntfyUrl/$(hostname)" \
          || ${pkgs.util-linux}/bin/logger -t ups-watch "delivery failed"
      else
        ${pkgs.util-linux}/bin/logger -t ups-watch \
          "transition to $cur observed but /run/agenix/ntfy-url is missing"
      fi
    fi
    echo "$cur" > "$state"
    exit 0
  '';
in
{
  systemd.services.ups-watch = {
    description = "Rack UPS transition watcher (Synology NUT)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = upsWatch;
    };
  };
  systemd.timers.ups-watch = {
    description = "Poll rack UPS every 2 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "2min";
    };
  };
}
