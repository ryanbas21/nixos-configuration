# Day/night screen color temperature via KWin's built-in Night Light.
# home.pc (not home.base): GUI/Wayland-only, must stay off the standalone
# Mac export.
#
# This module's previous incarnation was gammastep, but gammastep cannot
# drive Plasma Wayland: KWin implements neither wlr-gamma-control (the
# wayland method fails to start outright) nor a usable randr gamma path
# over XWayland ("SetCrtcGamma returned error 148"), so the indicator
# crash-looped (exit 255) and raised a failure notification roughly
# twice a day. KWin's Night Light does the same job natively.
#
# Two config files on Plasma 6.7, both edited in place rather than via
# xdg.configFile because they also carry live desktop state that
# Plasma's own GUI rewrites — a declarative whole-file replacement
# would clobber it:
#
#   ~/.config/kwinrc, [NightColor] — the filter itself: Active, Mode
#     (DarkLight = follow the shared sun schedule, Constant = fixed),
#     and the day/night temperatures (gammastep's old 5500/3700K).
#   ~/.config/knighttimerc — knighttimed (org.kde.NightTime): the
#     schedule daemon shared by Night Light and Plasma's automatic
#     dark/light color-scheme switching. Manual Denver coordinates for
#     the same reason gammastep used them: the geolocation chain
#     (geoclue -> beacondb) has no WiFi coverage for this location and
#     its IP fallback misattributes this ISP to Singapore, which put
#     the sun schedule 14 hours off. The machine is a stationary
#     desktop, so these coordinates only need updating if it moves.
#
# Live apply: KConfigWatcher consumers (kwin, knighttimed) listen for
# the org.kde.kconfig.notify ConfigChanged D-Bus signal only — a bare
# kwriteconfig6 write sits unread until the next login. The script
# emits that signal after writing, so a running session picks changes
# up immediately; when no session bus is reachable (activation from a
# non-graphical context) the emit is a no-op and the values apply at
# next login instead.
{ ... }:

{
  users.batman.home.pc = { config, lib, pkgs, ... }:
    let
      # The values the gammastep config carried.
      latitude = "39.7392";
      longitude = "-104.9903";
      dayTemperature = 5500;
      nightTemperature = 3700;

      kwriteconfig6 = "${pkgs.kdePackages.kconfig}/bin/kwriteconfig6";

      # One gdbus ConfigChanged emission per file. The payload names the
      # changed groups; the key lists inside are advisory — consumers
      # re-read the whole file anyway (an empty list works, verified
      # against kwin 6.7 and knighttimed 6.7).
      notify = file: groups:
        let
          payload = "{"
            + lib.concatStringsSep ", "
              (map (g: "'${g}': @aay []") groups)
            + "}";
        in
        "${pkgs.glib}/bin/gdbus emit --session --object-path ${file} --signal org.kde.kconfig.notify.ConfigChanged \"${payload}\"";
    in
    {
      home.activation.nightLight = config.lib.dag.entryAfter [ "writeBoundary" ] ''
      # --- the filter ---
      ${kwriteconfig6} --file kwinrc --group NightColor --key Active true
      ${kwriteconfig6} --file kwinrc --group NightColor --key Mode DarkLight
      ${kwriteconfig6} --file kwinrc --group NightColor --key DayTemperature ${toString dayTemperature}
      ${kwriteconfig6} --file kwinrc --group NightColor --key NightTemperature ${toString nightTemperature}
      ${notify "/kwinrc" [ "NightColor" ]} || true

      # --- the schedule (30-min transitions are knighttimed defaults) ---
      ${kwriteconfig6} --file knighttimerc --group General --key Source Location
      ${kwriteconfig6} --file knighttimerc --group Location --key Automatic false
      ${kwriteconfig6} --file knighttimerc --group Location --key Latitude ${latitude}
      # "--" guards the negative longitude from QCommandLineParser.
      ${kwriteconfig6} --file knighttimerc --group Location --key Longitude -- ${longitude}
      ${notify "/knighttimerc" [ "General" "Location" ]} || true

      # --- retire gammastep, this module's previous incarnation ---
      # The home-manager service disappears with the module; this stops
      # a still-running instance mid-session, clears its failed-state
      # marker, and drops the stale config file.
      systemctl --user stop gammastep.service 2>/dev/null || true
      systemctl --user reset-failed gammastep.service 2>/dev/null || true
      rm -f -- "$HOME/.config/gammastep/config.ini"
    '';
    };
}
