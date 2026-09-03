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
# exec-once, NOT home-manager systemd services: HM services bind to
# graphical-session.target, which also activates inside the Plasma
# session — dunst would fight Plasma's notification daemon and
# gammastep cannot drive KWin at all (see time-of-day-gamma.nix for
# that whole saga). exec-once scopes them to Hyprland only. On Hyprland
# gammastep works again — it speaks wlr-gamma-control, which KWin
# refuses to implement but Hyprland does — so this restores the
# 5500/3700 K day/night schedule the Plasma session gets via KWin
# Night Light.
{ inputs, ... }:

{
  users.batman.home.pc = { lib, pkgs, ... }:
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
          *Log*)      hyprctl dispatch exit ;;
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
        # Hyprland 0.56 grew a Lua config backend (hl.bind/hl.config,
        # see the example in the hyprland package's share/hypr/), and
        # home-manager flips its default to render hyprland.lua for
        # stateVersion >= 26.05. The classic hyprlang format stays
        # fully supported though — and the rice, the wiki, and this
        # module's $variable idiom ($bg0/$fg/$mainMod, hoisted to the
        # top of the conf via importantPrefixes) are all hyprlang —
        # so pin it rather than translate every dispatcher to Lua.
        configType = "hyprlang";
        # Compositor config in Nix rather than the rice's raw conf:
        # hyprland.conf becomes a generated file, version-controlled
        # with everything else.
        settings = {
          # --- everforest palette as hypr variables ($ sorts before
          # letters, so home-manager's alphabetical serialization puts
          # every $var ahead of the first section that uses them). ---
          "$bg0" = "0xff${everforest.bg0}";
          "$bg1" = "0xff${everforest.bg1}";
          "$bg5" = "0xff${everforest.bg5}";
          "$fg" = "0xff${everforest.fg}";
          "$red" = "0xff${everforest.red}";
          "$yellow" = "0xff${everforest.yellow}";
          "$green" = "0xff${everforest.green}";
          "$aqua" = "0xff${everforest.aqua}";

          # SUPER (Hyprland's convention) rather than xmonad's
          # mod1Mask/ALT — the xmonad chords stay identical apart from
          # the modifier, and Alt stays free for terminal shortcuts.
          "$mainMod" = "SUPER";

          env = [
            "MOZ_ENABLE_WAYLAND,1"
            "_JAVA_AWT_WM_NONREPARENTING,1"
            # Match the Plasma session's cursor/Qt theming so apps feel
            # at home; Breeze is installed system-wide via plasma6.
            "XCURSOR_THEME,Breeze"
            "XCURSOR_SIZE,24"
            "QT_QPA_PLATFORMTHEME,kde"
          ];

          monitor = [ ",preferred,auto,1" ];

          exec-once = [
            # No manual systemd/D-Bus environment import here:
            # wayland.windowManager.hyprland.systemd.enable defaults
            # to true and home-manager injects the exec-once that
            # starts hyprland-session.target (which imports
            # WAYLAND_DISPLAY et al for user services/portals, the
            # way KWin does for Plasma).
            # Session daemons — exec-once, not HM services, so they
            # never leak into the Plasma session (see module header).
            "waybar"
            "dunst"
            "hyprpaper"
            "gammastep" # reads ~/.config/gammastep/config.ini
            "nm-applet --indicator"
            "${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1"
            # Clipboard history (the rice's two watcher lines).
            "wl-paste --type text --watch cliphist store"
            "wl-paste --type image --watch cliphist store"
          ];

          general = {
            # xmonad: 20px screen gaps (gaps_out) + 6px window spacing
            # (gaps_in). The rice widens gaps_in to 10; the xmonad
            # value wins.
            gaps_in = 6;
            gaps_out = 20;
            border_size = 4;
            "col.active_border" = "$fg";
            "col.inactive_border" = "$bg5";
            # The xmonad-like master+stack comes first; M-e flips to
            # dwindle at runtime.
            layout = "master";
            resize_on_border = true;
          };

          decoration = {
            rounding = 10;
            blur.enabled = false;
            # The rice's signature flat "3D" bottom edge: a shadow
            # pinned below the window. (The rice's C++ patch extends it
            # to borders; the stock effect is close enough.)
            shadow = {
              enabled = true;
              range = 0;
              render_power = 4;
              color = "rgb(${everforest.accent})";
              color_inactive = "rgb(2b312f)";
              scale = 1.0;
              offset = "0 10";
            };
            dim_inactive = false;
            dim_strength = 0.1;
          };

          animations = {
            enabled = "yes";
            bezier = [
              "slow,0,0.85,0.3,1"
              "overshot,0.7,0.6,0.1,1.1"
              "bounce,1,1.6,0.1,0.85"
            ];
            animation = [
              "windows,1,5,bounce,popin"
              "border,1,20,default"
              "fade,1,5,overshot"
              "workspaces,1,6,overshot,slidevert"
              "windowsIn,1,5,slow,popin"
              "windowsMove,1,5,default"
            ];
          };

          master = {
            # xmonad Tall: master 2/3 of the screen, on the left, and
            # new windows join the stack rather than stealing master.
            mfact = 0.67;
            # 0.56 renamed new_is_master (bool) to new_status: xmonad
            # Tall keeps new windows in the stack, which is "slave".
            new_status = "slave";
          };

          dwindle = {
            # pseudotile was dropped from the config in 0.56 (the
            # per-window `pseudo` dispatcher went with it);
            # preserve_split keeps the split direction when moving
            # windows around, which is the part that matters.
            preserve_split = "yes";
          };

          group = {
            "col.border_inactive" = "$fg";
            "col.border_active" = "$bg5";
          };

          input = {
            kb_layout = "us";
            numlock_by_default = true;
            follow_mouse = 1;
            touchpad.natural_scroll = true;
          };

          # (0.56 dropped gestures.workspace_swipe from the config —
          # touchpad gestures are declared through the gesture API
          # now, which is Lua-config-only. Desktop without a touchpad,
          # so nothing is lost.)

          misc = {
            # xmonad's focus follows EWMH activation — jump to windows
            # that ask for attention.
            focus_on_activate = true;
            # Belt-and-braces behind hyprpaper: never fall back to the
            # built-in mascot wallpapers / logo if hyprpaper is slow
            # or dead (that fallback is what painted the first boot).
            force_default_wallpaper = 0;
            disable_hyprland_logo = true;
          };

          ecosystem = {
            # 0.56 renders a Windows-style "Go to settings to activate
            # Hyprland" donation nag over the wallpaper until switched
            # off — the documented off switch, verified live via
            # `hyprctl keyword ecosystem:no_donation_nag true`.
            no_donation_nag = true;
          };

          # --- keybinds: the xmonad translation (see module header) ---

          bind = [
            # Launchers (xmonad: M-Return ghostty, M-Space rofi, M-Tab
            # window switcher; pkill-first makes repeat presses toggle).
            "$mainMod, Return, exec, ghostty"
            # Vicinae (modules/batman/vicinae.nix) is the launcher —
            # `vicinae open` shows the window against the daemon that
            # module already runs under graphical-session.target, so
            # no exec-once here. (The pkill-wofi toggle pattern from
            # the rofi binds doesn't apply; `vicinae toggle` exists if
            # toggle-on-repeat-press is ever wanted.)
            "$mainMod, Space, exec, vicinae open"
            "$mainMod, Tab, exec, pkill wofi || wofi --show window"
            # xmonad had fullscreen on M-f and the browser on M4-f —
            # two different mods. On a single SUPER mod they collide,
            # so fullscreen keeps F (the constantly-used bind) and the
            # browser takes B.
            "$mainMod, B, exec, firefox"

            # Focus: M-j/k cycle the stack (xmonad focusDown/focusUp),
            # M-m the master; arrows are Hyprland-directional.
            "$mainMod, J, cyclenext"
            "$mainMod, K, cyclenext, prev"
            # 0.56 dropped the focusmaster dispatcher; the master
            # layout still answers `layoutmsg focusmaster`.
            "$mainMod, M, layoutmsg, focusmaster"
            "$mainMod, left, movefocus, l"
            "$mainMod, right, movefocus, r"
            "$mainMod, up, movefocus, u"
            "$mainMod, down, movefocus, d"

            # Swap: M-S-j/k (xmonad swapDown/Up), M-S-. swaps with
            # master (xmonad swapMaster).
            "$mainMod SHIFT, J, swapnext"
            "$mainMod SHIFT, K, swapnext, prev"
            "$mainMod SHIFT, period, layoutmsg, swapwithmaster"
            "$mainMod SHIFT, left, movewindow, l"
            "$mainMod SHIFT, right, movewindow, r"
            "$mainMod SHIFT, up, movewindow, u"
            "$mainMod SHIFT, down, movewindow, d"

            # Master pane geometry (xmonad Shrink/Expand = M-h/l,
            # IncMasterN = M-,/M-.).
            "$mainMod, H, layoutmsg, mfact -0.05"
            "$mainMod, L, layoutmsg, mfact +0.05"
            "$mainMod, comma, layoutmsg, addmaster"
            "$mainMod, period, layoutmsg, removemaster"

            # Layouts & window state: M-e cycles layouts, M-w tabbed
            # groups, M-f fullscreen, M-t float (xmonad sink), M-g
            # hides the bar (xmonad ToggleStruts).
            "$mainMod, E, exec, ${cycleLayout}"
            "$mainMod, W, togglegroup"
            "$mainMod, F, fullscreen, 0"
            "$mainMod, T, togglefloating"
            "$mainMod SHIFT, Q, killactive"
            "$mainMod, G, exec, pkill -SIGUSR1 waybar"

            # Workspaces: M-1..M-0 → 1..10, M-S-1..0 moves without
            # following (xmonad W.shift), M-[/] cycles
            # (xmonad nextWS/prevWS), M-S-[] shifts across.
            "$mainMod, 1, workspace, 1"
            "$mainMod, 2, workspace, 2"
            "$mainMod, 3, workspace, 3"
            "$mainMod, 4, workspace, 4"
            "$mainMod, 5, workspace, 5"
            "$mainMod, 6, workspace, 6"
            "$mainMod, 7, workspace, 7"
            "$mainMod, 8, workspace, 8"
            "$mainMod, 9, workspace, 9"
            "$mainMod, 0, workspace, 10"
            "$mainMod SHIFT, 1, movetoworkspacesilent, 1"
            "$mainMod SHIFT, 2, movetoworkspacesilent, 2"
            "$mainMod SHIFT, 3, movetoworkspacesilent, 3"
            "$mainMod SHIFT, 4, movetoworkspacesilent, 4"
            "$mainMod SHIFT, 5, movetoworkspacesilent, 5"
            "$mainMod SHIFT, 6, movetoworkspacesilent, 6"
            "$mainMod SHIFT, 7, movetoworkspacesilent, 7"
            "$mainMod SHIFT, 8, movetoworkspacesilent, 8"
            "$mainMod SHIFT, 9, movetoworkspacesilent, 9"
            "$mainMod SHIFT, 0, movetoworkspacesilent, 10"
            "$mainMod, bracketleft, workspace, e-1"
            "$mainMod, bracketright, workspace, e+1"
            "$mainMod SHIFT, bracketleft, movetoworkspacesilent, e-1"
            "$mainMod SHIFT, bracketright, movetoworkspacesilent, e+1"

            # Session: M-S-r reload (xmonad restart), M-S-e exits to
            # SDDM (xmonad quit), M-S-x locks (xmonad loginctl
            # lock-session — under Hyprland that job belongs to
            # hyprlock directly).
            "$mainMod SHIFT, R, exec, hyprctl reload"
            "$mainMod SHIFT, E, exit"
            "$mainMod SHIFT, X, exec, hyprlock"
            "$mainMod SHIFT, P, exec, ${powerMenu}"

            # Screenshots (xmonad F12/S-F12 flameshot; grim+slurp are
            # the Wayland equivalents).
            ", F12, exec, ${screenshot "region"}"
            "SHIFT, F12, exec, ${screenshot "full"}"
            "$mainMod, Print, exec, ${screenshot "full"}"

            # Clipboard history (the rice's M-V menu).
            "$mainMod, V, exec, cliphist list | wofi --dmenu | cliphist decode | wl-copy"

            # Workspace cycling on the wheel (the rice).
            "$mainMod, mouse_down, workspace, e-1"
            "$mainMod, mouse_up, workspace, e+1"

            # Media/hardware keys: wpctl ships with the pipewire the
            # base module enables (pactl would need the pulseaudio
            # package pulled in just for the CLI).
            ", XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 10%+"
            ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 10%-"
            ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
            ", XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
            ", XF86MonBrightnessUp, exec, brightnessctl set +10%"
            ", XF86MonBrightnessDown, exec, brightnessctl set 10%-"

            # The rice's resize submap (xmonad had none — resizing was
            # M-h/l — so this is a bonus, not a translation).
            "$mainMod, R, submap, resize"
          ];

          # Window rules: the xmonad ManageHook (firefox → ws2, Gimp
          # float) plus the rice's utility floats.
          windowruleV2 = [
            "workspace 2 silent, class:^(firefox)$"
            # Vicinae's launcher window must float centered or the
            # tiler adopts it (class from the module's StartupWMClass).
            "float, class:^(vicinae)$"
            "center, class:^(vicinae)$"
            "float, class:^(gimp)$"
            "float, class:^(pavucontrol)$"
            "size 600 800, class:^(pavucontrol)$"
            "center, class:^(pavucontrol)$"
            "float, class:^(org\\.gnome\\.Calculator)$"
            "size 490 600, class:^(org\\.gnome\\.Calculator)$"
            "float, class:^(blueman-manager)$"
            "float, title:^(Confirm to replace files)$"
            "float, title:^(File Operation Progress)$"
            "float, title:^(Steam - News)$"
          ];

          # (The rice's `layerrule noanim, selection` — no fade on
          # slurp's screenshot overlay — is dropped: 0.56 turned
          # layerrules into field/value pairs (no_anim 1) and its
          # namespace-matching syntax is in neither the shipped
          # example nor reachable through hyprctl keyword probes.
          # Purely cosmetic; revisit with 0.56 docs.)
        };

        # The rice's resize submap (xmonad had none — resizing was
        # M-h/l — so this is a bonus, not a translation). The entry
        # bind (M-R) lives in settings.bind above; home-manager
        # renders each submap as a `submap = name ... submap = reset`
        # block after the main settings, so the attrset-ordering that
        # blocked submaps from settings doesn't apply.
        submaps.resize.settings = {
          binde = [
            ", right, resizeactive, 15 0"
            ", left, resizeactive, -15 0"
            ", up, resizeactive, 0 -15"
            ", down, resizeactive, 0 15"
          ];
          bind = [ ", escape, submap, reset" ];
        };
      };

      # Session-scoped daemons configured as plain files — the HM
      # service modules would also run them under Plasma (see header).
      xdg.configFile = {
        "hypr/hyprpaper.conf".text = ''
          preload = ${wallpaper}
          wallpaper = ,${wallpaper}
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
