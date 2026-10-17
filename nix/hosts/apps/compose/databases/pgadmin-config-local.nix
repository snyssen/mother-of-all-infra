{ config }:
# Kept in its own file for the same reason as auth/authelia-configuration.nix and
# crowdsec/crowdsec-web-ui-configuration.nix: ordinary Nix interpolation for both the
# sops placeholders and the domain-derived URLs, without cluttering default.nix.
#
# Mirrors the legacy role's pgadmin/config_local.py (same OAuth2 provider shape,
# proven working in prod) with one simplification: dropped the per-provider
# `OAUTH2_AUTO_CREATE_USER: "False"` key the legacy file also carried — pgAdmin's
# OAUTH2_CONFIG schema doesn't document that key at the per-provider level, and the
# module-level `OAUTH2_AUTO_CREATE_USER = True` below is what's actually authoritative
# (confirmed this is what makes "login via OIDC with no pre-provisioned local account"
# work) — keeping both was likely leftover copy-paste, not a deliberate two-state knob.
''
  OAUTH2_CONFIG = [
      {
          'OAUTH2_NAME': 'Authelia',
          'OAUTH2_DISPLAY_NAME': 'Authelia',
          'OAUTH2_CLIENT_ID': '${config.sops.placeholder."compose-stacks/databases/pgadmin/oidc/client_id"}',
          'OAUTH2_CLIENT_SECRET': '${config.sops.placeholder."compose-stacks/databases/pgadmin/oidc/client_secret"}',
          'OAUTH2_TOKEN_URL': 'https://auth.${config.domains.main}/api/oidc/token',
          'OAUTH2_AUTHORIZATION_URL': 'https://auth.${config.domains.main}/api/oidc/authorization',
          'OAUTH2_SERVER_METADATA_URL': 'https://auth.${config.domains.main}/.well-known/oauth-authorization-server',
          'OAUTH2_API_BASE_URL': 'https://auth.${config.domains.main}',
          'OAUTH2_USERINFO_ENDPOINT': 'https://auth.${config.domains.main}/api/oidc/userinfo',
          'OAUTH2_SCOPE': 'openid profile groups email',
          'OAUTH2_USERNAME_CLAIM': 'preferred_username',
          'OAUTH2_BUTTON_COLOR': 'None',
          'OAUTH2_ICON': 'None'
      }
  ]
  OAUTH2_AUTO_CREATE_USER = True
''
