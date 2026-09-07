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

    # Kernel tunings that make zram swap actually earn its keep —
    # zram is an in-memory device, and the kernel's disk-swap defaults
    # fight it (quartet adapted from ryan4yin/nix-config,
    # modules/nixos/base/zram.nix; values held at his defaults):
    boot.kernel.sysctl = {
      # Swap aggressively to zram (0-200; disk default 60). Values
      # above 100 are the documented recommendation for in-memory
      # swap: pages compress better than they page out.
      "vm.swappiness" = 180;
      # Disable watermark boost — premature reclaim that evicts
      # warm page cache under memory pressure spikes.
      "vm.watermark_boost_factor" = 0;
      # Wake kswapd earlier (background reclaim at ~1.25% free vs the
      # ~0.1% default) so pressure degrades smoothly instead of
      # stalling into direct reclaim at swappiness 180.
      "vm.watermark_scale_factor" = 125;
      # No swap readahead (0-6; 3 = 4 pages/IO). zram has no seek
      # cost — readahead only wastes memory holding pages nothing
      # asked for.
      "vm.page-cluster" = 0;
    };

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
