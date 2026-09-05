{
  users.users.remotebuild = {
    isSystemUser = true;
    createHome = false;
    group = "remotebuild";
    useDefaultShell = true;

  };
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIlMK7jt86TlHnzvths3bWymyEZfmfxJcUQ1PkuJ/HEJ desktop-nix-cache-push"
  ];

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
