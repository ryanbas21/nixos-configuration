{ inputs, ... }: {
  users.batman.home.base = { pkgs, ... }: {
    programs.fzf = {
      enable = true;
      enableFishIntegration = true;
      defaultCommand = "fd --type f --strip-cwd-prefix --hidden --follow --exclude .git";
      fileWidget = {
        command = "fd --type f --strip-cwd-prefix --hidden --follow --exclude .git";
      };
    };
  };
}
