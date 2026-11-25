{
  lib,
  config,
  osConfig,
  pkgs,
  ...
}:
let
  cfg = config.shell.fish;
in
{
  options.shell.fish = {
    enable = lib.mkEnableOption "Fish shell";
    fzf.enable = lib.mkEnableOption "fzf history manager";
    intelli-shell.enable = lib.mkEnableOption "intelli-shell";
    direnv.enable = lib.mkEnableOption "direnv integration";
    starship.enable = lib.mkEnableOption "starship prompt";
    dua.enable = lib.mkEnableOption "dua-cli integration";
    zellij = {
      enable = lib.mkEnableOption "Zellij terminal multiplexer";
      autoStart = lib.mkEnableOption "starting Zellij automatically in every interactive shell";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.fish = {
      enable = true;
      generateCompletions = true;
      shellAbbrs = {
        cat = lib.mkIf config.programs.bat.enable "bat";
        vsc = lib.mkIf config.programs.vscode.enable "code";
        vscd = lib.mkIf config.programs.vscode.enable "code --diff";
        ts = lib.mkIf osConfig.services.tailscale.enable "tailscale";
        tsst = lib.mkIf osConfig.services.tailscale.enable "tailscale status";
        tssh = lib.mkIf osConfig.services.tailscale.enable "tailscale ssh";
      };
      plugins = [
        {
          name = "bang-bang";
          src = pkgs.fishPlugins.bang-bang;
        }
      ];
    };

    programs.fzf = lib.mkIf cfg.fzf.enable {
      enable = true;
      enableFishIntegration = true;
    };

    programs.intelli-shell = lib.mkIf cfg.intelli-shell.enable {
      enable = true;
      enableFishIntegration = true;
      # settings = {};
      # shellHotkeys = {};
    };

    programs.direnv = lib.mkIf cfg.direnv.enable {
      enable = true;
      # Below is automatically enabled by direnv,
      # and adding it again actually break build
      # enableFishIntegration = true;
      nix-direnv.enable = true;
    };

    programs.zellij = lib.mkIf cfg.zellij.enable {
      enable = true;
      enableFishIntegration = cfg.zellij.autoStart;
    };

    programs.starship = lib.mkIf cfg.starship.enable {
      enable = true;
      enableFishIntegration = true;
    };

    home.packages = with pkgs; [ ] ++ lib.lists.optional cfg.dua.enable dua;
  };
}
