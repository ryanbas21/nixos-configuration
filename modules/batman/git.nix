# Git setup
{ ... }: {
  users.batman.home.base = { ... }: {
    programs.git = {
      enable = true;
      signing = {
        # Full primary fingerprint — gpg resolves it to the signing
        # SUBKEY on the subkey-only keyring (gpg.nix); the primary
        # secret is a stub and cannot sign. Deliberately NOT the
        # "<fpr>!" form — the ! suffix pins the PRIMARY itself and
        # would break signing entirely.
        key = "D1ADFE3B04FA3CE2";
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
