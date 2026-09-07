# The framework laptop's power & thermal stack (imported from
# framework.nix; desktop hosts want none of this).
#
# NOTE: this nixpkgs (26.11 unstable) no longer ships the old
# hardware.framework module — its successor is services.framework-control
# (D-Bus hardware service; checked in the module tree 2026-09-06), and
# battery charge thresholds are NOT covered by any module anymore —
# hence the explicit sysfs writes below.
{ pkgs, ... }:

let
  # 80% charge ceiling — Framework's own battery-longevity guidance.
  # Raise to 100 before an unplugged travel day (or drop this whole
  # stanza and charge to the moon; the tradeoff is battery wear).
  # Applied at boot and re-applied by udev on every power_supply
  # event (dock/AC hotplug recreates the battery's sysfs state).
  chargeThreshold = 80;
  applyChargeThreshold = pkgs.writeShellScript "framework-charge-threshold" ''
    for f in /sys/class/power_supply/BAT*/charge_control_end_threshold; do
      [ -w "$f" ] && echo ${toString chargeThreshold} > "$f"
    done
    exit 0
  '';
in
{
  # amd_pstate is the frequency driver (kernel default on this Ryzen);
  # power-profiles-daemon is its D-Bus profile layer — Plasma's battery
  # tray, powerprofilesctl, and the framework-control CLI all speak it.
  # Deliberately NOT: TLP (asserts against p-p-d; per-device tuning on
  # a stock Framework buys nothing) and thermald (Intel-only —
  # meaningless on this AMD board).
  services.power-profiles-daemon.enable = true;

  # Framework's own hardware-control daemon + CLI: fan curves, module
  # LEDs, input schemes, charge-threshold CLI — shells out to
  # framework_tool, which rides along in the module's path.
  services.framework-control.enable = true;

  # Lid close → suspend. This is logind's own stock default, stated
  # explicitly because the two desktop sessions on this machine split
  # the job: under Plasma, powerdevil holds the handle-lid-switch
  # inhibitor and implements the lid itself (its LidAction default is
  # Sleep, with kscreenlocker locking on resume); under Hyprland no
  # daemon inhibits logind, so *this* line is the lid handler and
  # hypridle (batman/hyprland.nix) supplies the lock-before-sleep
  # half via logind's PrepareForSleep signal. Docked-with-external-
  # monitor keeps the stock "ignore" (lidSwitchDocked) — closing the
  # lid on a dock leaves the external display alive; flip
  # lidSwitchDocked to "suspend" here if that's not wanted.
  services.logind.lidSwitch = "suspend";

  # Pin suspend-to-idle: the sleep mode this platform actually
  # supports. "deep" (S3) is broken on AMD Frameworks — fails to
  # resume reliably — and s2idle is already the kernel default; pinned
  # here so the choice is deliberate and sleep-drain regressions
  # (BIOS/kernel updates shift this; fwupdmgr in system/hardware.nix
  # is the other half of that fight) start from a known floor.
  boot.kernelParams = [ "mem_sleep_default=s2idle" ];

  systemd.services.framework-charge-threshold = {
    description = "Framework battery charge ceiling (${toString chargeThreshold}%)";
    wantedBy = [ "multi-user.target" ];
    # Skips cleanly where no battery exists (the VM boot tests).
    unitConfig.ConditionPathExists = "/sys/class/power_supply";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = applyChargeThreshold;
    };
  };
  services.udev.extraRules = ''
    ACTION=="change", SUBSYSTEM=="power_supply", RUN+="${applyChargeThreshold}"
  '';
}
