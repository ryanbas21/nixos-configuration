{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # nixpkgs unstable (26.11) dropped x86_64-darwin; the 26.05-darwin
    # stable branch is nixpkgs' supported substitute for Intel Macs and
    # feeds only the ryan-intel-mac standalone home-manager export.
    nixpkgs-intel-mac.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    # Secrets (home-manager module + agenix CLI). Upstream moves rarely:
    # rev b027ee2 (2026-02-03) was still HEAD when checked 2026-09-01 —
    # verify with `nix flake metadata github:ryantm/agenix` before
    # assuming the lock entry is stale (see README, "Updating inputs").
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative partitioning (consumed by the disko CLI via the
    # flake-level diskoConfigurations; not part of any host eval).
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secure Boot for the framework (computers/framework/
    # _secure-boot.nix): Lanzaboote's lzbt signs everything written to
    # the ESP at switch time with the sbctl key set in /var/lib/sbctl.
    # Release-tagged per upstream docs (their examples pin the current
    # tag); follows our nixpkgs so the tool and module ride one
    # revision.
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ryan-nvim = {
      url = "github:ryanbas21/dotfiles";
      flake = false;
    };

    nvf = {
      url = "github:NotAShelf/nvf/v26.07";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    fzf-git-sh = {
      url = "github:junegunn/fzf-git.sh";
      flake = false;
    };

    # The summer-day-and-night Hyprland rice
    # (https://github.com/MathisP75/summer-day-and-night): pulled in for
    # its everforest wallpapers, which hyprpaper preloads from the store.
    # The rice's own config files are NOT used verbatim — they are ported
    # into modules/batman/hyprland.nix (home-manager) so they stay
    # declarative — so this input only ever feeds asset paths.
    summer-day-and-night = {
      url = "github:MathisP75/summer-day-and-night";
      flake = false;
    };

    psysonic.url = "github:Psysonic/psysonic";

    llm-agents.url = "github:numtide/llm-agents.nix";

    rigup.url = "github:YPares/rigup.nix";

    flake-parts.url = "github:hercules-ci/flake-parts";

    # Pre-commit hooks as flake-parts modules (the flake formerly known
    # as cachix/pre-commit-hooks.nix). deadnix is a built-in hook there.
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    import-tree = {
      url = "github:vic/import-tree";
      flake = false;
    };

    vicinae.url = "github:vicinaehq/vicinae";

  };

  outputs = inputs: import ./outputs.nix inputs;
}
