{
  config,
  lib,
  pkgs,
  flake,
  ...
}:
let
  cfg = config.argunix.builder;
in
{
  imports = [
    flake.inputs.argunix.nixosModules.argunix-builder
  ];

  options = {
    argunix.builder = {
      enable = lib.mkEnableOption "Argunix builder configuration";
      coordinatorHost = lib.mkOption {
        type = lib.types.str;
        default = "argunix.snyssen.be";
      };
      argunixPort = lib.mkOption {
        type = lib.types.int;
        default = 45678;
      };
      enrollmentTokenFile = lib.mkOption {
        type = lib.types.path;
        default = "/run/secrets/argunix/builder_enrollment/token";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.argunix-builder = {
      enable = true;
      argunixHost = cfg.coordinatorHost;
      argunixPort = cfg.argunixPort;
      enrollmentTokenFile = cfg.enrollmentTokenFile;
    };
  };
}
