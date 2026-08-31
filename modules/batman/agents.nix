# Agent tool configs for batman (opencode + pi), symlinked from the
# ryan-nvim (dotfiles) input. Ported from ./agents.nix (top level).
{inputs, ...}: {
  users.batman.home.base = {...}: {
    xdg.configFile."opencode".source =
      "${inputs.ryan-nvim}/opencode/.config/opencode";

    home.file.".pi".source =
      "${inputs.ryan-nvim}/pi/.pi";
  };
}
