{ config, ... }:
let
  composeFile = "${./.}/docker-compose.yaml";
  host = "speedtest-tracker.${config.domains.main}";
in
{
  # PUID/PGID in docker-compose.yaml. Same mode as the legacy role created it with.
  systemd.tmpfiles.rules = [
    "d /var/lib/app-data/speedtest-tracker 0700 1000 1000 -"
  ];

  # Carried over unchanged from the legacy vault: it is Laravel's encryption key, and
  # keeping prod's means whatever the imported database holds encrypted with it stays
  # readable.
  sops.secrets."compose-stacks/speedtest-tracker/app_key" = {
    sopsFile = ../../data/speedtest-tracker.yaml;
  };

  sops.templates."compose-speedtest-tracker.env".content = ''
    APP_KEY=${config.sops.placeholder."compose-stacks/speedtest-tracker/app_key"}
    APP_URL=https://${host}
    DB_PASSWORD=${
      config.sops.placeholder."compose-stacks/databases/postgres/passwords/speedtest_tracker"
    }
    MAIL_HOST=${config.sops.placeholder."smtp/host"}
    MAIL_PORT=${config.sops.placeholder."smtp/port"}
    MAIL_USERNAME=${config.sops.placeholder."smtp/user"}
    MAIL_PASSWORD=${config.sops.placeholder."smtp/password"}
    MAIL_FROM_ADDRESS=speedtest-tracker@${config.domains.main}
  '';

  # Sysadmins only, through the admin-tools rule in auth/authelia-configuration.nix,
  # as on prod. Port 80 is the image's bundled nginx.
  reverseProxy.dynamicConfig.speedtest-tracker = ''
    http:
      routers:
        speedtest-tracker:
          rule: "Host(`${host}`)"
          entryPoints:
            - websecure
          service: speedtest-tracker
          middlewares:
            - authelia
          tls:
            certResolver: le_main
      services:
        speedtest-tracker:
          loadBalancer:
            servers:
              - url: "http://speedtest-tracker:80"
  '';

  compose-stacks.stacks.speedtest-tracker = {
    restartTriggers = [
      ../../data/speedtest-tracker.yaml
      ../../data/databases.yaml
      ../../data/common.yaml
      config.sops.templates."compose-speedtest-tracker.env".content
    ];
    inherit composeFile;
    environmentFile = config.sops.templates."compose-speedtest-tracker.env".path;
    dockerNetworks = [
      "web"
      "db"
    ];
    extraAfter = [ "reverse-proxy-dynamic-config.service" ];
  };
}
