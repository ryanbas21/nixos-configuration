# Agent tools for batman
{ inputs, ... }: {
  users.batman.home.base = { pkgs, ... }: {
    home.packages = [
      inputs.llm-agents.packages.${pkgs.system}.pi
      inputs.llm-agents.packages.${pkgs.system}.openskills
      inputs.llm-agents.packages.${pkgs.system}.plannotator
      inputs.llm-agents.packages.${pkgs.system}.herdr
      inputs.llm-agents.packages.${pkgs.system}.rtk
    ];
    home.file.".pi/settings.json".source =
      "${inputs.ryan-nvim}/.pi/settings.json";

    home.file.".pi/AGENTS.md".source =
      "${inputs.ryan-nvim}/.pi/AGENTS.md";

  };
}

