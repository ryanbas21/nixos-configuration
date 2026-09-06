# Nerd Fonts for batman — assigned to home.base so every consumer
# (NixOS hosts via home.pc, standalone home-manager exports) gets them.
{ ... }: {
  users.batman.home.base = { pkgs, ... }: {
    fonts.fontconfig.enable = true;
    home.packages = with pkgs; [
      nerd-fonts.fira-code
      nerd-fonts.fira-mono
      nerd-fonts.jetbrains-mono
    ];
  };
}
