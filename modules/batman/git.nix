# Git setup
{ ... }: {
  users.batman.home.base = { ... }: {
    programs.git = {
      enable = true;
      signing = {
        key = "F3EB6A9821002B2C";
        signByDefault = true;
      };
      settings = {
        pull.rebase = true;
        rebase.autoStash = true;
        user.name = "ryan bas";
        user.email = "ryanbas21@gmail.com";
        init.defaultBranch = "main";
        push = {
          autoSetupRemote = true;
        };
        alias = {
          co = "checkout";
          st = "status";
          sync = "!git pull --rebase && git push";
          po = "push origin";
        };
      };
    };
  };
}
