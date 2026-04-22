{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.gaming.steam;
  user = config.gaming.user;
in
{
  config = lib.mkIf cfg.enable {
    programs.steam = {
      enable = true;
      gamescopeSession.enable = true;
      remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
      localNetworkGameTransfers.openFirewall = true; # Open ports in the firewall for Steam Local Network Game Transfers
      protontricks.enable = true;
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
        STEAM_EXTRA_COMPAT_TOOLS_PATHS = "/home/${user}/.steam/root/compatibilitytools.d";
      };
    };
  };
}
