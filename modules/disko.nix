# Flake-level diskoConfigurations: disk layouts the disko CLI consumes
# (github:nix-community/disko, locked input). Not imported into any host
# eval — hosts keep their mount tables in computers/<name>/_hardware.nix;
# the two meet at the partition labels (see computers/nixos/_disko.nix).
# A new host gets a _disko.nix next to its _hardware.nix plus an entry
# here.
{ ... }: {
  flake.diskoConfigurations = {
    nixos = import ./computers/nixos/_disko.nix;
    harmonia = import ./computers/harmonia/_disko.nix;
  };
}
