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
  };

  config = lib.mkIf cfg.enable {
  };
}
