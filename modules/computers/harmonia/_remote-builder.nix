{
  # NOTE: root's authorized_keys are NOT declared here — they live in
  # harmonia.nix, which owns the gated key set (LAN-scoped, forced
  # nix-store-protocol command for the fleet build/push key). A second
  # declaration here would list-merge an unrestricted duplicate and
  # silently bypass that gating (caught by eval during the 2026-09-06
  # security audit). The remotebuild user below is kept from the
  # upstream builder template, currently unused as a demotion target.
  users.users.remotebuild = {
    isSystemUser = true;
    createHome = false;
    group = "remotebuild";
    useDefaultShell = true;

  };

  users.groups.remotebuild = { };

  nix = {
    nrBuildUsers = 64;
    settings = {
      trusted-users = [ "root" ];
      min-free = 10 * 1024 * 1024;
      max-free = 200 * 1024 * 1024;
      max-jobs = "auto";
      cores = 0;
    };
  };

  systemd.services.nix-daemon.serviceConfig = {
    MemoryAccounting = true;
    MemoryMax = "90%";
    OOMScoreAdjust = 500;
  };
}
