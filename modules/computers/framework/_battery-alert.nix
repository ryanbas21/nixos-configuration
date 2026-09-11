# Low-battery desktop alerts for the laptop (imported from
# framework.nix; the desktop has no battery, and the VM boot tests
# match no BAT* device, so the poll exits clean there).
#
# A one-minute user-session poll of /sys/class/power_supply/BAT*
# that fires notify-send on THRESHOLD TRANSITIONS ONLY — the same
# quiet contract as _ups.nix's rack watcher: ok→low at 20% (normal
# urgency, 5s expiry), →critical at 10% (critical urgency, -t 0 =
# never expires; the dunstrc's global 5s timeout would otherwise
# swallow the one alert that must not be missed), and one
# low-urgency note on recovery (plugged in / back above threshold).
# Charging or full is always "ok" — no nagging while on AC, and a
# missed low alert still lands at the critical one.
#
# Why a home-manager user unit and not a system service like
# _ups.nix: notifications must reach THIS session's daemon — dunst
# under Hyprland (started by the hyprland.start hook, see
# batman/hyprland.nix) or Plasma's own notifier — and only the user
# manager sits on that session bus (systemd user services inherit
# DBUS_SESSION_BUS_ADDRESS from pam_systemd). The timer binds to
# graphical-session.target, which activates under BOTH sessions
# (the very binding hyprland.nix avoids for its daemons; here it's
# the point — notify-send reaches whoever owns the notification
# name) and stops when the session does. Off-session drains (SDDM
# greeter, logged out) are silent by construction: that's ntfy's
# lane (observability.nix), not dunst's.
#
# State: ~/.local/state/battery-watch/level — the user-side
# equivalent of ups-watch's /var/lib/ups-watch/state. The Framework
# 13 has one battery (BAT1); the glob keeps a dual-battery machine
# honest by watching the lowest cell.
{pkgs, ...}: let
  # Framework's 80% charge ceiling (_power.nix) means "low" is
  # measured against real runtime, not the top of a mostly-worn
  # band: 20%/10% on this hardware is roughly an hour / half an
  # hour of sipping, not of sprinting.
  lowPct = 20;
  criticalPct = 10;

  batteryWatch = pkgs.writeShellScript "battery-watch" ''
    state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/battery-watch"
    mkdir -p "$state_dir"
    state_file="$state_dir/level"

    # Lowest capacity across batteries + any-discharging flag. An
    # empty glob (VM) leaves pct empty → clean exit below.
    pct=""
    discharging=0
    for bat in /sys/class/power_supply/BAT*; do
      [ -r "$bat/capacity" ] || continue
      p=$(cat "$bat/capacity")
      if [ -z "$pct" ] || [ "$p" -lt "$pct" ]; then pct=$p; fi
      [ "$(cat "$bat/status" 2>/dev/null)" = Discharging ] && discharging=1
    done
    [ -z "$pct" ] && exit 0

    cur=ok
    if [ "$pct" -le ${toString criticalPct} ]; then cur=critical
    elif [ "$pct" -le ${toString lowPct} ]; then cur=low
    fi
    [ "$discharging" = 0 ] && cur=ok # on AC: never nag

    prev=$(cat "$state_file" 2>/dev/null || echo ok)

    # || true: no notification daemon (crashed dunst, early target
    # race) is a drop, not a failed unit — there is nobody to tell.
    notify() { # urgency, expiry_ms, summary, body
      ${pkgs.libnotify}/bin/notify-send \
        -a Battery -u "$1" -t "$2" -- "$3" "$4" || true
    }

    if [ "$cur" != "$prev" ]; then
      case "$cur" in
        critical)
          notify critical 0 "Battery critical" "''${pct}% left — plug in now." ;;
        low)
          notify normal 5000 "Battery low" "''${pct}% discharging — find power soon." ;;
        ok)
          if [ "$discharging" = 1 ]; then
            notify low 3000 "Battery OK" "back above ${toString lowPct}% (''${pct}%)."
          else
            notify low 3000 "Battery charging" "on external power at ''${pct}%."
          fi ;;
      esac
    fi
    echo "$cur" > "$state_file"
    exit 0
  '';
in {
  home-manager.users.batman.systemd.user = {
    services.battery-watch = {
      Unit.Description = "Low-battery notifier (notify-send to the session daemon)";
      Service = {
        Type = "oneshot";
        ExecStart = batteryWatch;
      };
    };
    timers.battery-watch = {
      Unit = {
        Description = "Poll battery level every minute";
        # Scoped to the graphical session: starts with either
        # Hyprland or Plasma, stops with it — never polls a
        # logged-out seat.
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Install.WantedBy = [ "graphical-session.target" ];
      Timer = {
        OnActiveSec = "30s";
        OnUnitActiveSec = "1min";
      };
    };
  };
}
