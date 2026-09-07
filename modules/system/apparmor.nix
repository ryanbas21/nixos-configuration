# AppArmor beachhead: load the LSM now, confine nothing yet. Enabling
# with zero policies changes no behavior — it only puts "apparmor" on
# the boot LSM list, which is the prerequisite for every future
# profile (adding the LSM later would be a reboot-able config change
# blocking the whole rollout; today it is a no-op that ships ahead).
# The rollout contract for per-app profiles (the ryan4yin/nix-config
# pattern, hardening/): each app gets its own feature file here,
# every new policy starts in complain mode — violations log to the
# kernel journal (journalctl -k | grep -i apparmor) but never block —
# and promotes to enforce only after a stable period. The VM boot
# tests prove each step stays bootable, on every push.
{ ... }:

{
  nixos.modules.base = {
    security.apparmor.enable = true;
  };
}
