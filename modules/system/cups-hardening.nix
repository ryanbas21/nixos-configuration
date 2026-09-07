# CUPS service sandboxing — the fixable finding of the 2026-09-07
# systemd exposure sweep (prompted by xeiaso.net/blog/
# paranoid-nixos-2021-07-18): `systemd-analyze security cups.service`
# scored 9.2 UNSAFE (no sandboxing directives at all). Actual exposure is
# small — cups binds 127.0.0.1:631 only and the firewall is default-deny —
# so this is defense in depth for local privilege escalation, not an
# internet-facing fix. Same spirit as observability.nix's custom units,
# applied to the one third-party daemon on the base tier with a bad score.
#
# Deliberately ABSENT (each would break real printing, documented so a
# future reader doesn't "complete" the set):
#   - CapabilityBoundingSet / SystemCallFilter=~@privileged — cupsd starts
#     as root and setuid()s down to the cups user internally; filtering
#     those breaks the drop.
#   - MemoryDenyWriteExecute — unproven against the filter chain
#     (ghostscript et al.); not worth an invisible printing failure.
#   - PrivateDevices — would cut off USB/parallel printers.
#   - ProtectSystem=strict — cups writes /etc/cups and /var/spool/cups;
#     enumerating ReadWritePaths adds fragility for little gain over the
#     kernel/home/namespace shields below.
{ ... }:

{
  nixos.modules.base = {
    systemd.services.cups.serviceConfig = {
      NoNewPrivileges = true;
      PrivateTmp = true;
      # "read-only": filters never write $HOME, but fontconfig/user
      # config may be consulted — not "tmpfs" (empty) on purpose.
      # (Spelling matters: systemd rejects "read" — the VM test caught
      # the unit override being ignored with exactly that value.)
      ProtectHome = "read-only";
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHostname = true;
      RestrictRealtime = true;
      RestrictNamespaces = true;
      LockPersonality = true;
      RestrictSUIDSGID = true;
    };
  };
}
