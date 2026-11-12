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
      builder = lib.mkIf (cfg.enable && (cfg.mode == "builder" || cfg.mode == "both")) {
        enable = true;
        # The coordinator never builds itself: a host running both only builds through
        # its own builder, which upstream has dial the coordinator over loopback.
        # Through argunix.snyssen.be it depends on that name resolving to this host,
        # and on that path letting the builder port through, which ingress doesn't.
        coordinatorHost = lib.mkIf (cfg.mode == "both") (lib.mkDefault "127.0.0.1");
      };
      coordinator = lib.mkIf (cfg.enable && (cfg.mode == "coordinator" || cfg.mode == "both")) {
        enable = true;
      };
    };
  };
}
