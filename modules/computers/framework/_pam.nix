# PAM policy for the fingerprint-equipped laptop (framework only:
# imported from framework.nix; hosts without services.fprintd keep
# the stock stacks everywhere).
{ config, lib, pkgs, ... }:
{
  security.pam.services.sudo.fprintAuth = true;
  security.pam.services.polkit-1.fprintAuth = true;
  security.pam.services.hyprlock.fprintAuth = true;

  # EITHER-OR AUTH AT THE SDDM GREETER (password OR fingerprint).
  #
  # The stock sddm PAM service substacks `login` for auth, and the
  # generated login stack runs pam_fprintd (sufficient, order 11400)
  # BEFORE the pam_unix pair (unix-early 11700 / unix 13100).
  # pam_fprintd blocks inside fprintd's 30s verify window, so every
  # TYPED password sat unanswered until the reader timed out —
  # journal from 2026-09-05, identical on every login:
  #
  #   21:10:54 "Place your right index finger on the fingerprint reader"
  #   21:11:24 "Verification timed out" → password accepted same second
  #
  # sddm cannot do this natively: v0.21.0 (latest release) has no
  # fingerprint code; the greeter merely relays pam_fprintd's prompt.
  # So fix the PAM order instead — same modules as the login stack,
  # password first:
  #
  #   - correct password + Enter → unix-early caches it, kwallet grabs
  #     it, unix (try_first_pass) validates → sufficient → INSTANT.
  #     pam_fprintd never runs.
  #   - Enter on an EMPTY field → pam_unix fails, falls through to
  #     pam_fprintd's "Place your finger" prompt → swipe → login.
  #   - a MISTYPED password takes the fprintd path (30s + finger
  #     prompt, then auth failure and a fresh prompt) — no worse than
  #     today, where every attempt paid the 30s.
  #
  # Fingerprint logins leave kwallet locked (no password captured) —
  # exactly like a fingerprint login before this change; only the
  # password path got faster. Console `login`, sudo, polkit and
  # hyprlock stacks are untouched. mkForce because the sddm module
  # assigns rules.auth wholesale (autoOrderRules substack); nothing
  # else contributes auth rules to this service.
  security.pam.services.sddm.rules.auth = lib.mkForce {
    # Prompts for (and caches) the submitted password. `optional`
    # keeps the stack alive on failure so the fingerprint path
    # survives a bad or empty password. Mirrors stock login's
    # unix-early.
    unix-early = {
      order = 10100;
      control = "optional";
      modulePath = config.security.pam.pam_unixModulePath;
      settings = {
        likeauth = true;
        nullok = true;
      };
    };
    # Stashes the cached password for the session-phase kwallet
    # unlock. Same placement as stock login: after the first pam_unix
    # conversation, before the decisive one.
    kwallet = {
      order = 10200;
      control = "optional";
      modulePath = "${pkgs.kdePackages.kwallet-pam}/lib/security/pam_kwallet5.so";
    };
    # The decisive password check: try_first_pass consumes the cached
    # password with no second conversation, so a correct password
    # completes authentication in milliseconds.
    unix = {
      order = 10300;
      control = "sufficient";
      modulePath = config.security.pam.pam_unixModulePath;
      settings = {
        likeauth = true;
        nullok = true;
        try_first_pass = true;
      };
    };
    # Fingerprint — only reached when no valid password was supplied.
    fprintd = {
      order = 10400;
      control = "sufficient";
      modulePath = "${pkgs.fprintd}/lib/security/pam_fprintd.so";
    };
    deny = {
      order = 10500;
      control = "required";
      modulePath = "${config.security.pam.package}/lib/security/pam_deny.so";
    };
  };
}
