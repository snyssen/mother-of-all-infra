{ lib, ... }:
let
  appsServerIp = "100.114.242.89";
  # These allow proxying web services to the apps server without middleware or complex rules.
  # Unlike the TCP/UDP definitions below, HTTP backends are configured from these hostnames
  # (for example as `https://${hostname}`), so ingress must resolve them via split-horizon or
  # tailnet DNS to the apps server. Do not use public DNS for backend resolution here.
  # If you need more complex rules, you can add them directly to
  # services.traefik.dynamicConfigOptions.http.routers and
  # services.traefik.dynamicConfigOptions.http.services options below.
  proxiedWebServices = {
    attic = "attic.snyssen.be";
    auth-main = "auth.snyssen.be";
    auth-team = "auth.bigdouf.team";
    dashboard = "dash.snyssen.be";
    mc-dynmap = "mc.snyssen.be";
    mc-usw-dynmap = "mc-usw.snyssen.be"; # dynmap for USW server
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

    # Note: this lives on the apps host
    argunix = "argunix.snyssen.be";
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
  traefik.ping.enable = true;

  traefik.tcpEntrypoints = lib.mapAttrs (_: svc: {
    port = svc.port;
  }) proxiedTCPServices;

  traefik.udpEntrypoints = lib.mapAttrs (_: svc: {
    port = svc.port;
  }) proxiedUDPServices;
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
        ping = {
          entryPoints = [ "websecure" ];
          rule = "Host(`ingress.snyssen.be`) && Path(`/ping`)";
          service = "ping@internal";
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
    ];
  }
  // lib.optionalAttrs (proxiedTCPServices != { }) {
    tcp.routers = lib.mkMerge [
      (lib.mapAttrs (svcName: svc: {
        entryPoints = [ svcName ];
        rule = "HostSNI(`*`)";
        service = svcName;
      }) proxiedTCPServices)
    ];
    tcp.services = lib.mkMerge [
      (lib.mapAttrs (svcName: svc: {
        loadBalancer = {
          servers = [
            { address = "${svc.address}:${toString svc.port}"; }
          ];
        };
      }) proxiedTCPServices)
    ];
  }
  // lib.optionalAttrs (proxiedUDPServices != { }) {
    udp.routers = lib.mkMerge [
      (lib.mapAttrs (svcName: svc: {
        entryPoints = [ svcName ];
        service = svcName;
      }) proxiedUDPServices)
    ];
    udp.services = lib.mkMerge [
      (lib.mapAttrs (svcName: svc: {
        loadBalancer = {
          servers = [
            { address = "${svc.address}:${toString svc.port}"; }
          ];
        };
      }) proxiedUDPServices)
    ];
  };
}
