{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.gaming;
in
{
  imports = [
    ./steam.nix
    ./heroic.nix
  ];

  options.gaming = {
    enable = lib.mkEnableOption "Gaming configuration" // {
      default = true;
    };
    user = lib.mkOption {
      default = "snyssen";
    };
    steam = {
      enable = lib.mkEnableOption "Steam client" // {
        default = true;
      };
    };
    heroic = {
      enable = lib.mkEnableOption "Heroic Games Launcher" // {
        default = true;
      };
    };
    minecraft = {
      enable = lib.mkEnableOption "Minecraft" // {
        default = true;
      };
    };
    retroarch = {
      enable = lib.mkEnableOption "RetroArch" // {
        default = true;
      };
    };
    extraPkgs = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
    };
  };

  config = lib.mkIf cfg.enable {
    programs.gamemode.enable = true;
    programs.gamescope.enable = true;

    environment.systemPackages =
      with pkgs;
      [ protontricks ]
      ++ cfg.extraPkgs
      ++ lib.lists.optional cfg.minecraft.enable prismlauncher
      ++ lib.lists.optional cfg.retroarch.enable (
        retroarch.withCores (
          cores: with cores; [
            beetle-psx-hw # PS1
            pcsx2 # PS2
          ]
        )
      );
  };
}
