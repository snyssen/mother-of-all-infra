{ lib, config, ... }:
let
  cfg = config.ghostty;
in
{
  options.ghostty = { };

  config = {
    programs.ghostty = {
      enable = true;

      enableZshIntegration = true;

      settings = {
        shell-integration-features = "ssh-terminfo,ssh-env";
      };
    };
  };
}
