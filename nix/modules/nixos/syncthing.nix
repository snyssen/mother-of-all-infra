{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.syncthing;
in
{
  options.syncthing = {
    username = lib.mkOption {
      default = "snyssen";
      type = lib.types.str;
    };
    devices = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            id = lib.mkOption {
              type = lib.types.str;
              example = "XXX-XXX-XXX";
            };
          };
        }
      );
      default = { };
    };
    folders = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            path = lib.mkOption {
              type = lib.types.str;
              example = "/mnt/folder-to-sync";
            };
            devices = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              example = ''
                [ "device-one", "device-two" ]
              '';
            };
          };
        }
      );
      default = { };
    };
  };

  config = {
    services.syncthing = {
      enable = true;
      user = "${cfg.username}";
      dataDir = "/home/${cfg.username}/Documents";
      configDir = "/home/${cfg.username}/Documents/.config/syncthing";
      overrideDevices = true;
      overrideFolders = true;
      settings = {
        devices = cfg.devices;
        folders = cfg.folders;
      };
    };
  };
}
