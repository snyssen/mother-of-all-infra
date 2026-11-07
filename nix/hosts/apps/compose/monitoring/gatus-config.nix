{ lib, config }:
# Gatus's config, as a sops template: the external endpoints carry the push token.
#
# Gatus replaces prod's Uptime Kuma. Kuma's monitors could only be created through its
# API (prod's Ansible collection does, and supports v1 only), while Gatus's config *is*
# the monitor list. It does no notifying: `alerting` is left out, Prometheus scrapes
# its /metrics and Grafana alerts, as with every other metric.
#
# The checks are prod's, one for one (their Ansible `uptime_kuma.monitor` tasks), on this
# host's domains. Not carried over: `Semaphore UI` (retired) and `unifi` (its controller
# isn't on this host; see "UniFi OS" in docs/hypervisor/apps-migration-plan.md).
let
  domain = config.domains.main;
  team = config.domains.team;

  # Kuma's http monitors pass on any 2xx after following redirects, and so do these.
  # A failed connection already fails the check before any condition is looked at.
  http = name: url: {
    inherit name url;
    group = "services";
    conditions = [ "[STATUS] < 300" ];
  };
  # Kuma's `keyword` type: a 2xx whose body contains the word.
  keyword =
    name: url: word:
    http name url
    // {
      conditions = [
        "[STATUS] < 300"
        "[BODY] == pat(*${word}*)"
      ];
    };
  infra = monitor: monitor // { group = "infrastructure"; };

  # A host behind Authelia's forwardAuth, as two checks. Authelia answers a request with
  # no session and no browser headers with a 401, never reaching the app (prod's Kuma
  # only "passed" these by following the redirect to Authelia's own login page).
  #   - the app itself, on its internal address, under prod's monitor name;
  #   - `<name> route`, on the public URL, expecting exactly that 401: Traefik routes the
  #     host and Authelia still guards it. It also goes red if the gate ever goes away.
  # Giving Gatus its own way through Authelia was the alternative, but Authelia's only
  # machine credential (an OAuth2 client-credentials token) is one-factor, which would
  # mean opening two-factor admin tools to a single secret.
  # The internal checks tie Gatus to this host; move them along with it.
  gated = name: internalUrl: publicUrl: [
    (http name internalUrl)
    {
      name = "${name} route";
      url = publicUrl;
      group = "routes";
      conditions = [ "[STATUS] == 401" ];
    }
  ];

  endpoints = lib.flatten [
    (http "authelia" "https://auth.${domain}")
    (http "ldap" "https://ldap.${domain}")
    # Internal: its metrics port is not routed.
    (http "crowdsec" "http://crowdsec:6060/metrics")
    (http "matrix" "https://element.${domain}")
    # Native on the host, as Traefik reaches it.
    (gated "backrest" "http://host.docker.internal:9898" "https://backrest.${domain}")
    (http "dashboard" "https://dash.${domain}")
    (http "minecraft" "https://mc.${domain}")
    (http "minecraft USW" "https://mc-usw.${domain}")
    (http "immich" "https://photos.${domain}")
    (http "personal website" "https://${domain}")
    (http "ntfy" "https://ntfy.${domain}")
    (gated "prometheus" "http://prometheus:9090/-/healthy" "https://prometheus.${domain}")
    (http "grafana" "https://monitor.${domain}")
    # Internal: Loki's public route is tailnet-only, and this check isn't on the tailnet.
    (keyword "loki" "http://loki:3100/ready" "ready")
    (http "umami" "https://umami.${domain}/api/heartbeat")
    (
      http "nextcloud" "https://cloud.${domain}/status.php"
      // {
        conditions = [
          "[STATUS] == 200"
          "[BODY].installed == true"
          "[BODY].maintenance == false"
          "[BODY].needsDbUpgrade == false"
        ];
      }
    )
    (http "actual-budget" "https://actual.${domain}")
    (http "dawarich" "https://location.${domain}")
    (http "team wiki" "https://${team}")
    (
      http "sharkey" "https://social.${domain}"
      // {
        # Off while the stack is (it isn't started until the cutover): a check that is
        # down by design would only teach everyone to ignore red.
        enabled = config.compose-stacks.stacks.sharkey.autostart;
      }
    )
    (http "foundryvtt" "https://dnd.${domain}")
    (keyword "jellyfin" "https://streaming.${domain}/health" "Healthy")
    # These live in the vpn container's network namespace, so that is their address.
    # The *arr apps' /ping needs no API key.
    (gated "bazarr" "http://vpn:6767" "https://bazarr.${domain}")
    # Not gated from here: Authelia lets lidarr through from the internal networks, for
    # lidatube's calls, and this check comes from one of them.
    (http "lidarr" "https://lidarr.${domain}")
    (gated "prowlarr" "http://vpn:9696/ping" "https://prowlarr.${domain}")
    (gated "radarr" "http://vpn:7878/ping" "https://radarr.${domain}")
    (gated "sonarr" "http://vpn:8989/ping" "https://sonarr.${domain}")
    (gated "pinchflat" "http://vpn:8945" "https://yt.${domain}")
    (http "peertube" "https://peertube.${domain}")
    # Only /admin is behind Authelia here (the rest is the app's own OIDC login), so the
    # app keeps its public check and the gate is checked on /admin.
    (http "paperless" "https://paperless.${domain}")
    {
      name = "paperless admin route";
      url = "https://paperless.${domain}/admin/";
      group = "routes";
      conditions = [ "[STATUS] == 401" ];
    }
    (http "rallly" "https://events.${team}")
    # Prod's s-pdf, now bentopdf on the same host name.
    (gated "s-pdf" "http://bentopdf:8080" "https://pdf.${domain}")
    (http "speedtest" "https://speedtest.${domain}")
    (http "speedtest-tracker" "https://speedtest-tracker.${domain}")
    (http "recipes" "https://recipes.${domain}")
    {
      name = "recipes admin route";
      url = "https://recipes.${domain}/admin/";
      group = "routes";
      conditions = [ "[STATUS] == 401" ];
    }
    # Native on the host, as Traefik reaches it.
    (gated "syncthing" "http://host.docker.internal:8384" "https://sync.${domain}")

    # What prod's monitoring__uptime_monitors lists: things that live off this host,
    # under their permanent names.
    (infra (http "restic rest server" "http://backup.snyssen.be:8000/metrics"))
    (infra (http "home assistant" "https://hass.snyssen.be"))
    (infra (http "technitium-primary" "http://192.168.1.2:5380/"))
    (infra (http "technitium-secondary" "http://192.168.1.3:5380/"))
    (infra (http "Ingress" "https://ingress.snyssen.be/ping"))
  ];

  token = config.sops.placeholder."compose-stacks/monitoring/gatus/push_token";

  # Kuma's push monitors. Gatus records a failure (metrics included) when nothing arrives
  # within `heartbeat.interval`, but only checks once per interval, so a missed push can
  # take up to twice that to show.
  externalEndpoints = [
    {
      # Pushed by nextcloud-cron every 5 minutes. Prod's monitor: 300s, 3 retries.
      name = "nextcloud background job";
      group = "jobs";
      inherit token;
      heartbeat.interval = "20m";
    }
  ]
  # One per Backrest plan, pushed by its hooks (backrest.nix), as prod's autorestic
  # pushed one per location. Daily backups; 26h is prod's 24h + 2h of leeway.
  ++ map (plan: {
    name = plan;
    group = "backups";
    inherit token;
    heartbeat.interval = "26h";
  }) (lib.attrNames config.backrest.plans);
in
# JSON is valid YAML. Note that Gatus expands `$VAR`s anywhere in its config: nothing
# here may contain a literal `$`.
builtins.toJSON {
  metrics = true;
  # Check history only, so the UI has something to show after a restart. Not backed up:
  # like Prometheus's TSDB, it is observability history, not configuration.
  storage = {
    type = "sqlite";
    path = "/data/data.db";
  };
  ui.title = "Uptime | ${domain}";
  endpoints = map (e: { interval = "60s"; } // e) endpoints;
  external-endpoints = externalEndpoints;
}
