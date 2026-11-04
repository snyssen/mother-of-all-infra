{ config, ... }:
let
  composeFile = "${./.}/docker-compose.yaml";
  host = "events.${config.domains.team}";
in
{
  # All carried over unchanged from the legacy vault, so the imported database and the
  # OIDC client keep matching what prod used.
  sops.secrets = {
    "compose-stacks/rallly/secret" = {
      sopsFile = ../../data/rallly.yaml;
    };
    "compose-stacks/rallly/oidc/client_id" = {
      sopsFile = ../../data/rallly.yaml;
    };
    "compose-stacks/rallly/oidc/client_secret" = {
      sopsFile = ../../data/rallly.yaml;
    };
    # Hashed, for Authelia's own client config — same plaintext/hash split as every
    # other OIDC client on this host.
    "compose-stacks/rallly/oidc/client_secret_hash" = {
      sopsFile = ../../data/rallly.yaml;
    };
  };

  sops.templates."compose-rallly.env".content = ''
    DATABASE_URL=postgres://rallly:${
      config.sops.placeholder."compose-stacks/databases/postgres/passwords/rallly"
    }@postgres/rallly
    SECRET_PASSWORD=${config.sops.placeholder."compose-stacks/rallly/secret"}
    NEXT_PUBLIC_BASE_URL=https://${host}
    NOREPLY_EMAIL=rally@${config.domains.main}
    SUPPORT_EMAIL=${config.sops.placeholder."smtp/to"}
    SMTP_HOST=${config.sops.placeholder."smtp/host"}
    SMTP_PORT=${config.sops.placeholder."smtp/port"}
    SMTP_USER=${config.sops.placeholder."smtp/user"}
    SMTP_PWD=${config.sops.placeholder."smtp/password"}
    OIDC_ISSUER_URL=https://auth.${config.domains.team}
    OIDC_DISCOVERY_URL=https://auth.${config.domains.team}/.well-known/openid-configuration
    OIDC_CLIENT_ID=${config.sops.placeholder."compose-stacks/rallly/oidc/client_id"}
    OIDC_CLIENT_SECRET=${config.sops.placeholder."compose-stacks/rallly/oidc/client_secret"}
  '';

  # No forwardAuth: Rallly's own OIDC login is the gate. /register is left unrouted as
  # on prod, on top of REGISTRATION_ENABLED=false.
  reverseProxy.dynamicConfig.rallly = ''
    http:
      routers:
        rallly:
          rule: "Host(`${host}`) && !PathPrefix(`/register`)"
          entryPoints:
            - websecure
          service: rallly
          tls:
            certResolver: le_team
      services:
        rallly:
          loadBalancer:
            servers:
              - url: "http://rallly:3000"
  '';

  compose-stacks.stacks.rallly = {
    restartTriggers = [
      ../../data/rallly.yaml
      ../../data/databases.yaml
      ../../data/common.yaml
      config.sops.templates."compose-rallly.env".content
    ];
    inherit composeFile;
    environmentFile = config.sops.templates."compose-rallly.env".path;
    dockerNetworks = [
      "web"
      "db"
    ];
    extraAfter = [ "reverse-proxy-dynamic-config.service" ];
  };
}
