{
  lib,
  config,
  pkgs,
  ...
}:
let
  composeFile = "${./.}/docker-compose.yaml";
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/app-data/monitoring/prometheus 0700 65534 65534 -"
    "d /var/lib/app-data/monitoring/grafana 0700 472 472 -"
    "d /var/lib/app-data/monitoring/loki 0700 10001 10001 -"
    # Uptime Kuma resets its data dir to root:root ownership on its own regardless
    # of what's set here.
    "d /var/lib/app-data/monitoring/uptime 0700 0 0 -"
  ];

  sops.secrets = {
    "compose-stacks/monitoring/umami/app_secret" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-monitoring.service" ];
    };
  };

  sops.templates."compose-monitoring.env".content = ''
    GF_SERVER_ROOT_URL=https://monitor.${config.domains.main}
    GF_SMTP_HOST=${config.sops.placeholder."smtp/host"}:${config.sops.placeholder."smtp/port"}
    GF_SMTP_USER=${config.sops.placeholder."smtp/user"}
    GF_SMTP_PASSWORD=${config.sops.placeholder."smtp/password"}
    GF_SMTP_FROM_ADDRESS=grafana@${config.domains.main}
    DATABASE_URL=postgresql://umami:${config.sops.placeholder."compose-stacks/databases/postgres/passwords/umami"}@postgres:5432/umami
    APP_SECRET=${config.sops.placeholder."compose-stacks/monitoring/umami/app_secret"}
  '';

  # Dashboards are exposed without Authelia protection for now (the `auth` stack
  # doesn't exist yet) — same reasoning as reverse-proxy's own dashboard: this test
  # VM isn't reachable from the public Internet yet (DNS hasn't cut over), only via
  # Tailscale, where it's already an implicitly trusted network. Revisit once `auth`
  # is deployed. Loki has no route here at all — nothing needs to reach it
  # externally (Grafana queries it over the `monitoring` docker network, and
  # grafana-alloy on this host reaches it over loopback), and it has no built-in
  # auth (`auth_enabled: false`), so there's no reason to expose it yet.
  reverseProxy.dynamicConfig.monitoring = ''
    http:
      routers:
        prometheus:
          rule: "Host(`prometheus.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: prometheus
          tls:
            certResolver: le_main
        grafana:
          rule: "Host(`monitor.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: grafana
          tls:
            certResolver: le_main
        uptime:
          rule: "Host(`uptime.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: uptime
          tls:
            certResolver: le_main
        umami:
          rule: "Host(`umami.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: umami
          tls:
            certResolver: le_main
      services:
        prometheus:
          loadBalancer:
            servers:
              - url: "http://prometheus:9090"
        grafana:
          loadBalancer:
            servers:
              - url: "http://grafana:3000"
        uptime:
          loadBalancer:
            servers:
              - url: "http://uptime:3001"
        umami:
          loadBalancer:
            servers:
              - url: "http://umami:3000"
  '';

  compose-stacks.stacks.monitoring = {
    inherit composeFile;
    environmentFile = config.sops.templates."compose-monitoring.env".path;
    dockerNetworks = [
      "web"
      "db"
      "monitoring"
    ];
    extraAfter = [ "reverse-proxy-dynamic-config.service" ];
  };
}
