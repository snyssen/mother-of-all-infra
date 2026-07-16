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
      fzf.enable = lib.mkDefault true;
      intelli-shell.enable = lib.mkDefault true;
      direnv.enable = lib.mkDefault true;
      starship.enable = lib.mkDefault true;
      dua.enable = lib.mkDefault true;
    };
    shell.fish = lib.mkIf (osConfig.shell.default == "fish") {
      enable = true;
      fzf.enable = lib.mkDefault true;
      intelli-shell.enable = lib.mkDefault false;
      direnv.enable = lib.mkDefault true;
      starship.enable = lib.mkDefault true;
      dua.enable = lib.mkDefault true;
    };
  };
}
