# Pre-commit hooks, via git-hooks.nix's flake-parts module
# (https://github.com/cachix/git-hooks.nix, the flake formerly known as
# cachix/pre-commit-hooks.nix). The flakeModule does three things here:
#
# 1. `nix develop` enters a shell whose shellHook installs the hooks
#    into .git/hooks (and keeps them in sync — it writes a
#    .pre-commit-config.yaml symlink at the repo root; that file is
#    gitignored). Commits then run the hooks against the staged files.
# 2. `checks.pre-commit` lands in the flake's checks output, so
#    `nix build .#checks.x86_64-linux.pre-commit` (or a plain
#    `nix flake check`) runs every enabled hook over the whole tree —
#    note CI's flake-check job uses `--no-build`, so it only evaluates
#    this derivation; building it is the local full-repo lint.
# 3. The hook tools come from git-hooks.nix's own pinned tool set, so
#    the exact deadnix version is locked, not whatever nixpkgs has.
#
# Config was deliberately removed from the automated git-backup timer
# (it used to commit-and-push any dirty tree daily): commits are
# hand-made now, and this hook is the quality gate they pass through.
{ inputs, ... }:

{
  imports = [ inputs.git-hooks.flakeModule ];

  perSystem = { config, ... }: {
    pre-commit.settings.hooks.deadnix.enable = true;

    # The flake otherwise has no devShell; expose the one git-hooks
    # generates (mkShell + install shellHook + the hook tools on PATH)
    # so `nix develop` is what activates the hooks.
    devShells.default = config.pre-commit.devShell;
  };
}
