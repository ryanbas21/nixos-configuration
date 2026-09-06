# Hardware hygiene for the desktop (assigns to nixos.modules.base —
# today the desktop is the base's only consumer; the harmonia host runs
# its own minimal base and its real hardware file hasn't landed yet.
# If a second base-consuming host ever appears with a non-btrfs root,
# promote these to a host tier like maintenance.nix does for retention).
{ ... }: {
  nixos.modules.base = {
    # Weekly TRIM for the NVMe SSD (fstrim.timer).
    services.fstrim.enable = true;

    # Periodic btrfs scrub: detect silent corruption on the root
    # filesystem instead of backing it up faithfully via borg.
    # Btrfs-specific — see the header comment.
    services.btrfs.autoScrub = {
      enable = true;
      fileSystems = [ "/" ];
    };

    # Compressed RAM swap as an OOM cushion (32G physical, no disk
    # swap): a memory spike degrades gracefully instead of killing
    # Plasma.
    zramSwap.enable = true;

    # Disk health monitoring; findings land in the journal
    # (journalctl -t smartd). No mail transport is configured.
    services.smartd.enable = true;

    # Bluetooth: the hardware is present (hci0) and Plasma ships
    # bluedevil; enable the bluez daemon so the UI actually works.
    hardware.bluetooth.enable = true;

    # Firmware updates (SSD/motherboard/BIOS) via `fwupdmgr`.
    services.fwupd.enable = true;
  };
}
