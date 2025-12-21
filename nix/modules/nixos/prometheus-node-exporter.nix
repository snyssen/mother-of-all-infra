{ config, lib, ... }:
let
  cfg = config.prometheus-node-exporter;
in
{
  options.prometheus-node-exporter = {
    listenAddress = lib.mkOption {
      default = "0.0.0.0";
    };
  };

  config = {
    services.prometheus.exporters.node = {
      enable = true;
      listenAddress = cfg.listenAddress;
      port = 9100;
      enabledCollectors = [ "systemd" ];
      openFirewall = true;
    };
  };
}
