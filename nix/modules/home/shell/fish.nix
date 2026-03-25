{
  lib,
  config,
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
  };

  config = lib.mkIf cfg.enable {
    programs.fish = {
      enable = true;
      generateCompletions = true;
      shellAbbrs = {
        cat = lib.mkIf config.programs.bat.enable "bat";
        vsc = lib.mkIf config.programs.vscode.enable "code";
        vscd = lib.mkIf config.programs.vscode.enable "code --diff";
        ts = lib.mkIf config.programs.tailscale.enable "tailscale";
        tsst = lib.mkIf config.programs.tailscale.enable "tailscale status";
        tssh = lib.mkIf config.programs.tailscale.enable "tailscale ssh";
      };
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

    programs.starship = lib.mkIf cfg.starship.enable {
      enable = true;
      enableFishIntegration = true;
    };

    home.packages = with pkgs; [ ] ++ lib.lists.optional cfg.dua.enable dua;
  };
}
