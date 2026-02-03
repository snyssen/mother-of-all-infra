{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.obsidian;
in
{
  options.obsidian = {
    vaults = {
      manage = lib.mkEnableOption "Manage Obsidian vaults";
      rootPath = lib.mkOption {
        type = lib.types.str;
        default = "Notes"; # config.syncthing.folders."Notes".path;
        description = "Root path where your Obsidian vaults are located, relative to your home directory";
      };
      subPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "personal"
          "TTRPG/Cthulhu - Le Monastère du Stup"
          "TTRPG/DnD - Bahut"
          "TTRPG/DnD - Saltmarsh"
          "TTRPG/DnD - Yawning Portal"
          "TTRPG/Mass Effect - En eaux troubles"
          "TTRPG/Pathfinder - Gatewalkers"
        ];
      };
    };
  };

  config = {
    programs.obsidian = lib.mkIf cfg.vaults.manage {
      enable = true;
      vaults = builtins.listToAttrs (
        lib.lists.map (subPath: {
          name = builtins.baseNameOf subPath;
          value = {
            target = "${cfg.vaults.rootPath}/${subPath}";
          };
        }) cfg.vaults.subPaths
      );
    };

    home.packages = lib.mkIf (!cfg.vaults.manage) [ pkgs.obsidian ];

    stylix.targets.obsidian.vaultNames = lib.mkIf (
      config.stylix.targets.obsidian.enable && cfg.vaults.manage
    ) (lib.lists.map builtins.baseNameOf cfg.vaults.subPaths);
  };
}
