{
  config,
  lib,
  pkgs,
  flake,
  ...
}:
let
  cfg = config.argunix;
in
{
  imports = [
    ./builder.nix
    ./coordinator.nix
  ];

  options.argunix = {
    enable = lib.mkEnableOption "Argunix configuration" // {
      default = true;
    };
    mode = lib.mkOption {
      type = lib.types.enum [
        "builder"
        "coordinator"
        "both"
      ];
      default = "builder";
    };
  };

  config = {
    argunix = {
      builder = lib.mkIf (cfg.mode == "builder" || cfg.mode == "both") {
        enable = true;
      };
      coordinator = lib.mkIf (cfg.mode == "coordinator" || cfg.mode == "both") {
        enable = true;
      };
    };
  };
}
