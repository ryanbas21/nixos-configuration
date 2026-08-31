# Obsidian notes for batman. Ported from ./home.nix (top level);
# desktop-only (assigned to home.pc) because the vault lives on the
# desktop's home (and its notes NFS mount).
{...}: {
  users.batman.home.pc = {...}: {
    programs.obsidian = {
      enable = true;

      vaults.notes.target = "Documents/Obsidian";

      defaultSettings.app = {
        alwaysUpdateLinks = true;
        spellcheck = true;
      };
    };
  };
}
