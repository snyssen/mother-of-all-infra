{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.onedrive;
in
{
  options.onedrive = {
    enable = lib.mkEnableOption "Enable OneDrive client (onedrive) application" // {
      default = true;
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.onedrive;
      description = "Package to use for OneDrive client.";
    };
    gui = {
      enable = lib.mkEnableOption "Enable OneDrive GUI (onedrivegui) application";
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.onedrivegui;
        description = "Package to use for OneDrive GUI.";
      };
    };
  };

  config = {
    services.onedrive.enable = true;
    services.onedrive.package = cfg.package;
    environment.systemPackages = lib.mkIf cfg.gui.enable [ cfg.gui.package ];
  };
}
