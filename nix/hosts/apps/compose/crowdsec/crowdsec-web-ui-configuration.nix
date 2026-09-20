{ config }:
# Kept in its own file for the same reason as auth/authelia-configuration.nix: ordinary
# Nix interpolation for both the sops placeholders and the domain-derived URLs below,
# without cluttering default.nix.
''
  server:
    port: 3000
    basePath: ""
  storage:
    dataDir: /app/data
    geonamesDir: /app/geonames
  ui:
    timeZone: browser
    timeFormat: browser
    readOnly: false
  auth:
    enabled: true
    oidc:
      issuerUrl: "https://auth.${config.domains.main}"
      clientId: "${config.sops.placeholder."compose-stacks/crowdsec/oidc/client_id"}"
      # Unlike clientId/username below, this field takes a file reference directly
      # (per the app's own docs) rather than an inline value — points straight at the
      # raw sops secret, no placeholder substitution needed for this one.
      clientSecret:
        file: /run/secrets/oidc_client_secret
      scope: openid profile email groups
      groupsClaim: groups
      # Same lldap groups already bootstrapped for Grafana's role mapping in the auth
      # stack. Unlike Grafana's non-strict mode, unmatchedRole: deny is the right
      # default here — this is a security tool's admin UI, not a dashboard.
      adminGroups:
        - sysadmin
      readOnlyGroups:
        - sysviewer
      unmatchedRole: deny
  notifications:
    allowPrivateAddresses: true
    debugPayloads: false
  updates:
    enabled: true
  crowdsec:
    simulationsEnabled: false
    alertFilters: {}
    sync:
      lookback: 5d
      refreshInterval: 30s
      manualRefreshEnabled: false
      idleRefreshInterval: 5m
      idleThreshold: 2m
      requestTimeout: 30s
      bouncerPropagationDelay: 15s
      metricsRequestTimeout: 5s
      heartbeatInterval: 30s
      alertSyncChunk: 12h
      alertSyncMinChunk: 15m
      reconcileWindow: 1h
      reconcileRecentAge: 1d
      reconcileRecentInterval: 15m
      reconcileActiveInterval: 5m
      reconcileOldInterval: 3h
      reconcileWindowsPerRefresh: 2
      bootstrapRetryDelay: 30s
      bootstrapRetryEnabled: true
  instances:
    - id: default
      name: CrowdSec
      lapi:
        url: http://crowdsec:8080
        auth:
          type: password
          username: "${config.sops.placeholder."compose-stacks/crowdsec/webui/lapi_user"}"
          password:
            env: CROWDSEC_LAPI_PASSWORD
      # Same container/port the legacy setup's Uptime Kuma monitor already checked
      # (crowdsec:6060/metrics) — CrowdSec's own Prometheus endpoint, enabled at
      # level: full in config.yaml.local so this actually has data to show.
      metrics:
        - url: http://crowdsec:6060/metrics
''
