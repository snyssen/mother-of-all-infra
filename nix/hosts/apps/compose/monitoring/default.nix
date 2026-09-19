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
    GF_AUTH_GENERIC_OAUTH_CLIENT_ID=${config.sops.placeholder."compose-stacks/auth/oidc/grafana/client_id"}
    GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET=${config.sops.placeholder."compose-stacks/auth/oidc/grafana/client_secret"}
    GF_AUTH_GENERIC_OAUTH_AUTH_URL=https://auth.${config.domains.main}/api/oidc/authorization
    GF_AUTH_GENERIC_OAUTH_TOKEN_URL=https://auth.${config.domains.main}/api/oidc/token
    GF_AUTH_GENERIC_OAUTH_API_URL=https://auth.${config.domains.main}/api/oidc/userinfo
    DATABASE_URL=postgresql://umami:${config.sops.placeholder."compose-stacks/databases/postgres/passwords/umami"}@postgres:5432/umami
    APP_SECRET=${config.sops.placeholder."compose-stacks/monitoring/umami/app_secret"}
  '';

  # Grafana logs in via its own Authelia OIDC (see the `auth` stack). Prometheus and
  # Uptime Kuma have no login of their own, so their dashboards are gated behind
  # Authelia's forwardAuth middleware instead (defined once in the `auth` stack's own
  # dynamicConfig fragment, referenced here by plain name) — matching what the old
  # container_backbone/container_monitoring roles protected with `authelia@docker`.
  # Umami stays ungated, same as before.
  #
  # prometheus-write and loki are separate, ingestion-only routes for Grafana Alloy
  # (on this host and every tailnet host, see grafana-alloy.nix) to push metrics/logs
  # into — an agent push has no browser session, so it can't go through Authelia.
  # Gated instead by a tailnet-only IP allowlist, mirroring the `lan-whitelist`
  # middleware the legacy container_backbone/container_monitoring roles already use
  # for the exact same problem on Loki's own route there. Traefik's default
  # longest-rule-wins priority means prometheus-write's more specific rule doesn't
  # weaken the general prometheus dashboard router's Authelia gate.
  reverseProxy.dynamicConfig.monitoring = ''
    http:
      routers:
        prometheus:
          rule: "Host(`prometheus.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: prometheus
          middlewares:
            - authelia
          tls:
            certResolver: le_main
        prometheus-write:
          rule: "Host(`prometheus.${config.domains.main}`) && Path(`/api/v1/write`)"
          entryPoints:
            - websecure
          service: prometheus
          middlewares:
            - tailnet-whitelist
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
          middlewares:
            - authelia
          tls:
            certResolver: le_main
        umami:
          rule: "Host(`umami.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: umami
          tls:
            certResolver: le_main
        loki:
          rule: "Host(`loki.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: loki
          middlewares:
            - tailnet-whitelist
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
        loki:
          loadBalancer:
            servers:
              - url: "http://loki:3100"
      middlewares:
        tailnet-whitelist:
          ipAllowList:
            sourceRange:
              - "100.64.0.0/10"
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
