{ lib, ... }:
let
  services = {
    speedtest = {
      domain = "speedtest.snyssen.be";
    };
  };
in
{
  services.traefik.dynamicConfigOptions = {
    http.middlewares = {
      ip-allowlist = {
        ipAllowList.sourceRange = [
          # Home
          "213.49.36.74/32"
          # tailnet
          "100.64.0.0/10"
        ];
      };
    };
    http.routers = lib.mkMerge [
      {
        traefik-dashboard = {
          entryPoints = [ "websecure" ];
          rule = "Host(`ingress.snyssen.be`)";
          service = "api@internal";
          middlewares = [ "ip-allowlist" ];
        };
        prometheus-node-exporter = {
          entryPoints = [ "websecure" ];
          rule = "Host(`pne.ingress.snyssen.be`)";
          service = "prometheus-node-exporter";
          middlewares = [ "ip-allowlist" ];
        };
      }
      (lib.mapAttrs (svcName: svc: {
        entryPoints = [ "websecure" ];
        rule = "Host(`${svc.domain}`)";
        service = svcName;
      }) services)
    ];
    http.services = lib.mkMerge [
      {
        prometheus-node-exporter = {
          loadBalancer.servers = [
            { url = "http://localhost:9100"; }
          ];
        };
      }
      (lib.mapAttrs (svcName: svc: {
        loadBalancer = {
          servers = [
            { url = "https://${svc.domain}"; }
          ];
          passHostHeader = false;
        };
      }) services)
    ];
  };
}
