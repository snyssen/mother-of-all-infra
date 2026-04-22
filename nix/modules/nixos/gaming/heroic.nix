{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.gaming.heroic;
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      (heroic.override {
        extraPkgs =
          pkgs': with pkgs'; [
            gamescope
            gamemode
          ];
      })
    ];
  };
}
