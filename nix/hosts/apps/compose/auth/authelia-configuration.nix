{
  config,
  ldapBaseDn,
  ldapBindUserDn,
}:
# Authelia's config file, kept in its own file rather than inline in default.nix — the
# real Authelia config this is modeled on runs 722 lines once every app's
# access_control rules and OIDC clients are added, which would make default.nix
# unreadable. A plain `.nix` file (imported and called from default.nix) rather than a
# separate templated text file: it can use ordinary Nix string interpolation directly
# (${config.sops.placeholder."..."} etc.), and later, if this keeps growing, can be
# split into functions (e.g. one for rendering an OIDC client block, called once per
# app) to avoid repetition — not needed yet with a single client, but the file shape
# supports it without another rewrite.
#
# Secrets are embedded directly (via sops placeholders, resolved by sops-nix at
# activation time since this becomes the content of a sops.templates entry) rather
# than using Authelia's per-field `_FILE` env var convention — equally secure (this
# file gets the same activation-time permission handling as any other sops.templates
# output), but far fewer moving parts than a separate bind-mounted file per secret.
''
  theme: auto
  default_2fa_method: totp

  log:
    level: info

  totp:
    disable: false
    issuer: Authelia

  webauthn:
    disable: false

  password_policy:
    zxcvbn:
      enabled: true
      min_score: 3

  privacy_policy:
    enabled: false

  # Top-level jwt_secret is deprecated since Authelia 4.38 in favor of the
  # identity_validation.reset_password.jwt_secret below (same underlying secret as
  # the original config's `backbone__authelia__jwt_secret`, which was also reused for
  # both fields) — Authelia refuses to auto-map when both are present, so only the
  # non-deprecated one is set here.
  identity_validation:
    reset_password:
      jwt_secret: "${config.sops.placeholder."compose-stacks/auth/authelia/jwt_secret"}"

  authentication_backend:
    ldap:
      address: "ldap://lldap:3890"
      implementation: lldap
      base_dn: "${ldapBaseDn}"
      user: "${ldapBindUserDn}"
      password: "${config.sops.placeholder."compose-stacks/auth/ldap_bind/password"}"

  session:
    secret: "${config.sops.placeholder."compose-stacks/auth/authelia/session_secret"}"
    cookies:
      - domain: "${config.domains.main}"
        authelia_url: "https://auth.${config.domains.main}"
      # The team domain's own portal, as on prod: a cookie only ever covers its own
      # domain, so team-domain apps need a login page under that domain too. It must be
      # a separate registrable domain, not a subdomain of the main one — Authelia
      # rejects two cookie domains that share a scope.
      - domain: "${config.domains.team}"
        authelia_url: "https://auth.${config.domains.team}"
    name: authelia_session
    same_site: lax
    inactivity: 45m
    expiration: 1h
    remember_me: 1M
    redis:
      host: authelia_redis

  storage:
    encryption_key: "${config.sops.placeholder."compose-stacks/auth/authelia/storage_encryption_key"}"
    postgres:
      address: "tcp://postgres:5432"
      database: authelia
      username: authelia
      password: "${config.sops.placeholder."compose-stacks/databases/postgres/passwords/authelia"}"

  notifier:
    # Authelia treats a failed provider startup check as FATAL: it logs "Error occurred
    # running a startup check" and then exits with "One or more providers had fatal
    # failures performing startup checks". With `restart: unless-stopped` that becomes a
    # crash loop, so an unreachable SMTP relay takes down *all* authentication on this
    # host — every forwardAuth-gated route and every OIDC client with it.
    #
    # That is a bad dependency for an SSO gateway: a cold boot, or any redeploy, during
    # a mail-relay outage locks everyone out of everything. It bit us on 2026-10-21 —
    # the relay had been unreachable for a while, Authelia only noticed because a deploy
    # restarted it, and auth.${config.domains.main} went down while prod survived purely
    # because it had not been restarted.
    #
    # Skipping the check degrades the failure instead: Authelia serves normally and mail
    # fails at send time, so password resets and 2FA enrolment break rather than login.
    # The error is still logged on every send attempt, and container logs are queryable
    # per-service now (see nix/modules/nixos/grafana-alloy.nix), so it stays visible.
    disable_startup_check: true
    smtp:
      # submission:// (STARTTLS, port 587) matches the most common self-hosted SMTP
      # relay setup — switch to submissions:// if the actual provider needs implicit
      # TLS (typically port 465) instead.
      address: "submission://${config.sops.placeholder."smtp/host"}:${
        config.sops.placeholder."smtp/port"
      }"
      username: "${config.sops.placeholder."smtp/user"}"
      password: "${config.sops.placeholder."smtp/password"}"
      sender: "Authelia <auth@${config.sops.placeholder."smtp/from_domain"}>"

  # Deny by default, as on prod: a forwardAuth-gated route is reachable only if a rule
  # below names its host. That makes adding a gated route a two-place change (its
  # stack's dynamicConfig *and* a rule here), but the failure mode of forgetting is a
  # route nobody can open, noticed on first use — instead of an admin tool quietly open
  # to every account in LDAP, which is what a permissive default turns the same
  # mistake into. Rules for prod hosts not yet migrated (dnd, speedtest-tracker,
  # garage...) are added with their stacks, not ahead of them.
  #
  # Only forwardAuth goes through these rules. OIDC logins are governed by each
  # client's own authorization_policy further down — the admin tools that log in that
  # way (Grafana, pgAdmin, CrowdSec) are restricted there.
  #
  # Rules are first-match-wins, so wherever two rules share a host, the narrower one
  # comes first. Note that `authelia validate-config` does NOT check `policy:` values
  # here (verified against 4.39.28: a rule with `policy: bypasss` validates clean), so
  # a typo in one of these is silent — unlike the same typo in a client's
  # `authorization_policy`, which is rejected.
  access_control:
    default_policy: deny
    # The same three ranges as the `lan-whitelist` middleware (compose/monitoring):
    # LAN, the whole Docker pool, and the tailnet. Authelia sees the real client
    # address through Traefik's forwarded headers.
    networks:
      - name: internal
        networks:
          - "192.168.1.0/24"
          - "172.16.0.0/12"
          - "100.64.0.0/10"
    rules:
      # Open to any registered user with a single factor, carried over from prod's
      # "general services" rule.
      - domain:
          - "pdf.${config.domains.main}"
        policy: one_factor
      # FoundryVTT, players only. Carried over from prod.
      - domain:
          - "dnd.${config.domains.main}"
        policy: one_factor
        subject:
          - ["group:foundry_player"]
      # Admin tools behind forwardAuth. routing is the Traefik dashboard (served from
      # the argunix fragment in compose/reverse-proxy).
      - domain:
          - "routing.${config.domains.main}"
          - "prometheus.${config.domains.main}"
          - "uptime.${config.domains.main}"
          - "speedtest-tracker.${config.domains.main}"
          - "backrest.${config.domains.main}"
          - "garage.${config.domains.main}"
          - "crowdsec-ui.${config.domains.main}"
        policy: two_factor
        subject:
          - ["group:sysadmin"]
      # Machine-to-machine calls from the *arr apps to the download clients, and from
      # lidatube to lidarr, carry no session — let them through from inside. On this
      # host most of these share the vpn container's network namespace and never touch
      # Traefik, but configs restored from prod may still use the public names. Must
      # come before the rule below, which matches the same hosts.
      - domain:
          - "torrent.${config.domains.main}"
          - "usenet.${config.domains.main}"
          - "lidarr.${config.domains.main}"
        policy: bypass
        networks:
          - internal
      - domain:
          - "torrent.${config.domains.main}"
          - "usenet.${config.domains.main}"
          - "sonarr.${config.domains.main}"
          - "radarr.${config.domains.main}"
          - "lidarr.${config.domains.main}"
          - "prowlarr.${config.domains.main}"
          - "bazarr.${config.domains.main}"
          - "lidatube.${config.domains.main}"
          - "lidify.${config.domains.main}"
          - "yt.${config.domains.main}"
        policy: two_factor
        subject:
          - ["group:sysadmin"]
          - ["group:media_manager"]
      # Django admin, sysadmins only, then the rest of the host handed to the app's own
      # OIDC login. The middleware on these two routers exists *only* for the /admin
      # rule; without the bypass it would put a second, redundant Authelia login in
      # front of the OIDC flow and break the mobile/API clients, which have no browser
      # session to offer.
      - domain:
          - "paperless.${config.domains.main}"
          - "recipes.${config.domains.main}"
        policy: two_factor
        subject:
          - ["group:sysadmin"]
        resources:
          # IMPORTANT: single quotes -> https://www.authelia.com/configuration/prologue/common/#regular-expressions
          - '^/admin.*$'
      - domain:
          - "paperless.${config.domains.main}"
          - "recipes.${config.domains.main}"
        policy: bypass

  identity_providers:
    oidc:
      hmac_secret: "${config.sops.placeholder."compose-stacks/auth/oidc/hmac_secret"}"
      # jwks[].key takes inline PEM only (no _FILE-style path field). A real
      # multi-line PEM can't go through sops-nix's placeholder substitution here —
      # it's a plain text replace with no YAML-indentation awareness, so the
      # continuation lines of a block scalar would come out mis-indented. Sidestepped
      # by storing the secret itself pre-escaped (real newlines replaced with literal
      # `\n`, see the comment on this secret in default.nix) and placing it in a
      # double-quoted YAML string instead of a block scalar: substitution stays on
      # one line, and it's Authelia's own YAML parser (nothing experimental, just
      # standard YAML) that decodes the `\n` escapes back into real newlines when it
      # loads this file.
      jwks:
        - key_id: main
          algorithm: RS256
          key: "${config.sops.placeholder."compose-stacks/auth/oidc/issuer_private_key"}"
      # Group-scoped policies, each carried over from the legacy config. The built-in
      # `two_factor` lets in any account in LDAP, so it only suits apps whose own
      # permissions do the rest (Nextcloud, Actual); anything narrower needs one of
      # these. Every group named here already exists — see lldap-bootstrap/group-configs/.
      authorization_policies:
        # The admin tools that log in through OIDC rather than forwardAuth: Grafana,
        # pgAdmin and CrowdSec's web UI. Same group and factor as the forwardAuth admin
        # rule in access_control above.
        sysadmin_policy:
          default_policy: deny
          rules:
            - policy: two_factor
              subject:
                - ["group:sysadmin"]
        # PeerTube and Audiobookshelf.
        media_policy:
          default_policy: deny
          rules:
            - policy: two_factor
              subject:
                - ["group:media_viewer"]
        # one_factor, deliberately: Immich's mobile app drives this same OIDC flow, and
        # a second factor in that embedded webview is painful enough that prod does
        # without.
        photos_policy:
          default_policy: deny
          rules:
            - policy: one_factor
              subject:
                - ["group:photos_user"]
        # Unlike photos_policy, this one keeps the second factor: Paperless is only
        # ever driven from a real browser, so there is no embedded-webview problem to
        # work around, and the documents are the most sensitive data on the host.
        # Carried over from the legacy config unchanged. The group already exists —
        # see lldap-bootstrap/group-configs/paperless_user.json.
        paperless_policy:
          default_policy: deny
          rules:
            - policy: two_factor
              subject:
                - ["group:paperless_user"]
        # one_factor, carried over from the legacy config unchanged. The group already
        # exists — see lldap-bootstrap/group-configs/recipes_user.json.
        recipes_policy:
          default_policy: deny
          rules:
            - policy: one_factor
              subject:
                - ["group:recipes_user"]
        # one_factor, carried over from the legacy config unchanged. The group already
        # exists — see lldap-bootstrap/group-configs/team_wiki_member.json.
        team_wiki_policy:
          default_policy: deny
          rules:
            - policy: one_factor
              subject:
                - ["group:team_wiki_member"]
        # Rallly. one_factor, carried over from the legacy config unchanged. The group
        # already exists — see lldap-bootstrap/group-configs/team_member.json.
        team_member_policy:
          default_policy: deny
          rules:
            - policy: one_factor
              subject:
                - ["group:team_member"]
        # Matrix, through MAS. one_factor, carried over from the legacy config unchanged.
        # The group already exists — see lldap-bootstrap/group-configs/matrix_user.json.
        matrix_policy:
          default_policy: deny
          rules:
            - policy: one_factor
              subject:
                - ["group:matrix_user"]
        # one_factor, carried over from the legacy config unchanged. The group already
        # exists — see lldap-bootstrap/group-configs/dawarich_user.json.
        dawarich_policy:
          default_policy: deny
          rules:
            - policy: one_factor
              subject:
                - ["group:dawarich_user"]
      clients:
        - client_name: Grafana
          client_id: "${config.sops.placeholder."compose-stacks/auth/oidc/grafana/client_id"}"
          client_secret: "${
            config.sops.placeholder."compose-stacks/auth/oidc/grafana/client_secret_hash"
          }"
          authorization_policy: sysadmin_policy
          redirect_uris:
            - "https://monitor.${config.domains.main}/login/generic_oauth"
          scopes:
            - openid
            - profile
            - email
            - groups
          userinfo_signed_response_alg: none
          token_endpoint_auth_method: client_secret_post
        - client_name: CrowdSec
          client_id: "${config.sops.placeholder."compose-stacks/crowdsec/oidc/client_id"}"
          client_secret: "${
            config.sops.placeholder."compose-stacks/crowdsec/oidc/client_secret_hash"
          }"
          authorization_policy: sysadmin_policy
          redirect_uris:
            - "https://crowdsec-ui.${config.domains.main}/api/auth/oidc/callback"
          scopes:
            - openid
            - profile
            - email
            - groups
          userinfo_signed_response_alg: none
          token_endpoint_auth_method: client_secret_post
        # Redirect URI per peertube-plugin-auth-openid-connect's documented callback
        # route — unverified against a live PeerTube instance (the legacy role's own
        # compose file flagged this exact env-var-based OIDC config as possibly not
        # actually wired up: "TODO: remove ? ... config can probably only be done
        # through UI"). If login fails after deploy, check PeerTube's own plugin
        # settings page for the callback path it actually expects.
        - client_name: PeerTube
          client_id: "${config.sops.placeholder."compose-stacks/streaming/peertube/oidc/client_id"}"
          client_secret: "${
            config.sops.placeholder."compose-stacks/streaming/peertube/oidc/client_secret_hash"
          }"
          authorization_policy: media_policy
          redirect_uris:
            - "https://peertube.${config.domains.main}/plugins/auth-openid-connect/router/code-cb"
          scopes:
            - openid
            - profile
            - email
            - groups
          userinfo_signed_response_alg: none
          token_endpoint_auth_method: client_secret_post
        # Carried over from prod, which this host had missed. Two redirect URIs: the web
        # callback, and the one Audiobookshelf's mobile apps go through. No
        # token_endpoint_auth_method, so client_secret_basic, as on prod.
        - client_name: Audiobookshelf
          client_id: "${
            config.sops.placeholder."compose-stacks/streaming/audiobookshelf/oidc/client_id"
          }"
          client_secret: "${
            config.sops.placeholder."compose-stacks/streaming/audiobookshelf/oidc/client_secret_hash"
          }"
          authorization_policy: media_policy
          redirect_uris:
            - "https://audiobooks.${config.domains.main}/auth/openid/callback"
            - "https://audiobooks.${config.domains.main}/auth/openid/mobile-redirect"
          scopes:
            - openid
            - profile
            - groups
            - email
          userinfo_signed_response_alg: none
        # Unlike the other clients above, no token_endpoint_auth_method override —
        # pgAdmin's OAuth2 client correctly uses Authelia's default
        # (client_secret_basic) on its own, matching the legacy role's own
        # proven-working client config.
        - client_name: pgAdmin
          client_id: "${config.sops.placeholder."compose-stacks/databases/pgadmin/oidc/client_id"}"
          client_secret: "${
            config.sops.placeholder."compose-stacks/databases/pgadmin/oidc/client_secret_hash"
          }"
          authorization_policy: sysadmin_policy
          redirect_uris:
            - "https://pgadmin.${config.domains.main}/oauth2/authorize"
          scopes:
            - openid
            - profile
            - groups
            - email
          userinfo_signed_response_alg: none
        # Three redirect URIs, not one: besides the two web routes, `app.immich://` is
        # the mobile app's custom URL scheme. Dropping it breaks phone login only, and
        # silently — the web UI keeps working, so it would not show up in testing here.
        - client_name: immich
          client_id: "${config.sops.placeholder."compose-stacks/immich/oidc/client_id"}"
          client_secret: "${config.sops.placeholder."compose-stacks/immich/oidc/client_secret_hash"}"
          authorization_policy: photos_policy
          redirect_uris:
            - "app.immich:///oauth-callback"
            - "https://photos.${config.domains.main}/auth/login"
            - "https://photos.${config.domains.main}/user-settings"
          scopes:
            - openid
            - profile
            - email
          userinfo_signed_response_alg: none
          token_endpoint_auth_method: client_secret_post
        - client_name: Nextcloud
          client_id: "${config.sops.placeholder."compose-stacks/nextcloud/oidc/client_id"}"
          client_secret: "${
            config.sops.placeholder."compose-stacks/nextcloud/oidc/client_secret_hash"
          }"
          authorization_policy: two_factor
          redirect_uris:
            - "https://cloud.${config.domains.main}/apps/user_oidc/code"
          scopes:
            - openid
            - profile
            - email
            - groups
          userinfo_signed_response_alg: none
          token_endpoint_auth_method: client_secret_post
        # The trailing slash on the redirect URI is load-bearing — it is the exact
        # callback allauth's openid_connect provider registers for provider_id
        # `authelia` (see PAPERLESS_SOCIALACCOUNT_PROVIDERS in compose/paperless), and
        # Authelia matches redirect_uris literally.
        - client_name: Paperless
          client_id: "${config.sops.placeholder."compose-stacks/paperless/oidc/client_id"}"
          client_secret: "${
            config.sops.placeholder."compose-stacks/paperless/oidc/client_secret_hash"
          }"
          authorization_policy: paperless_policy
          redirect_uris:
            - "https://paperless.${config.domains.main}/accounts/oidc/authelia/login/callback/"
          scopes:
            - openid
            - profile
            - email
            - groups
          userinfo_signed_response_alg: none
          token_endpoint_auth_method: client_secret_post
        # client_secret_basic, not the client_secret_post most clients here override
        # to: Actual sets no auth method, so openid-client falls back to its default of
        # basic — which is also what the legacy client entry used.
        - client_name: Actual Budget
          client_id: "${config.sops.placeholder."compose-stacks/actual-budget/oidc/client_id"}"
          client_secret: "${
            config.sops.placeholder."compose-stacks/actual-budget/oidc/client_secret_hash"
          }"
          authorization_policy: two_factor
          redirect_uris:
            - "https://actual.${config.domains.main}/openid/callback"
          scopes:
            - openid
            - profile
            - groups
            - email
          userinfo_signed_response_alg: none
          token_endpoint_auth_method: client_secret_basic
        # Same callback shape as Paperless (both are allauth with provider_id
        # `authelia`), trailing slash included. client_secret_basic is what the legacy
        # entry got by leaving the method unset; Tandoor's allauth worked against it.
        - client_name: Recipes
          client_id: "${config.sops.placeholder."compose-stacks/recipes/oidc/client_id"}"
          client_secret: "${config.sops.placeholder."compose-stacks/recipes/oidc/client_secret_hash"}"
          authorization_policy: recipes_policy
          redirect_uris:
            - "https://recipes.${config.domains.main}/accounts/oidc/authelia/login/callback/"
          scopes:
            - openid
            - profile
            - email
            - groups
          userinfo_signed_response_alg: none
          token_endpoint_auth_method: client_secret_basic
        # The UUID in the redirect URI is the id of the login strategy inside Wiki.js's
        # own database, carried over unchanged from prod — so it is only right while
        # that strategy is the imported one. Recreating it in the wiki's admin UI gives
        # it a new id, and this URI with it.
        - client_name: team_wiki
          client_id: "${config.sops.placeholder."compose-stacks/team-wiki/oidc/client_id"}"
          client_secret: "${
            config.sops.placeholder."compose-stacks/team-wiki/oidc/client_secret_hash"
          }"
          authorization_policy: team_wiki_policy
          redirect_uris:
            - "https://${config.domains.team}/login/782aa720-97a8-439f-949e-fd75fed1085c/callback"
          scopes:
            - openid
            - profile
            - groups
            - email
          userinfo_signed_response_alg: none
          token_endpoint_auth_method: client_secret_post
        - client_name: rallly
          client_id: "${config.sops.placeholder."compose-stacks/rallly/oidc/client_id"}"
          client_secret: "${config.sops.placeholder."compose-stacks/rallly/oidc/client_secret_hash"}"
          authorization_policy: team_member_policy
          redirect_uris:
            - "https://events.${config.domains.team}/api/auth/callback/oidc"
          scopes:
            - openid
            - profile
            - email
          token_endpoint_auth_method: client_secret_post
        # No token_endpoint_auth_method, so client_secret_basic, as on prod.
        - client_name: dawarich
          client_id: "${config.sops.placeholder."compose-stacks/dawarich/oidc/client_id"}"
          client_secret: "${
            config.sops.placeholder."compose-stacks/dawarich/oidc/client_secret_hash"
          }"
          authorization_policy: dawarich_policy
          redirect_uris:
            - "https://location.${config.domains.main}/users/auth/openid_connect/callback"
          scopes:
            - openid
            - profile
            - email
        # MAS's upstream provider, so Synapse's logins go through Authelia. The last
        # path segment of the redirect URI is the provider's id in mas-config.yaml
        # (matrix__mas__oidc_id on prod), fixed because MAS links users to it.
        - client_name: Synapse
          client_id: "${config.sops.placeholder."compose-stacks/matrix/mas/oidc/client_id"}"
          client_secret: "${
            config.sops.placeholder."compose-stacks/matrix/mas/oidc/client_secret_hash"
          }"
          public: false
          authorization_policy: matrix_policy
          require_pkce: true
          pkce_challenge_method: S256
          redirect_uris:
            - "https://matrix-mas.${config.domains.main}/upstream/callback/01K8GGKK57BWVMVQ0C46QP5Z6Y"
          scopes:
            - openid
            - profile
            - email
            - groups
          response_types:
            - code
          grant_types:
            - refresh_token
            - authorization_code
          access_token_signed_response_alg: none
          userinfo_signed_response_alg: none
          token_endpoint_auth_method: client_secret_post
''
