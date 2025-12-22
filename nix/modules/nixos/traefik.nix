{ config, lib, ... }:
let
  cfg = config.traefik;
in
{
  options.traefik = {
    letsencrypt.email = lib.mkOption {
      default = "admin@snyssen.be";
    };
  };

  config = {
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
          };
        };
        certificatesResolvers.letsencrypt.acme = {
          email = cfg.letsencrypt.email;
          storage = "${config.services.traefik.dataDir}/acme.json";
          httpChallenge.entryPoint = "web";
        };
        api.dashboard = true;
        log = {
          level = "INFO";
          filePath = "${config.services.traefik.dataDir}/traefik.log";
          format = "json";
        };
      };

      dynamicConfigOptions = {
        http.routers = {
          traefik-dash = {
            rule = "Host(`ingress.snyssen.be`)";
            service = "api@internal";
          };
        };
        # http.services = {

        # };
      };
    };
  };
}
