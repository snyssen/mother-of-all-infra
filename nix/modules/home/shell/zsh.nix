{
  lib,
  config,
  osConfig,
  pkgs,
  ...
}:
let
  cfg = config.shell.zsh;
in
{
  options.shell.zsh = {
    enable = lib.mkEnableOption "Zsh shell";
    atuin.enable = lib.mkEnableOption "atuin history manager";
    fzf.enable = lib.mkEnableOption "fzf history manager";
    intelli-shell.enable = lib.mkEnableOption "intelli-shell";
    direnv.enable = lib.mkEnableOption "direnv integration";
    starship.enable = lib.mkEnableOption "starship prompt";
    dua.enable = lib.mkEnableOption "dua-cli integration";
  };

  config = lib.mkIf cfg.enable {
    home.packages =
      [ ] ++ lib.lists.optional cfg.atuin.enable pkgs.atuin ++ lib.lists.optional cfg.dua.enable pkgs.dua;

    programs.fzf = lib.mkIf cfg.fzf.enable {
      enable = true;
      enableZshIntegration = true;
    };

    programs.intelli-shell = lib.mkIf cfg.intelli-shell.enable {
      enable = true;
      enableZshIntegration = true;
      # settings = {};
      # shellHotkeys = {};
    };

    programs.direnv = lib.mkIf cfg.direnv.enable {
      enable = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };

    programs.starship = lib.mkIf cfg.starship.enable {
      enable = true;
      enableZshIntegration = true;
    };

    programs.zsh = {
      enable = true;
      autosuggestion.enable = true;
      enableCompletion = true;
      syntaxHighlighting.enable = true;
      zsh-abbr = {
        enable = true;
        abbreviations = {
          cat = lib.mkIf config.programs.bat.enable "bat";
          vsc = lib.mkIf config.programs.vscode.enable "code";
          vscd = lib.mkIf config.programs.vscode.enable "code --diff";
          ts = lib.mkIf osConfig.services.tailscale.enable "tailscale";
          tsst = lib.mkIf osConfig.services.tailscale.enable "tailscale status";
          tssh = lib.mkIf osConfig.services.tailscale.enable "tailscale ssh";
        };
      };

      # orders from https://nix-community.github.io/home-manager/options.xhtml#opt-programs.zsh.initContent
      initContent =
        let
          envVars = lib.mkOrder 1000 ''
            EDITOR="code --wait"
          '';
          atuin = lib.mkOrder 1500 ''
            eval "$(atuin init zsh)"
          '';
        in
        lib.mkMerge [
          envVars
          (lib.mkIf cfg.atuin.enable atuin)
        ];
    };
  };
}
