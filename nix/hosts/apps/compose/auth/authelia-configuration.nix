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
    smtp:
      # submission:// (STARTTLS, port 587) matches the most common self-hosted SMTP
      # relay setup — switch to submissions:// if the actual provider needs implicit
      # TLS (typically port 465) instead.
      address: "submission://${config.sops.placeholder."smtp/host"}:${config.sops.placeholder."smtp/port"}"
      username: "${config.sops.placeholder."smtp/user"}"
      password: "${config.sops.placeholder."smtp/password"}"
      sender: "Authelia <auth@${config.domains.main}>"

  # deny with zero rules is rejected by Authelia's validator ("when no rules are
  # specified it must be 'two_factor' or 'one_factor'") — nothing is actually gated
  # yet anyway, since no access_control.rules or forwardAuth middleware references
  # this stack yet. two_factor becomes the real default once rules do get added.
  access_control:
    default_policy: two_factor

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
      clients:
        - client_name: Grafana
          client_id: "${config.sops.placeholder."compose-stacks/auth/oidc/grafana/client_id"}"
          client_secret: "${config.sops.placeholder."compose-stacks/auth/oidc/grafana/client_secret_hash"}"
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
''
