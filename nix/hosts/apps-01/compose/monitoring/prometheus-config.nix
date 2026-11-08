{ config }:
# Prometheus's config, as a sops template rather than a plain file next to the compose
# file: two of prod's scrape jobs carry secrets in places Prometheus has no `_file`
# variant for (healthchecks.io's metrics path), so the file itself has to be rendered.
#
# Node and cAdvisor metrics are absent on purpose: every host pushes them through
# Grafana Alloy's remote_write (see modules/nixos/grafana-alloy.nix) rather than being
# scraped here.
let
  secret = name: config.sops.placeholder."compose-stacks/monitoring/prometheus/${name}";
in
''
  global:
    scrape_interval: 15s
    evaluation_interval: 30s

  scrape_configs:
    - job_name: "prometheus"
      static_configs:
        - targets: ["localhost:9090"]
    - job_name: "traefik"
      static_configs:
        - targets: ["traefik:8080"]
    # Gatus's check results (gatus_results_*), which Grafana alerts on: Gatus itself
    # notifies no one. See gatus-config.nix.
    - job_name: "gatus"
      scrape_interval: 30s
      static_configs:
        - targets: ["gatus:8080"]
    - job_name: "crowdsec"
      static_configs:
        - targets: ["crowdsec:6060"]
    - job_name: "ntfy"
      static_configs:
        - targets: ["ntfy:9090"]
    # minecraft-prometheus-exporter plugin on the main server (not mc-usw, which doesn't
    # run it), reached over the shared `monitoring` network. The label is prod's, kept
    # literal so the series continue the same ones across the cutover.
    - job_name: "minecraft"
      static_configs:
        - targets: ["minecraft:9940"]
          labels:
            server_name: "mc.snyssen.be"
    # Jellyfin's own /metrics, which it only serves with EnableMetrics set in its
    # system.xml. Prod scrapes it, so the setting is on there and comes back with the
    # `streaming-config` restore.
    - job_name: "jellyfin"
      static_configs:
        - targets: ["jellyfin:8096"]
    # Needs `telemetry.metrics` in Authelia's config (auth/authelia-configuration.nix).
    - job_name: "authelia"
      static_configs:
        - targets: ["authelia:9959"]
    # The on-site restic REST server both hosts back up to.
    - job_name: "rest_server"
      static_configs:
        - targets: ["backup.snyssen.be:8000"]
    # Home Assistant on its own VM, with a long-lived access token.
    - job_name: "hass"
      metrics_path: /api/prometheus
      authorization:
        credentials: "${secret "hass_token"}"
      scheme: http
      static_configs:
        - targets: ["hass.snyssen.be:8123"]
    - job_name: "healthchecks"
      scrape_interval: 60s
      scheme: https
      metrics_path: /projects/${secret "healthchecks/project_uuid"}/metrics/${secret "healthchecks/api_key"}
      static_configs:
        - targets: ["healthchecks.io"]

  rule_files:
    - node_rules.yml
''
