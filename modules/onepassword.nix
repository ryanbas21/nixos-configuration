# 1Password GUI at the SYSTEM level — not home-manager. The CLI↔app
# integration ("connect to desktop app") needs the app's polkit action
# visible to the system polkit daemon, and polkitd only scans system
# package paths; a per-user-profile package is invisible to it. The
# package also only GENERATES the policy when owners are non-empty
# (linux.nix: share/polkit-1/actions/com.1password.1Password.policy,
# templated with unix-user:<owner>), and programs._1password-gui bakes
# polkitPolicyOwners in via override. The module additionally provides
# the onepassword group and the setgid browser-support wrapper.
#
# The CLI stays in home.packages (packages.nix): same binary family the
# integration handshake accepts, and the headless service-account path
# (scripts/fetch-bootstrap-keys.sh) never involves the app at all.
{ ... }: {
  nixos.modules.base = {
    programs._1password-gui = {
      enable = true;
      polkitPolicyOwners = [ "batman" ];
    };

    # The app's socket-credential check (SO_PEERCRED) requires connecting
    # clients — the op CLI included — to carry the onepassword group the
    # module creates; without it every handshake dies with "invalid group
    # attempted to connect" (the app log's exact words) and op reports
    # "connection reset". Group membership takes a fresh login session.
    users.users.batman.extraGroups = [ "onepassword" ];
  };
}
