# Plymouth splash on the boot tier, plus an instant loader timeout so the
# desktop boots straight into the animation. Assigns to nixos.modules.base
# (desktop tier); harmonia keeps its minimal base, headless, no splash.
{ ... }: {
  nixos.modules.base = { pkgs, ... }: {
    boot.plymouth = {
      enable = true;
      theme = "cybernetic";
      themePackages = [
        # By default we would install all themes
        (pkgs.adi1090x-plymouth-themes.override {
          # shas.nix keys are lowercase; "Cybernetic" throws
          # 'Unknown theme(s)' at eval time.
          selected_themes = [ "rings" "cybernetic" ];
        })
      ];
    };
    boot.loader.timeout = 0;
  };
}
