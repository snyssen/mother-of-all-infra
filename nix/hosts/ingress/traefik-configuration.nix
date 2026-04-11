{ lib, ... }:
let
  appsServerIp = "100.114.242.89";
  # These allows for proxying services directly to the apps server, without middleware or complex rules.
  # If you need more complex rules, you can add them directly to services.traefik.dynamicConfigOptions.http.routers and services.traefik.dynamicConfigOptions.http.services options below.
  proxiedWebServices = {
    attic = "attic.snyssen.be";
    auth-main = "auth.snyssen.be";
    auth-team = "auth.bigdouf.team";
    dashboard = "dash.snyssen.be";
    minecraft = "mc.snyssen.be"; # dynmap
    mc-usw = "mc-usw.snyssen.be"; # dynmap for USW server
    element = "element.snyssen.be";
    foundryvtt = "dnd.snyssen.be";
    immich = "photos.snyssen.be";
    jellyfin = "streaming.snyssen.be";
    matrix-mas = "matrix-mas.snyssen.be";
    matrix = "matrix.snyssen.be";
    nextcloud = "cloud.snyssen.be";
    personal-website = "snyssen.be";
    rallly = "events.bigdouf.team";
    recipes = "recipes.snyssen.be";
    pdf = "pdf.snyssen.be";
    social = "social.snyssen.be";
    speedtest = "speedtest.snyssen.be";
    team = "bigdouf.team";
    umami = "umami.snyssen.be";
  };
  proxiedTCPServices = {
    minecraft = {
      address = appsServerIp;
      port = 25565;
    };
  };
  proxiedUDPServices = {
    # example-udp-service = {
    #   address = appsServerIp;
    #   port = 12345;
    # };
  };
in
{
  services.traefik.dynamicConfigOptions = {
    http.middlewares = {
      ip-allowlist = {
        ipAllowList.sourceRange = [
          # Home
          # "213.49.36.74/32"
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

      (lib.mapAttrs (svcName: hostname: {
        entryPoints = [ "websecure" ];
        rule = "Host(`${hostname}`)";
        service = svcName;
      }) proxiedWebServices)

      (lib.mapAttrs (svcName: svc: {
        entryPoints = [ svcName ];
        rule = "HostSNI(`*`)";
        service = svcName;
      }) proxiedTCPServices)

      (lib.mapAttrs (svcName: hostname: {
        entryPoints = [ svcName ];
        service = svcName;
      }) proxiedUDPServices)
    ];
    http.services = lib.mkMerge [
      {
        prometheus-node-exporter = {
          loadBalancer.servers = [
            { url = "http://localhost:9100"; }
          ];
        };
      }

      (lib.mapAttrs (svcName: hostname: {
        loadBalancer = {
          servers = [
            { url = "https://${hostname}"; }
          ];
          passHostHeader = false;
        };
      }) proxiedWebServices)

      (lib.mapAttrs (svcName: svc: {
        loadBalancer = {
          servers = [
            { address = "${svc.address}:${svc.port}"; }
          ];
        };
      }) proxiedTCPServices)

      (lib.mapAttrs (svcName: svc: {
        loadBalancer = {
          servers = [
            { address = "${svc.address}:${svc.port}"; }
          ];
        };
      }) proxiedUDPServices)
    ];
  };
}
