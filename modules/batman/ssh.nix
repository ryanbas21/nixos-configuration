# SSH config for batman's machines — client half (the Host blocks in
# home.pc below) and server half (id_borg in authorized_keys, via the
# nixos.base block at the bottom). Declares what previously lived
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
        "harmonia" = {
          HostName = "192.168.1.82";
          User = "root";
          IdentityFile = "~/.ssh/id_borg";
          IdentitiesOnly = true;
        };
        "media" = {
          HostName = "192.168.1.33";
          User = "ryan";
          IdentityFile = "~/.ssh/id_borg";
          IdentitiesOnly = true;
        };
        "utils" = {
          HostName = "192.168.1.39";
          User = "ryan";
          IdentityFile = "~/.ssh/id_borg";
          IdentitiesOnly = true;
        };
        "n8n" = {
          HostName = "192.168.1.39";
          User = "ryan";
          IdentityFile = "~/.ssh/id_borg";
          IdentitiesOnly = true;
        };
        "nas" = {
          HostName = "192.168.1.30";
          User = "ryan";
          IdentityFile = "~/.ssh/id_borg";
          IdentitiesOnly = true;
        };
        "framework" = {
          HostName = "192.168.1.52";
          User = "batman";
          IdentityFile = "~/.ssh/id_borg";
          IdentitiesOnly = true;
        };
        "desktop" = {
          HostName = "192.168.1.183";
          User = "batman";
          IdentityFile = "~/.ssh/id_borg";
          IdentitiesOnly = true;
        };
        "ha" = {
          HostName = "192.168.1.41";
          User = "ryan";
          IdentityFile = "~/.ssh/id_borg";
          IdentitiesOnly = true;
        };
      };
    };
  };

  # Server half: authorize id_borg for batman on every host importing
  # this user's NixOS base — the desktop and the framework laptop
  # (never the standalone exports; harmonia is root-only and gets its
  # own authorized_keys in computers/harmonia.nix). With the client
  # blocks above that closes the loop: `ssh desktop` / `ssh framework`
  # from any machine holding id_borg. Granting batman's own fleet
  # identity access to batman's own machines adds no new trust edge —
  # it is the same boundary every agenix secret already rests on.
  users.batman.nixos.base = {
    users.users.batman.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIELiz8KiOJ2x7L1J2yx3X8RZkZ3bd/uHcsUH5rzVw8Cl batman@nixos"
    ];
  };
}
