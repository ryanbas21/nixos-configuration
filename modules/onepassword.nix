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
# stays in home.packages (packages.nix): the same binary family the
# integration handshake accepts, for standalone exports and scripting
# that never involves the app (service-account tokens, CI, etc.).
{ ... }: {
  nixos.modules.base = {
    # The CLI module: system op + a setgid onepassword-cli wrapper
    # (/run/wrappers/bin/op). The app verifies the CLIENT BINARY carries
    # the onepassword-cli group — official installs ship op exactly this
    # way — and rejects bare binaries with "unsupportedClientType" even
    # once the socket peer-check passes. The wiki's canonical NixOS setup
    # enables BOTH this and the GUI module.
    programs._1password.enable = true;

    programs._1password-gui = {
      enable = true;
      polkitPolicyOwners = [ "batman" ];
    };

    # The app's socket-credential check (SO_PEERCRED) requires connecting
    # clients to carry a 1Password group; user membership in onepassword
    # covers connections made outside the setgid wrapper. Without it every
    # handshake dies with "invalid group attempted to connect" (the app
    # log's exact words) and op reports "connection reset". Takes a fresh
    # login session.
    users.users.batman.extraGroups = [ "onepassword" ];
  };
}
