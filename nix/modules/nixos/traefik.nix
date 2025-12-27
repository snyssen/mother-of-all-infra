{ config, lib, ... }:
let
  cfg = config.traefik;
in
{
  options.traefik = {
    letsencrypt.email = lib.mkOption {
      default = "admin@snyssen.be";
    };
    letsencrypt = {
      challengeType = lib.mkOption {
        type = lib.types.enum [
          "http"
          "dns"
        ];
        default = "http";
      };
      dnsChallenge.apiKeyPath = lib.mkOption {
        description = ''
          Path to API key file for DNS challenge, REQUIRED if challengeType is "dns". Should be provided using a SOPS secret.
        '';
      };
    };
  };

  config = {
    systemd.services.traefik.environment = lib.mkIf (cfg.letsencrypt.challengeType == "dns") {
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
            http.tls.domains = lib.mkIf (cfg.letsencrypt.challengeType == "dns") [
              {
                main = "ingress.snyssen.be";
                sans = [ "*.ingress.snyssen.be" ];
              }
            ];
          };
        };
        certificatesResolvers.letsencrypt.acme = lib.mkMerge [
          {
            email = cfg.letsencrypt.email;
            storage = "${config.services.traefik.dataDir}/acme.json";
          }
          (lib.mkIf (cfg.letsencrypt.challengeType == "http") {
            httpChallenge.entrypoint = "web";
          })
          (lib.mkIf (cfg.letsencrypt.challengeType == "dns") {
            dnsChallenge.provider = "dynu";
          })
        ];
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
            middlewares = [ "ip-allowlist" ];
          };
          prometheus-node-exporter = {
            entryPoints = [ "websecure" ];
            rule = "Host(`pne.ingress.snyssen.be`)";
            service = "prometheus-node-exporter";
            middlewares = [ "ip-allowlist" ];
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
