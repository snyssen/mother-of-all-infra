{
  lib,
  osConfig,
  pkgs,
  ...
}:
{
  imports = [
    ./zsh.nix
    ./fish.nix
  ];

  config = {
    shell.zsh = lib.mkIf (osConfig.shell.default == "zsh") {
      enable = true;
      fzf.enable = true;
      intelli-shell.enable = true;
    };
    shell.fish.enable = (osConfig.shell.default == "fish");
  };
}
