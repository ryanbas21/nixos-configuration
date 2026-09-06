# File-index database (plocate) for the desktop-style hosts.
#
# `plocate <name>` finds any file on the live filesystem in
# milliseconds — the daily updatedb timer (02:15 by default) does the
# walking. plocate needs an io_uring-fast index, not the mlocate
# format, which is why the package is the module default here.
#
# Base tier only: harmonia keeps its minimal closure and its
# root-only user has no use for an index of a cache it serves.
{ ... }:
{
  nixos.modules.base.services.locate.enable = true;
}
