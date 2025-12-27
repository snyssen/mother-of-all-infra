{ config, lib, ... }:
let
  cfg = config.traefik;
in
{
  options.traefik = {
    letsencrypt.email = lib.mkOption {
      default = "admin@snyssen.be";
    };
    letsencrypt.dnsChallenge.apiKeyPath = lib.mkOption { };
  };

  config = {
    systemd.services.traefik.environment = {
      DYNU_API_KEY_FILE = cfg.letsencrypt.dnsChallenge.apiKeyPath;
    };

    services.traefik = {
      enable = true;
      staticConfigOptions = {
        entrypoints = {
          web = {
            address = ":80";
            asDefault = true;
            http.redirections.entrypoint = {
              to = "websecure";
              scheme = "https";
            };
          };

          websecure = {
            address = ":443";
            asDefault = true;
            http.tls.certResolver = "letsencrypt";
            http.tls.domains = [
              {
                main = "ingress.snyssen.be";
                sans = [ "*.ingress.snyssen.be" ];
              }
            ];
          };
        };
        certificatesResolvers.letsencrypt.acme = {
          email = cfg.letsencrypt.email;
          storage = "${config.services.traefik.dataDir}/acme.json";
          dnsChallenge.provider = "dynu";
        };
        api.dashboard = true;
        log = {
          level = "INFO";
          filePath = "/var/log/traefik.log";
          format = "json";
        };
      };

      dynamicConfigOptions = {
        http.middlewares = {
          ip-allowlist = {
            ipAllowList.sourceRange = [
              # Home
              "81.240.174.125"
              "2a02:a03f:ab21:f900:d8a4:3da3:67f1:963d"
              # tailnet
              "100.64.0.0/10"
            ];
          };
        };
        http.routers = {
          traefik-dash = {
            entryPoints = [ "websecure" ];
            rule = "Host(`ingress.snyssen.be`)";
            service = "api@internal";
            middlewares = [ "io-allowlist" ];
          };
          prometheus-node-exporter = {
            entryPoints = [ "websecure" ];
            rule = "Host(`pne.ingress.snyssen.be`)";
            service = "prometheus-node-exporter";
            middlewares = [ "io-allowlist" ];
          };
        };
        http.services = {
          prometheus-node-exporter = {
            loadBalancer.servers = [
              { url = "http://localhost:9100"; }
            ];
          };
        };
      };
    };
  };
}
