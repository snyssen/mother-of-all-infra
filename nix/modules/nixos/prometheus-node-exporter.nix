{ config, lib, ... }:
let
  cfg = config.prometheus-node-exporter;
in
{
  options.prometheus-node-exporter = {
    listenAddress = lib.mkOption {
      default = "0.0.0.0";
    };
    port = lib.mkOption {
      default = 9100;
    };
    openFirewall = lib.mkEnableOption "open firewall";
  };

  config = {
    services.prometheus.exporters.node = {
      enable = true;
      listenAddress = cfg.listenAddress;
      port = cfg.port;
      enabledCollectors = [ "systemd" ];
      openFirewall = cfg.openFirewall;
    };
  };
}
