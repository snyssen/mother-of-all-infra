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

  # two_factor is the real default: it is what every forwardAuth-gated route without
  # a matching rule below resolves to (prometheus, uptime, the *arr apps, backrest...).
  #
  # Rules are first-match-wins, so the order of the two paperless entries matters and
  # the specific one has to come first. Note that `authelia validate-config` does NOT
  # check `policy:` values here (verified against 4.39.28: a rule with `policy:
  # bypasss` validates clean), so a typo in one of these is silent — unlike the same
  # typo in a client's `authorization_policy`, which is rejected. Together they reproduce the legacy config: the
  # middleware on paperless' router exists *only* to keep Django's /admin away from
  # non-sysadmins, and everything else on that host is handed straight through to
  # Paperless, which does its own OIDC login. Without the bypass, the middleware would
  # put a second, redundant Authelia login in front of the OIDC flow and break the
  # mobile/API clients, which have no browser session to offer.
  access_control:
    default_policy: two_factor
    rules:
      # Django admin, sysadmins only. `recipes` shares this rule on prod and should be
      # added here when that stack migrates.
      - domain:
          - "paperless.${config.domains.main}"
        policy: two_factor
        subject:
          - ["group:sysadmin"]
        resources:
          # IMPORTANT: single quotes -> https://www.authelia.com/configuration/prologue/common/#regular-expressions
          - '^/admin.*$'
      - domain:
          - "paperless.${config.domains.main}"
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
      # First named policy on this host. Every client so far has used the built-in
      # `two_factor`, but Immich needs group-scoped access, which only a custom policy
      # can express. Carried over from the legacy config unchanged, including the
      # one_factor: Immich's mobile app drives this same OIDC flow, and a second factor
      # in that embedded webview is painful enough that prod deliberately does without.
      # The group itself already exists — see lldap-bootstrap/group-configs/photos_user.json.
      authorization_policies:
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
      clients:
        - client_name: Grafana
          client_id: "${config.sops.placeholder."compose-stacks/auth/oidc/grafana/client_id"}"
          client_secret: "${
            config.sops.placeholder."compose-stacks/auth/oidc/grafana/client_secret_hash"
          }"
          authorization_policy: two_factor
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
          authorization_policy: two_factor
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
          authorization_policy: two_factor
          redirect_uris:
            - "https://peertube.${config.domains.main}/plugins/auth-openid-connect/router/code-cb"
          scopes:
            - openid
            - profile
            - email
            - groups
          userinfo_signed_response_alg: none
          token_endpoint_auth_method: client_secret_post
        # Unlike the other clients above, no token_endpoint_auth_method override —
        # pgAdmin's OAuth2 client correctly uses Authelia's default
        # (client_secret_basic) on its own, matching the legacy role's own
        # proven-working client config.
        - client_name: pgAdmin
          client_id: "${config.sops.placeholder."compose-stacks/databases/pgadmin/oidc/client_id"}"
          client_secret: "${
            config.sops.placeholder."compose-stacks/databases/pgadmin/oidc/client_secret_hash"
          }"
          authorization_policy: two_factor
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
''
