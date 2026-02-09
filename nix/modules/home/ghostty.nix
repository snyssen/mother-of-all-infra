{ lib, config, ... }:
let
  cfg = config.ghostty;
in
{
  options.ghostty = { };

  config = {
    programs.ghostty = {
      enable = true;

      enableZshIntegration = config.shell.zsh.enable;
      enableFishIntegration = config.shell.fish.enable;

      settings = {
        shell-integration-features = "ssh-terminfo,ssh-env";
      };
    };
  };
}
