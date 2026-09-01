{ ... }: {
  users.batman.home.base = { ... }: {
    programs.gh = {
      enable = true;
      settings.git_protocol = "ssh";
    };

  };
}

