# Hyprland for batman, living next to Plasma as an SDDM session choice
# (enabled system-side in modules/nixos/base.nix).
#
# home.pc (not home.base): a Wayland compositor config is desktop-only
# and would drag the whole hyprland package into the standalone
# home-manager exports otherwise (same reasoning as screen-capture.nix).
#
# Design notes, because this file makes two deliberate blends:
#
# 1. KEYBINDS follow the xmonad config in the ryanbas21/dotfiles repo
#    (input ryan-nvim), not Hyprland defaults — the goal was "hyprland
#    like my xmonad": SUPER as $mainMod (Hyprland's convention;
#    xmonad itself used mod1Mask/ALT, but the chords are identical
#    apart from the modifier, and SUPER leaves Alt free for
#    terminal/editor chords), M-h/l shrink
#    and grow the master split (xmonad Shrink/Expand), M-j/k cycle the
#    stack, M-[/] cycle workspaces, M-S-1..0 move windows without
#    following, media keys on pactl-style tools. Where xmonad has no
#    Hyprland equivalent (Accordion layout) the bind is simply dropped.
#    M-w (xmonad's "Tabbed Simplest") maps to Hyprland *groups*, which
#    are the tabbed-window equivalent.
#
# 2. LOOK follows the summer-day-and-night rice (input
#    summer-day-and-night, everforest dark) — borders, rounding,
#    shadows, waybar/wofi styling. The rice's day/night switch-theme.sh
#    is NOT ported: it live-rewrites VS Code/Obsidian/Firefox state via
#    sed and sqlite3, which fights this repo's declarative setup. The
#    everforest dark variant is baked in statically.
#
# Session daemons (waybar, dunst, hyprpaper, gammastep) are started by
# an hl.on("hyprland.start") hook, NOT home-manager systemd services:
# HM services bind to graphical-session.target, which also activates
# inside the Plasma session — dunst would fight Plasma's notification
# daemon and gammastep cannot drive KWin at all (see
# time-of-day-gamma.nix for that whole saga). The start hook scopes
# them to Hyprland only. On Hyprland
# gammastep works again — it speaks wlr-gamma-control, which KWin
# refuses to implement but Hyprland does — so this restores the
# 5500/3700 K day/night schedule the Plasma session gets via KWin
# Night Light.
{ inputs, ... }:

{
  users.batman.home.pc = { config, lib, pkgs, ... }:
    let
      # Everforest (medium, dark) palette, single source for the hypr
      # conf, hyprlock, waybar and wofi styling below. Values are the
      # rice's hypr/colors/everforest.conf (alpha-prefixed 0xRRGGBBAA
      # form only where Hyprland wants it; CSS spots use the # form).
      everforest = rec {
        bg_dim = "232a2e";
        bg0 = "2d353b";
        bg1 = "343f44";
        bg2 = "3d484d";
        bg3 = "475258";
        bg4 = "4f585e";
        bg5 = "56635f";
        bg_red = "514045";
        fg = "d3c6aa";
        red = "e67e80";
        orange = "e69875";
        yellow = "dbbc7f";
        green = "a7c080";
        aqua = "83c092";
        blue = "7fbbb3";
        purple = "d699b6";
        grey0 = "7a8478";
        grey1 = "859289";
        grey2 = "9da9a0";
        # The accent the rice draws under bar and launcher (a darker
        # everforest-yellow; it reads as a drop shadow on the light bg).
        accent = "7d6a40";
      };

      wallpaper = "${inputs.summer-day-and-night}/wallpapers/summer-night.png";

      # Icon glyphs for waybar/wofi/the power menu: FontAwesome
      # private-use codepoints, all present in JetBrainsMono Nerd Font.
      # They are written as JSON \u escapes and decoded here because
      # PUA characters are easy to lose in editor/tooling transit — the
      # first cut of this file shipped empty format strings, which waybar
      # renders as an absent module (the invisible power button).
      glyph = code: builtins.fromJSON ''"\u${code}"'';

      # --- Lua config helpers (configType = "lua"): home-manager's
      # Lua renderer emits hl.<key>(...) per settings key, and raw Lua
      # enters it through mkLuaInline — the hl.dsp.* dispatchers are
      # runtime objects, not serializable values. _args turns an
      # attrset into a multi-argument call (hl.bind's
      # key/dispatcher/flags triple).
      raw = lib.generators.mkLuaInline;
      dsp = s: raw "hl.dsp.${s}";
      bind = key: action: { _args = [ key action ]; };
      bindOpts = key: action: opts: { _args = [ key action opts ]; };
      # everforest hex + opaque alpha, as an rgba() color string.
      rgba = c: "rgba(${c}ff)";

      # The rice's switch-layout behaviour, reduced to what stock
      # Hyprland offers: xmonad's NextLayout (M-e) cycled
      # Tall/Mirror/Tabbed/Accordion; Hyprland only has two real
      # layouts (master ≈ xmonad Tall, dwindle = spiral), so M-e
      # toggles between them. `hyprctl keyword` changes are runtime
      # only — a config reload (M-S-r) resets to master, which is fine
      # for a toggle.
      cycleLayout = pkgs.writeShellScript "hypr-cycle-layout" ''
        current=$(hyprctl getoption general:layout -j | ${lib.getExe pkgs.jq} -r '.str')
        if [ "$current" = "dwindle" ]; then
          hyprctl keyword general:layout master
        else
          hyprctl keyword general:layout dwindle
        fi
      '';

      # The rice's wofi power menu, minus the rofi-theme plumbing: a
      # plain wofi --dmenu list. `hyprctl dispatch exit` lands back on
      # SDDM, where the Plasma session stays one click away.
      powerMenu = pkgs.writeShellScript "hypr-powermenu" ''
        entry=$(printf '%s\n' '${glyph "f023"} Lock' '${glyph "f08b"} Log out' '${glyph "f186"} Suspend' '${glyph "f021"} Reboot' '${glyph "f011"} Shutdown' \
          | wofi --dmenu --prompt 'Power' -i)
        case "$entry" in
          *Lock*)     hyprlock ;;
          *Log*)      hyprctl dispatch 'hl.dsp.exit()' ;;
          *Suspend*)  systemctl suspend ;;
          *Reboot*)   systemctl reboot ;;
          *Shutdown*) systemctl poweroff ;;
        esac
      '';

      # grim+slurp screenshots replacing xmonad's flameshot binds
      # (F12 region / Shift+F12 full). Both copy to the clipboard and
      # drop a file under ~/Pictures/Screenshots, reported through
      # dunst (notify-send).
      screenshot = kind: pkgs.writeShellScript "hypr-shot-${kind}" ''
        dir="$HOME/Pictures/Screenshots"
        mkdir -p "$dir"
        file="$dir/Screenshot_$(date +%Y-%m-%d_%H%M%S).png"
        ${
          if kind == "region"
          then ''grim -g "$(slurp)" "$file"''
          else ''grim "$file"''
        } && wl-copy < "$file" \
          && notify-send -t 2000 "Screenshot" "Saved to $file"
      '';
    in
    {
      home.packages = with pkgs; [
        # The rice stack around the compositor: launcher, screenshots,
        # clipboard, brightness, and the daemons exec-once'd below.
        # hyprpaper/dunst/gammastep are installed here too — the
        # configs alone (xdg.configFile below) don't install binaries,
        # and without these the exec-once lines died with
        # command-not-found on first boot (no wallpaper, notifications,
        # or gamma: only waybar survived).
        wofi
        hyprpaper
        dunst
        gammastep
        grim
        slurp
        wl-clipboard
        cliphist
        brightnessctl
        networkmanagerapplet # tray applet under waybar (xmonad's nm-applet)
        pavucontrol
        libnotify # notify-send for the screenshot scripts
        jq # hypr-cycle-layout parses `hyprctl getoption -j`
        # Waybar/wofi/ghostty glyphs need the nerd font cut; without
        # fonts.fontconfig.enable the home-profile copy is invisible.
        nerd-fonts.jetbrains-mono
      ];

      fonts.fontconfig.enable = true;

      wayland.windowManager.hyprland = {
        enable = true;
        # The Lua config backend (hyprland.lua, the hl.* API): the
        # format Hyprland 0.55+ develops against — hyprlang is
        # deprecated and slated for removal, so this module speaks
        # Lua natively rather than pinning the legacy format.
        # Home-manager renders each settings key as an hl.<name>(...)
        # call: lists become one call per element, `{ _args = [...]; }`
        # becomes a multi-argument call (how hl.bind's key/dispatcher/
        # flags triple is expressed), and lib.generators.mkLuaInline
        # (the `raw` helper in the let above) splices raw Lua for the
        # hl.dsp.* dispatcher objects, which are runtime values no
        # serializer can emit. Dispatcher spellings below are verified
        # against the wiki's dispatcher/master-layout tables and
        # src/config/lua/bindings/LuaBindingsDispatchers.cpp (notably
        # window.move's `follow = false` == the old movetoworkspace
        # `silent`, i.e. xmonad's W.shift).
        configType = "lua";

        settings = {
          # Session daemons — launched on hyprland.start, not HM
          # services, so they never leak into the Plasma session (see
          # module header). HM injects its own systemd activation hook
          # (hyprland-session.target) separately from this.
          on = [
            {
              _args = [
                "hyprland.start"
                (raw ''
                  function()
                    hl.exec_cmd("waybar")
                    hl.exec_cmd("dunst")
                    hl.exec_cmd("hyprpaper")
                    hl.exec_cmd("gammastep")
                    hl.exec_cmd("nm-applet --indicator")
                    hl.exec_cmd("${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1")
                    hl.exec_cmd("wl-paste --type text --watch cliphist store")
                    hl.exec_cmd("wl-paste --type image --watch cliphist store")
                  end
                '')
              ];
            }
          ];

          env = [
            { _args = [ "MOZ_ENABLE_WAYLAND" "1" ]; }
            { _args = [ "_JAVA_AWT_WM_NONREPARENTING" "1" ]; }
            # Match the Plasma session's cursor/Qt theming so apps
            # feel at home; Breeze is installed system-wide via
            # plasma6.
            { _args = [ "XCURSOR_THEME" "Breeze" ]; }
            { _args = [ "XCURSOR_SIZE" "24" ]; }
            { _args = [ "QT_QPA_PLATFORMTHEME" "kde" ]; }
          ];

          monitor = [{ output = ""; mode = "preferred"; position = "auto"; }];

          # Config sections, one hl.config({...}) call. Fields match
          # the generated Lua stubs in the hyprland package
          # (share/hypr/stubs/hl.meta.lua).
          config = [
            {
              general = {
                # xmonad: 20px screen gaps + 6px window spacing.
                gaps_in = 6;
                gaps_out = 20;
                border_size = 4;
                # everforest: cream active border, mossy inactive.
                col = {
                  active_border = rgba everforest.fg;
                  inactive_border = rgba everforest.bg5;
                };
                # The xmonad-like master+stack comes first; SUPER+E
                # flips to dwindle at runtime.
                layout = "master";
                resize_on_border = true;
              };
              decoration = {
                rounding = 10;
                blur.enabled = false;
                # The rice's signature flat "3D" bottom edge: a shadow
                # pinned below the window (range 0, offset y+10).
                shadow = {
                  enabled = true;
                  range = 0;
                  render_power = 4;
                  color = rgba everforest.accent;
                  color_inactive = "rgba(2b312fff)";
                  scale = 1.0;
                  # Vec2Like parses positional pairs only — {x=,y=}
                  # keyed tables trip "vec2 type requires exactly
                  # 2 elements" despite the stub alias allowing both.
                  offset = [ 0 10 ];
                };
              };
              master = {
                # xmonad Tall: master 2/3 of the screen; new windows
                # join the stack ("slave"), not the master pane.
                mfact = 0.67;
                new_status = "slave";
              };
              dwindle.preserve_split = true;
              group.col = {
                border_active = rgba everforest.bg5;
                border_inactive = rgba everforest.fg;
              };
              input = {
                kb_layout = "us";
                numlock_by_default = true;
                follow_mouse = 1;
                touchpad.natural_scroll = true;
              };
              misc = {
                # xmonad's focus follows activation — jump to windows
                # that ask for attention.
                focus_on_activate = true;
                # Belt-and-braces behind hyprpaper: never fall back to
                # the built-in mascot wallpapers / logo if hyprpaper
                # is slow or dead.
                force_default_wallpaper = 0;
                disable_hyprland_logo = true;
              };
              ecosystem = {
                # 0.56 renders a Windows-style "Go to settings to
                # activate Hyprland" donation nag over the wallpaper
                # until switched off — the documented off switch.
                no_donation_nag = true;
              };
            }
          ];

          # Animation curves: hl.curve(name, {type="bezier", points}),
          # then hl.animation({leaf=..., speed=..., bezier=...,
          # style=...}) per animation.
          curve = [
            { _args = [ "slow" { type = "bezier"; points = [ [ 0 0.85 ] [ 0.3 1 ] ]; } ]; }
            { _args = [ "overshot" { type = "bezier"; points = [ [ 0.7 0.6 ] [ 0.1 1.1 ] ]; } ]; }
            { _args = [ "bounce" { type = "bezier"; points = [ [ 1 1.6 ] [ 0.1 0.85 ] ]; } ]; }
          ];
          animation = [
            { leaf = "windows"; enabled = true; speed = 5; bezier = "bounce"; style = "popin"; }
            { leaf = "border"; enabled = true; speed = 20; bezier = "default"; }
            { leaf = "fade"; enabled = true; speed = 5; bezier = "overshot"; }
            { leaf = "workspaces"; enabled = true; speed = 6; bezier = "overshot"; style = "slidevert"; }
            { leaf = "windowsIn"; enabled = true; speed = 5; bezier = "slow"; style = "popin"; }
          ];

          # Window rules: the xmonad ManageHook (firefox → ws2, Gimp
          # float) plus the rice's utility floats and vicinae's
          # launcher popup.
          window_rule = [
            { name = "firefox-to-ws2"; match.class = "^firefox$"; workspace = "2"; }
            { name = "gimp-float"; match.class = "^gimp$"; float = true; }
            { name = "pavucontrol-float"; match.class = "^pavucontrol$"; float = true; center = true; size = [ 600 800 ]; }
            { name = "calculator-float"; match.class = "^org\\.gnome\\.Calculator$"; float = true; size = [ 490 600 ]; }
            { name = "blueman-float"; match.class = "^blueman-manager$"; float = true; }
            { name = "dialog-replace"; match.title = "^Confirm to replace files$"; float = true; }
            { name = "dialog-progress"; match.title = "^File Operation Progress$"; float = true; }
            { name = "steam-news"; match.title = "^Steam - News$"; float = true; }
            { name = "vicinae-float"; match.class = "^vicinae$"; float = true; center = true; }
          ];

          # The rice's no-anim slurp overlay — now expressible again:
          # the Lua layerrule form is documented, unlike 0.56's
          # hyprlang field/value pairs.
          layer_rule = [
            { name = "no-anim-selection"; match.namespace = "^selection$"; no_anim = true; }
          ];

          # --- keybinds: the xmonad translation (see module header) ---
          bind = [
            # Launchers (xmonad: M-Return ghostty, M-Space launcher,
            # M-Tab window switcher). Vicinae's daemon is systemd-
            # managed by its own module; `vicinae open` just raises it.
            (bind "SUPER + Return" (dsp ''exec_cmd("ghostty")''))
            (bind "SUPER + Space" (dsp ''exec_cmd("vicinae open")''))
            (bind "SUPER + Tab" (dsp ''exec_cmd("pkill wofi || wofi --show window")''))
            # xmonad had fullscreen on M-f and the browser on M4-f —
            # two different mods. On a single SUPER mod they collide,
            # so fullscreen keeps F and the browser takes B.
            (bind "SUPER + B" (dsp ''exec_cmd("firefox")''))

            # Focus: SUPER+J/K cycle the stack (xmonad focusDown/Up —
            # the master layout's cyclenext/cycleprev), SUPER+M the
            # master; arrows are Hyprland-directional.
            (bind "SUPER + J" (dsp ''layout("cyclenext")''))
            (bind "SUPER + K" (dsp ''layout("cycleprev")''))
            (bind "SUPER + M" (dsp ''layout("focusmaster")''))
            (bind "SUPER + left" (dsp ''focus({ direction = "left" })''))
            (bind "SUPER + right" (dsp ''focus({ direction = "right" })''))
            (bind "SUPER + up" (dsp ''focus({ direction = "up" })''))
            (bind "SUPER + down" (dsp ''focus({ direction = "down" })''))

            # Swap: SUPER+Shift+J/K (xmonad swapDown/Up — directional
            # in the Lua API), SUPER+Shift+period swaps with master
            # (xmonad swapMaster).
            (bind "SUPER + SHIFT + J" (dsp ''window.swap({ direction = "down" })''))
            (bind "SUPER + SHIFT + K" (dsp ''window.swap({ direction = "up" })''))
            (bind "SUPER + SHIFT + period" (dsp ''layout("swapwithmaster")''))
            (bind "SUPER + SHIFT + left" (dsp ''window.move({ direction = "left" })''))
            (bind "SUPER + SHIFT + right" (dsp ''window.move({ direction = "right" })''))
            (bind "SUPER + SHIFT + up" (dsp ''window.move({ direction = "up" })''))
            (bind "SUPER + SHIFT + down" (dsp ''window.move({ direction = "down" })''))

            # Master pane geometry (xmonad Shrink/Expand = M-h/l,
            # IncMasterN = M-,/M-.).
            (bind "SUPER + H" (dsp ''layout("mfact -0.05")''))
            (bind "SUPER + L" (dsp ''layout("mfact +0.05")''))
            (bind "SUPER + comma" (dsp ''layout("addmaster")''))
            (bind "SUPER + period" (dsp ''layout("removemaster")''))

            # Layouts & window state: SUPER+E cycles layouts, SUPER+W
            # tabbed groups, SUPER+F fullscreen (layout-aware, like
            # xmonad's Toggle NBFULL), SUPER+T float (xmonad sink),
            # SUPER+G hides the bar (xmonad ToggleStruts).
            (bind "SUPER + E" (dsp ''exec_cmd("${cycleLayout}")''))
            (bind "SUPER + W" (dsp ''group.toggle()''))
            (bind "SUPER + F" (dsp ''window.fullscreen({ mode = "fullscreen" })''))
            (bind "SUPER + T" (dsp ''window.float({ action = "toggle" })''))
            (bind "SUPER + SHIFT + Q" (dsp ''window.close()''))
            (bind "SUPER + G" (dsp ''exec_cmd("pkill -SIGUSR1 waybar")''))

            # Workspaces: SUPER+1..0 → 1..10; SUPER+Shift+1..0 moves
            # without following (follow=false, xmonad W.shift);
            # SUPER+[/] cycles existing (xmonad nextWS/prevWS).
            (bind "SUPER + 1" (dsp ''focus({ workspace = 1 })''))
            (bind "SUPER + 2" (dsp ''focus({ workspace = 2 })''))
            (bind "SUPER + 3" (dsp ''focus({ workspace = 3 })''))
            (bind "SUPER + 4" (dsp ''focus({ workspace = 4 })''))
            (bind "SUPER + 5" (dsp ''focus({ workspace = 5 })''))
            (bind "SUPER + 6" (dsp ''focus({ workspace = 6 })''))
            (bind "SUPER + 7" (dsp ''focus({ workspace = 7 })''))
            (bind "SUPER + 8" (dsp ''focus({ workspace = 8 })''))
            (bind "SUPER + 9" (dsp ''focus({ workspace = 9 })''))
            (bind "SUPER + 0" (dsp ''focus({ workspace = 10 })''))
            (bind "SUPER + SHIFT + 1" (dsp ''window.move({ workspace = 1, follow = false })''))
            (bind "SUPER + SHIFT + 2" (dsp ''window.move({ workspace = 2, follow = false })''))
            (bind "SUPER + SHIFT + 3" (dsp ''window.move({ workspace = 3, follow = false })''))
            (bind "SUPER + SHIFT + 4" (dsp ''window.move({ workspace = 4, follow = false })''))
            (bind "SUPER + SHIFT + 5" (dsp ''window.move({ workspace = 5, follow = false })''))
            (bind "SUPER + SHIFT + 6" (dsp ''window.move({ workspace = 6, follow = false })''))
            (bind "SUPER + SHIFT + 7" (dsp ''window.move({ workspace = 7, follow = false })''))
            (bind "SUPER + SHIFT + 8" (dsp ''window.move({ workspace = 8, follow = false })''))
            (bind "SUPER + SHIFT + 9" (dsp ''window.move({ workspace = 9, follow = false })''))
            (bind "SUPER + SHIFT + 0" (dsp ''window.move({ workspace = 10, follow = false })''))
            (bind "SUPER + bracketleft" (dsp ''focus({ workspace = "e-1" })''))
            (bind "SUPER + bracketright" (dsp ''focus({ workspace = "e+1" })''))
            (bind "SUPER + SHIFT + bracketleft" (dsp ''window.move({ workspace = "e-1", follow = false })''))
            (bind "SUPER + SHIFT + bracketright" (dsp ''window.move({ workspace = "e+1", follow = false })''))

            # Session: SUPER+Shift+R reload (xmonad restart),
            # SUPER+Shift+E exits to SDDM (xmonad quit), SUPER+Shift+X
            # locks (hyprlock — under Hyprland that job belongs to it
            # directly), SUPER+Shift+P power menu.
            (bind "SUPER + SHIFT + R" (dsp ''exec_cmd("hyprctl reload")''))
            (bind "SUPER + SHIFT + E" (dsp ''exit()''))
            (bind "SUPER + SHIFT + X" (dsp ''exec_cmd("hyprlock")''))
            (bind "SUPER + SHIFT + P" (dsp ''exec_cmd("${powerMenu}")''))

            # Screenshots (xmonad F12/S-F12 flameshot; grim+slurp are
            # the Wayland equivalents).
            (bind "F12" (dsp ''exec_cmd("${screenshot "region"}")''))
            (bind "SHIFT + F12" (dsp ''exec_cmd("${screenshot "full"}")''))
            (bind "SUPER + Print" (dsp ''exec_cmd("${screenshot "full"}")''))

            # Clipboard history (the rice's M-V menu).
            (bind "SUPER + V" (dsp ''exec_cmd("cliphist list | wofi --dmenu | cliphist decode | wl-copy")''))

            # Workspace cycling on the wheel (the rice).
            (bind "SUPER + mouse_down" (dsp ''focus({ workspace = "e-1" })''))
            (bind "SUPER + mouse_up" (dsp ''focus({ workspace = "e+1" })''))

            # Media/hardware keys: repeating while held and active on
            # the lock screen too. wpctl ships with the pipewire the
            # base module enables (pactl would need the pulseaudio
            # package pulled in just for the CLI).
            (bindOpts "XF86AudioRaiseVolume" (dsp ''exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 10%+")'') { locked = true; repeating = true; })
            (bindOpts "XF86AudioLowerVolume" (dsp ''exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 10%-")'') { locked = true; repeating = true; })
            (bindOpts "XF86AudioMute" (dsp ''exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")'') { locked = true; repeating = true; })
            (bindOpts "XF86AudioMicMute" (dsp ''exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle")'') { locked = true; repeating = true; })
            (bindOpts "XF86MonBrightnessUp" (dsp ''exec_cmd("brightnessctl set +10%")'') { locked = true; repeating = true; })
            (bindOpts "XF86MonBrightnessDown" (dsp ''exec_cmd("brightnessctl set 10%-")'') { locked = true; repeating = true; })

            # Move/resize with SUPER + LMB/RMB dragging (xmonad's
            # mod-button1/3 mouseActions).
            (bindOpts "SUPER + mouse:272" (dsp ''window.drag()'') { mouse = true; })
            (bindOpts "SUPER + mouse:273" (dsp ''window.resize()'') { mouse = true; })

            # Resize submap entry (xmonad had none — bonus bind).
            (bind "SUPER + R" (dsp ''submap("resize")''))
          ];
        };

        # The rice's resize submap. Entry bind (SUPER+R) lives in
        # settings.bind above; home-manager wraps these in
        # hl.define_submap("resize", function() ... end) — binds
        # registered inside only fire while the submap is active,
        # until hl.dsp.submap("reset") returns to the default map.
        submaps.resize.settings = {
          bind = [
            { _args = [ "escape" (dsp ''submap("reset")'') ]; }
            { _args = [ "right" (dsp ''window.resize({ x = 15, y = 0, relative = true })'') { repeating = true; } ]; }
            { _args = [ "left" (dsp ''window.resize({ x = -15, y = 0, relative = true })'') { repeating = true; } ]; }
            { _args = [ "up" (dsp ''window.resize({ x = 0, y = -15, relative = true })'') { repeating = true; } ]; }
            { _args = [ "down" (dsp ''window.resize({ x = 0, y = 15, relative = true })'') { repeating = true; } ]; }
          ];
        };
      };

      # Hyprland's emergency fallback: when a session on the legacy
      # config manager reloads and finds no hyprland.conf (e.g. mid-
      # session switch to the Lua config), it WRITES a stub config
      # ("This config is a STUB!", SUPER+Q→kitty, SUPER+M→exit) as a
      # regular file — which then shadows hyprland.lua at next login
      # (happened on the lua migration: the running hyprlang session
      # reloaded after HM had already swapped the symlink). Sweep it
      # on every activation; only regular files, never HM symlinks.
      home.activation.hyprlandSweepLegacyConf = config.lib.dag.entryAfter [ "writeBoundary" ] ''
        if [ -f "$HOME/.config/hypr/hyprland.conf" ] && [ ! -L "$HOME/.config/hypr/hyprland.conf" ]; then
          rm -f -- "$HOME/.config/hypr/hyprland.conf"
        fi
      '';

      # Session-scoped daemons configured as plain files — the HM
      # service modules would also run them under Plasma (see header).
      xdg.configFile = {
        "hypr/hyprpaper.conf".text = ''
          # hyprpaper 0.8 was rewritten on hyprtoolkit and broke the
          # old grammar: `preload`/`wallpaper = ,path` lines are now
          # unknown keys ("Config has errors", no wallpaper, monitor
          # left with "no target"). Wallpapers are anonymous wallpaper
          # {} blocks; the empty monitor is still the all-monitors
          # wildcard, and fit_mode is cover by default.
          wallpaper {
            monitor =
            fit_mode = cover
            path = ${wallpaper}
          }

          splash = false
        '';

        "gammastep/config.ini".text = ''
          [general]
          temp-day=5500
          temp-night=3700
          transition=1
          location-provider=manual
          [manual]
          lat=39.7392
          lon=-104.9903
        '';

        # dunst, everforest-flavoured: top-right, clear of the bar.
        "dunst/dunstrc".text = ''
          [global]
            origin = top-right
            offset = 20x60
            width = 350
            gap_size = 6
            padding = 12
            frame_width = 2
            corner_radius = 10
            frame_color = "#${everforest.accent}"
            separator_color = frame
            font = JetBrainsMono Nerd Font 11
            icon_position = left
            timeout = 5

          [urgency_low]
            background = "#${everforest.bg0}"
            foreground = "#${everforest.fg}"

          [urgency_normal]
            background = "#${everforest.bg0}"
            foreground = "#${everforest.fg}"

          [urgency_critical]
            background = "#${everforest.bg_red}"
            foreground = "#${everforest.red}"
            frame_color = "#${everforest.red}"
        '';

        # wofi auto-loads config + style.css from ~/.config/wofi.
        "wofi/config".text = ''
          mode=drun
          allow_images=true
          image_size=40
          term=ghostty
          insensitive=true
          location=center
          no_actions=true
          prompt=Search
          width=600
          height=500
        '';

        "wofi/style.css".text = with everforest; ''
          @define-color bg_dim #${bg_dim};
          @define-color bg0 #${bg0};
          @define-color fg #${fg};
          @define-color green #${green};
          @define-color accent #${accent};

          * {
            font-family: JetBrainsMono Nerd Font, FontAwesome;
            font-size: 17px;
            border: none;
            border-radius: 10px;
          }

          window {
            margin: 0px;
            background-color: @fg;
            color: @bg0;
            border-radius: 15px;
            border-bottom: 5px solid @accent;
          }

          #input {
            background-color: @green;
            color: @bg0;
            margin: 15px;
            padding: 10px;
            border-bottom: 5px solid #556a35;
          }

          #inner-box {
            margin: 20px;
            background-color: transparent;
          }

          #entry {
            padding: 10px;
          }

          #entry:selected {
            background-color: @bg0;
            color: @fg;
            border-bottom: 5px solid #161a1d;
          }

          #text {
            margin-left: 15px;
            margin-right: 15px;
          }
        '';
      };

      programs.hyprlock = {
        enable = true;
        settings = {
          general = {
            disable_loading_bar = true;
            grace = 5;
          };
          background = {
            monitor = "";
            path = wallpaper;
            blur_passes = 2;
            blur_size = 6;
          };
          input-field = {
            monitor = "";
            size = "300 50";
            outline_thickness = 2;
            dots_size = 0.2;
            fade_timeout = 2000;
            position = "0, -150";
            halign = "center";
            valign = "center";
            "col.outer_frame" = "rgb(${everforest.accent})";
          };
          label = [
            {
              monitor = "";
              text = "$TIME";
              font_size = 90;
              position = "0, 100";
              halign = "center";
              valign = "center";
              color = "rgb(${everforest.fg})";
            }
            {
              monitor = "";
              text = "hi, batman";
              font_size = 20;
              position = "0, 30";
              halign = "center";
              valign = "center";
              color = "rgb(${everforest.grey1})";
            }
          ];
        };
      };

      programs.waybar = {
        enable = true;
        # mainBar is the key home-manager maps to the plain
        # ~/.config/waybar/config (any other name would produce
        # config-<name>).
        settings.mainBar = {
          layer = "top";
          position = "top";
          height = 50;
          margin-top = 0;
          margin-bottom = 0;
          margin-left = 100;
          margin-right = 100;
          spacing = 15;

          modules-left = [ "custom/launcher" "clock" "clock#date" ];
          modules-center = [ "wlr/workspaces" ];
          modules-right = [ "tray" "pulseaudio" "network" "custom/powermenu" ];

          "wlr/workspaces" = {
            disable-scroll = true;
            all-outputs = true;
            on-click = "activate";
            format = "{icon}";
            format-icons = {
              "1" = "一";
              "2" = "二";
              "3" = "三";
              "4" = "四";
              "5" = "五";
              "6" = "六";
              "7" = "七";
              "8" = "八";
              "9" = "九";
              "10" = "十";
            };
          };

          clock.format = "${glyph "f017"} {:%H:%M}";
          "clock#date".format = "${glyph "f073"} {:%A, %B %d}";

          "custom/launcher" = {
            format = "❯";
            on-click = "vicinae open";
            tooltip = false;
          };

          "custom/powermenu" = {
            format = glyph "f011";
            on-click = "${powerMenu}";
            tooltip = false;
          };

          pulseaudio = {
            format = "{icon} {volume}%";
            format-muted = "${glyph "f026"} muted";
            format-icons.default = [
              (glyph "f026")
              (glyph "f027")
              (glyph "f028")
            ];
            on-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
            on-click-right = "pavucontrol";
          };

          network = {
            format-wifi = "${glyph "f1eb"} {signalStrength}%";
            format-ethernet = "${glyph "f796"} wired";
            format-disconnected = glyph "f127";
            tooltip = false;
          };

          tray = {
            icon-size = 20;
            spacing = 8;
          };
        };

        # The rice's everforest bar: floating pills with the accent
        # underline. Everforest palette inlined via @define-color so
        # this file is self-contained.
        style = with everforest; ''
          @define-color bg0 #${bg0};
          @define-color bg1 #${bg1};
          @define-color fg #${fg};
          @define-color red #${red};
          @define-color green #${green};
          @define-color blue #${blue};
          @define-color accent #${accent};

          * {
            font-family: JetBrainsMono Nerd Font, FontAwesome;
            font-size: 16px;
            font-weight: bold;
          }

          window#waybar {
            background-color: @fg;
            color: @bg0;
            border-radius: 0px 0px 15px 15px;
            border-bottom: 5px solid @accent;
          }

          #custom-launcher,
          #clock,
          #clock-date,
          #workspaces,
          #pulseaudio,
          #network,
          #tray,
          #custom-powermenu {
            background-color: @bg0;
            color: @fg;
            padding-left: 10px;
            padding-right: 10px;
            margin-top: 7px;
            margin-bottom: 12px;
            border-radius: 10px;
            border-bottom: 5px solid #161a1d;
          }

          #workspaces {
            padding: 0px;
          }

          #workspaces button {
            padding: 0px 6px;
            color: @fg;
            background-color: transparent;
            border-radius: 10px;
          }

          #workspaces button.active {
            background-color: @blue;
            color: @bg0;
            border-bottom: 5px solid #366660;
          }

          #custom-launcher {
            background-color: @green;
            color: @bg0;
            border-bottom-color: #556a35;
            margin-left: 15px;
            padding-left: 20px;
            padding-right: 21px;
          }

          #custom-powermenu {
            background-color: @red;
            color: @bg0;
            border-bottom-color: #951c1f;
            margin-right: 15px;
            padding-left: 20px;
            padding-right: 23px;
          }

          #tray {
            padding-left: 15px;
            padding-right: 15px;
          }
        '';
      };
    };
}
