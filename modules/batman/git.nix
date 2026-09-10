# Git setup
{ ... }: {
  users.batman.home.base = { ... }: {
    programs.git = {
      enable = true;
      signing = {
        # The dedicated signing SUBKEY fingerprint (rsa4096, [S],
        # 2026-09-09) — pinned explicitly, so git signs with exactly
        # this key rather than relying on gpg's newest-subkey
        # preference. The primary's secret never touches a host
        # (gpg.nix's stub-only contract); rotating the subkey means
        # updating this fingerprint.
        key = "0818A0D4E91914B4265FD243D1ADFE3B04FA3CE2";
        signByDefault = true;
      };
      settings = {
        pull.rebase = true;
        rebase.autoStash = true;
        user.name = "ryan bas";
        user.email = "18267769+ryanbas21@users.noreply.github.com";
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
