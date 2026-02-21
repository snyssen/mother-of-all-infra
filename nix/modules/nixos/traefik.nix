{ config, lib, ... }:
let
  cfg = config.traefik;
in
{
  options.traefik = {
    letsencrypt = {
      email = lib.mkOption {
        default = "admin@snyssen.be";
      };
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
      dnsChallenge.domains = lib.mkOption {
        default = [ "snyssen.be" ];
      };
    };
    tcpEntrypoints = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            port = lib.mkOption {
              type = lib.types.port;
            };
          };
        }
      );
      default = { };
    };
  };

  config = {
    systemd.services.traefik.environment = lib.mkIf (cfg.letsencrypt.challengeType == "dns") {
      DYNU_API_KEY_FILE = cfg.letsencrypt.dnsChallenge.apiKeyPath;
    };

    services.traefik = {
      enable = true;
      staticConfigOptions = {
        entrypoints = lib.mkMerge [
          {
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
              http.tls.domains = lib.mkIf (cfg.letsencrypt.challengeType == "dns") (
                lib.lists.map (domain: {
                  main = "${domain}";
                  sans = [ "*.${domain}" ];
                }) cfg.letsencrypt.dnsChallenge.domains
              );
            };
          }
          (builtins.mapAttrs (entrypointName: entrypoint: {
            address = ":${builtins.toString entrypoint.port}";
          }) cfg.tcpEntrypoints)
        ];
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
        accesslog = {
          filePath = "/var/log/traefik/access.log";
          # format = "json";
        };
        log = {
          level = "INFO";
          filePath = "/var/log/traefik/traefik.log";
          format = "json";
        };
      };
    };
  };
}
