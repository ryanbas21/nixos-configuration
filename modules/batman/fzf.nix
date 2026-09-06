{ ... }: {
  users.batman.home.base = { ... }: {
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
