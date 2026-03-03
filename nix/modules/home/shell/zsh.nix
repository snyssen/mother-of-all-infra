{
  lib,
  config,
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

    programs.zsh = {
      enable = true;
      autosuggestion.enable = true;
      enableCompletion = true;
      syntaxHighlighting.enable = true;
      oh-my-zsh = {
        enable = true;
        plugins = [
          "colored-man-pages"
          "colorize"
          "docker-compose"
          "docker"
          "dotenv"
          "dotnet"
          "git"
          "npm"
          "screen"
          "vscode"
        ];
      };

      # orders from https://nix-community.github.io/home-manager/options.xhtml#opt-programs.zsh.initContent
      initContent =
        let
          p10kConfig = lib.mkOrder 500 ''
            # p10k config
            source ~/.p10k.zsh
          '';
          envVars = lib.mkOrder 1000 ''
            EDITOR="code --wait"
          '';
          atuin = lib.mkOrder 1500 ''
            eval "$(atuin init zsh)"
          '';
        in
        lib.mkMerge [
          p10kConfig
          envVars
          (lib.mkIf cfg.atuin.enable atuin)
        ];

      plugins = [
        {
          name = "powerlevel10k";
          src = pkgs.zsh-powerlevel10k;
          file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
        }
      ];
    };

    # Place p10k config file
    home.file.".p10k.zsh".source = ../../../files/home/p10k-config;
  };
}
