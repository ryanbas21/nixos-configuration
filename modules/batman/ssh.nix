# SSH client config for batman's desktop. Declares what previously lived
# in a hand-written ~/.ssh/config: GitHub auth is bound to ~/.ssh/git,
# the dedicated push key (id_borg is the agenix identity only), so this
# is desktop-only (home.pc) — the standalone exports don't carry the
# key. Home-manager backs the existing manual ~/.ssh/config up to *.bak
# on first activation (backupFileExtension).
{ ... }: {
  users.batman.home.pc = { ... }: {
    programs.ssh = {
      enable = true;
      # Opt out of home-manager's built-in default block (deprecated; it
      # warns on every eval) and declare the equivalent Host "*" settings
      # verbatim below, per the programs.ssh deprecation notice.
      enableDefaultConfig = false;
      settings = {
        "*" = {
          ForwardAgent = false;
          AddKeysToAgent = "no";
          Compression = false;
          ServerAliveInterval = 0;
          ServerAliveCountMax = 3;
          HashKnownHosts = false;
          UserKnownHostsFile = "~/.ssh/known_hosts";
          ControlMaster = "no";
          ControlPath = "~/.ssh/master-%r@%n:%p";
          ControlPersist = "no";
        };
        "github.com" = {
          HostName = "github.com";
          User = "git";
          IdentityFile = "~/.ssh/git";
          IdentitiesOnly = true;
        };
        # The harmonia cache server (root-only host; batman's id_borg
        # was authorized as the admin key 2026-09-04 — see
        # modules/computers/harmonia.nix). Without this block ssh never
        # offers id_borg (it is not a default identity name), so
        # `ssh root@192.168.1.82` fails even though the key is
        # authorized. Desktop-only, same as github.com: id_borg is the
        # desktop's agenix identity and does not ride along on the
        # standalone exports.
        "192.168.1.82" = {
          HostName = "192.168.1.82";
          User = "root";
          IdentityFile = "~/.ssh/id_borg";
          IdentitiesOnly = true;
        };
      };
      extraConfig = ''
        Host 192.168.1.82
          User root
          IdentityFile /home/batman/.ssh/id_borg
          IdentitiesOnly yes
      '';
    };
  };
}
