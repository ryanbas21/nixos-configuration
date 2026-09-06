# Fleet observability: push alerting, failure hooks, and a weekly
# health digest — the answer to "nobody reads the journal".
#
# The problem this file exists for: every failure worth knowing about
# (smartd findings, scrub failures, GC failures, a backup that stopped
# running) lands in a journal that no human opens on a headless box or
# a lid-closed laptop. So the three halves here are:
#
#   1. The SERVER: ntfy on harmonia (computers/harmonia.nix, port
#      6777, LAN-subnet-scoped like sshd and the cache). Phones
#      subscribe with the ntfy app against
#      http://192.168.1.82:6777/<hostname>. The whole rack rides the
#      UPS, so the alert path itself survives mains events.
#   2. FAILURE HOOKS: a notify-failed@.service template that OnFailure
#      wiring points at — a unit dying pages the phone within seconds.
#      Wired: nix-gc, fstrim, snapper-timeline/-cleanup (base hosts);
#      nix-gc (harmonia). NOT wired: btrfs-scrub (its unit names are
#      generated per-filesystem; the digest's scrub-status section
#      covers it) and borgmatic (a home-manager USER unit — the
#      system-level template cannot see it; the digest reports its
#      last result instead).
#   3. The DIGEST: a weekly one-screen health summary per host. Also
#      its own dead-man signal — a host that stops posting digests is
#      a host in trouble.
#
# Assigned twice (maintenance.nix pattern): the desktop-style hosts
# eat nixos.modules.base, harmonia keeps its minimal base but still
# needs its own alerts — and hosts the server everyone posts to.
{ lib, inputs, ntfyServer, ... }:

let
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
  ntfyUrl = "http://${ntfyServer.host}:${toString ntfyServer.port}";

  # Fire-and-forget push helper shared by every alerting path. NEVER
  # fails: an OnFailure hook that itself fails would recurse, and a
  # dead notification path must not take the notifying unit down with
  # it. Delivery failures degrade to the journal.
  notify = pkgs.writeShellScript "notify" ''
    # $1 title, $2 ntfy priority (low|default|high|urgent), $3 body
    if ! ${lib.getExe pkgs.curl} -sf -m 8 --retry 2 --retry-all-errors \
        -H "Title: $1" -H "Priority: $2" -H "Tags: warning" \
        -d "$3" "${ntfyUrl}/$(hostname)"; then
      ${pkgs.util-linux}/bin/logger -t observability \
        "notify: delivery to ${ntfyUrl} failed — $1: $3"
    fi
    exit 0
  '';

  # Instantiated per failed unit via the notify-failed@.service
  # template below; systemd's %i (the unit name) arrives as $1.
  notifyFailed = pkgs.writeShellScriptBin "notify-failed" ''
    exec ${notify} "URGENT: $1 failed" urgent \
      "unit $1 failed on $(hostname) at $(date '+%F %T') — journalctl -u $1"
  '';

  healthDigest = pkgs.writeShellScriptBin "health-digest" ''
    # One screen of everything that is otherwise write-only journal.
    # Sections self-neutralize on hosts that lack the hardware
    # (harmonia: no batman, no btrfs, no smartctl; off-LAN hosts: no
    # UPS) so the same script serves every NixOS host.
    set -u
    out=""
    add() { out="$out$1
"; }

    add "== $(hostname) health digest — $(date '+%F %T')"
    add "uptime: $(uptime -p | sed 's/^up //')  kernel: $(uname -r)"

    # Failed units, system and (where present) batman's user manager.
    failed=$(systemctl --failed --plain --no-legend | head -n 20)
    add "failed system units: $(systemctl --failed --no-legend | grep -c . || true)"
    [ -n "$failed" ] && add "$failed"
    if id batman >/dev/null 2>&1; then
      ufailed=$(runuser -u batman -- systemctl --user --failed --plain --no-legend | head -n 20)
      add "failed user units (batman): $(runuser -u batman -- systemctl --user --failed --no-legend | grep -c . || true)"
      [ -n "$ufailed" ] && add "$ufailed"
      # The backup heartbeat. This is the ONLY place a silently dead
      # borgmatic surfaces (it is a user unit — see the header).
      runuser -u batman -- systemctl --user is-active --quiet borgmatic.timer \
        || add "WARN: borgmatic.timer is not active for batman"
      add "borgmatic last run: $(runuser -u batman -- systemctl --user show borgmatic.service -p Result -p ExecMainExitTimestamp -p ExecMainStatus | tr '\n' ' ')"
    fi

    # Journal error volume this week — the cheap leading indicator
    # that something is quietly wrong.
    add "journal err+ lines (7d): $(journalctl -p 3 -S '7 days ago' --no-pager 2>/dev/null | wc -l)"

    # Filesystem headroom (only mounts that are up — the noauto NFS
    # automounts must not be poked awake by the digest).
    for m in / /home; do
      findmnt -n "$m" >/dev/null && add "$(df -h "$m" | tail -n 1)"
    done

    # btrfs: scrub state and snapshot counts (skips on ext4 hosts).
    if [ "$(findmnt -n -o FSTYPE /)" = btrfs ]; then
      add "scrub: $(btrfs scrub status / | sed -n 's/^\tScrub started: /started /p; s/^\tStatus: /status /p' | tr '\n' ' ')"
      for c in root home; do
        [ -f /etc/snapper/configs/$c ] \
          && add "snapper $c: $(snapper -c $c list | tail -n +2 | wc -l) snapshots"
      done
    fi

    # Disk health: smartd findings land in the journal; this is the
    # pull side — the overall verdict only.
    if command -v smartctl >/dev/null && [ -e /dev/nvme0n1 ]; then
      add "smart: $(smartctl -H /dev/nvme0n1 | sed -n 's/^overall-health self-assessment test result: //p')"
    fi

    # The rack UPS (Synology's DSM NUT server at 192.168.1.30:3493,
    # verified open 2026-09-06): status, charge, runtime. Off-LAN or
    # NAS-down → the section simply omits. The framework laptop's
    # watcher (framework/_ups.nix) is the real-time half of this.
    ups=$(timeout 3 ${pkgs.nut}/bin/upsc ups@192.168.1.30 2>/dev/null \
      | sed -n 's/^ups\.status: /status /p; s/^battery\.charge: /charge %/p; s/^battery\.runtime: /runtime s/p' \
      | tr '\n' '; ')
    [ -n "$ups" ] && add "ups (rack): $ups"

    if ! ${lib.getExe pkgs.curl} -sf -m 10 --retry 2 --retry-all-errors \
        -H "Title: health digest" -H "Priority: low" -H "Tags: pill" \
        -d "$out" "${ntfyUrl}/$(hostname)"; then
      ${pkgs.util-linux}/bin/logger -t health-digest \
        "delivery to ${ntfyUrl} failed"
    fi
    exit 0
  '';

  # The client half every NixOS host runs (the server half is
  # computers/harmonia.nix).
  client = {
    systemd.services."notify-failed@" = {
      description = "Push-notify that %i failed";
      # No wantedBy: only OnFailure ever pulls this template in.
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe notifyFailed} %i";
      };
      path = [ pkgs.curl pkgs.util-linux ];
    };

    systemd.services.health-digest = {
      description = "Weekly fleet health digest (observability)";
      serviceConfig.Type = "oneshot";
      path = with pkgs; [
        curl
        util-linux # logger, runuser
        smartmontools
        snapper
        btrfs-progs
        nut # upsc
      ];
      serviceConfig.ExecStart = lib.getExe healthDigest;
    };
    systemd.timers.health-digest = {
      description = "Weekly fleet health digest";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Sun *-*-* 09:00:00";
        # A laptop that was asleep Sunday 9am still owes its digest.
        Persistent = true;
      };
    };

    # sar samples every 10 min — the after-the-fact "what happened at
    # 3am" record (sar -f /var/log/sa/...).
    services.sysstat.enable = true;

    # Cap the persistent journal: the systemd default lets it grow to
    # 10% of the btrfs root — gigabytes of / that nothing prunes. 1G
    # is years of err-level volume at this fleet's rate.
    services.journald.extraConfig = "SystemMaxUse=1G";
  };
in
{
  nixos.modules.base = lib.mkMerge [
    client
    {
      systemd.services = {
        nix-gc.unitConfig.OnFailure = "notify-failed@%n.service";
        fstrim.unitConfig.OnFailure = "notify-failed@%n.service";
        snapper-timeline.unitConfig.OnFailure = "notify-failed@%n.service";
        snapper-cleanup.unitConfig.OnFailure = "notify-failed@%n.service";
      };
    }
  ];

  # harmonia skips nixos.modules.base but still needs its own alerts —
  # and its GC failures matter as much as anyone's. (fstrim/snapper
  # wiring would materialize phantom stub units here: its minimal base
  # has neither.)
  nixos.configurations.harmonia.module = lib.mkMerge [
    client
    {
      systemd.services.nix-gc.unitConfig.OnFailure = "notify-failed@%n.service";
    }
  ];
}
