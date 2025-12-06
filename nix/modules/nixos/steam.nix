{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.steam;
in
{
  options.steam = {
    user = lib.mkOption {
      default = "snyssen";
    };
  };

  config = {
    programs.steam = {
      enable = true;
      gamescopeSession.enable = true;
    };
    environment = {
      systemPackages = with pkgs; [
        mangohud
        protonup-ng
      ];
      # For using protonup
      # Simply run "protonup" in a terminal and it will install the latest ProtonGE and integrate it with Steam
      # Steam will keep the version up to date afterward
      sessionVariables = {
        STEAM_EXTRA_COMPAT_TOOLS_PATHS = "/home/${cfg.user}/.steam/root/compatibilitytools.d";
      };
    };
    programs.gamemode.enable = true;
  };
}
