{ config, lib, ... }:
let
  cfg = config.traefik;
in
{
  options.traefik = {
    ping.enable = lib.mkEnableOption "the ping endpoint for health checks.";
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
    udpEntrypoints = lib.mkOption {
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

  config =
    let
      overlappingNames = lib.lists.intersectLists (builtins.attrNames cfg.tcpEntrypoints) (
        builtins.attrNames cfg.udpEntrypoints
      );
    in
    {
      assertions = [
        {
          assertion = lib.lists.length overlappingNames == 0;
          message = "traefik: tcpEntrypoints and udpEntrypoints have overlapping names: '${lib.strings.concatStringsSep "', '" overlappingNames}'. Please use unique names for each entrypoint.";
        }
      ];

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
              address = ":${builtins.toString entrypoint.port}/tcp";
            }) cfg.tcpEntrypoints)
            (builtins.mapAttrs (entrypointName: entrypoint: {
              address = ":${builtins.toString entrypoint.port}/udp";
            }) cfg.udpEntrypoints)
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
          ping = lib.mkIf cfg.ping.enable {
            entryPoint = "websecure";
          };
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
