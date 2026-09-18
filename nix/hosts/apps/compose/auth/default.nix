{
  lib,
  config,
  pkgs,
  ...
}:
let
  composeFile = "${./.}/docker-compose.yaml";

  # Pinned to the permanent domain rather than config.domains.main (currently a temp
  # test domain, see reverse-proxy's argunix fragment for the same reasoning): the LDAP
  # base DN defines the structure of the whole directory tree, and changing it later
  # would mean re-provisioning it rather than just re-pointing a hostname.
  ldapBaseDomain = "snyssen.be";
  ldapBaseDn = lib.concatMapStringsSep "," (part: "dc=${part}") (
    lib.splitString "." ldapBaseDomain
  );
  ldapBindUserDn = "uid=authelia,ou=people,${ldapBaseDn}";
in
{
  sops.secrets = {
    "compose-stacks/auth/authelia/jwt_secret" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-auth.service" ];
    };
    "compose-stacks/auth/authelia/session_secret" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-auth.service" ];
    };
    "compose-stacks/auth/authelia/storage_encryption_key" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-auth.service" ];
    };
    "compose-stacks/auth/oidc/hmac_secret" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-auth.service" ];
    };
    # Value must be stored pre-escaped: the PEM with every real newline replaced by
    # the two literal characters `\n`, wrapped in single quotes when editing via
    # `just sops-update` (single-quoted YAML doesn't interpret `\n`, so the secret
    # keeps the literal backslash-n instead of sops turning it back into a real
    # multi-line string). See the jwks.key comment in authelia-configuration.nix for
    # why. Generate the value from an existing PEM file with:
    #   perl -0pe 's/\n/\\n/g' key.pem
    "compose-stacks/auth/oidc/issuer_private_key" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-auth.service" ];
    };
    "compose-stacks/auth/oidc/grafana/client_id" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-auth.service" ];
    };
    "compose-stacks/auth/oidc/grafana/client_secret_hash" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-auth.service" ];
    };
    # Plaintext, shared with `monitoring` (Grafana needs the plaintext; Authelia only
    # ever sees/stores the hash above) — single source of truth, referenced from both
    # stacks rather than duplicated.
    "compose-stacks/auth/oidc/grafana/client_secret" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [
        "compose-auth.service"
        "compose-monitoring.service"
      ];
    };
    "compose-stacks/auth/lldap/jwt_secret" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-auth.service" ];
    };
    "compose-stacks/auth/lldap/key_seed" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-auth.service" ];
    };
    "compose-stacks/auth/lldap/admin_password" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-auth.service" ];
    };
    # Shared between lldap (the account's actual password, set via bootstrap.sh) and
    # Authelia (the same password, used to bind as that account) — one secret, two
    # consumers, not duplicated.
    "compose-stacks/auth/ldap_bind/password" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [
        "compose-auth.service"
        "auth-lldap-bootstrap.service"
      ];
    };
  };

  # Non-secret path variables plus lldap's own secrets (bare-forwarded, matching every
  # other stack's convention) — kept separate from the Authelia config template below
  # since these two files serve different consumers (docker-compose.yaml vs Authelia
  # itself) and mixing them would make it harder to see which secret feeds what.
  sops.templates."compose-auth.env".content = ''
    LLDAP_JWT_SECRET=${config.sops.placeholder."compose-stacks/auth/lldap/jwt_secret"}
    LLDAP_KEY_SEED=${config.sops.placeholder."compose-stacks/auth/lldap/key_seed"}
    LLDAP_LDAP_USER_PASS=${config.sops.placeholder."compose-stacks/auth/lldap/admin_password"}
    LLDAP_ADMIN_PASSWORD=${config.sops.placeholder."compose-stacks/auth/lldap/admin_password"}
    LLDAP_DATABASE_URL=postgres://lldap:${config.sops.placeholder."compose-stacks/databases/postgres/passwords/lldap"}@postgres/lldap
    LDAP_BIND_PASSWORD_PATH=${config.sops.secrets."compose-stacks/auth/ldap_bind/password".path}
    AUTHELIA_CONFIG_PATH=${config.sops.templates."authelia-configuration.yml".path}
  '';

  # See authelia-configuration.nix for why this lives in its own file.
  sops.templates."authelia-configuration.yml".content = import ./authelia-configuration.nix {
    inherit config ldapBaseDn ldapBindUserDn;
  };

  reverseProxy.dynamicConfig.auth = ''
    http:
      routers:
        authelia:
          rule: "Host(`auth.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: authelia
          tls:
            certResolver: le_main
        lldap:
          rule: "Host(`ldap.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: lldap
          tls:
            certResolver: le_main
      services:
        authelia:
          loadBalancer:
            servers:
              - url: "http://authelia:9091"
        lldap:
          loadBalancer:
            servers:
              - url: "http://lldap:17170"
      # Shared by any other stack's dynamicConfig fragment that wants to gate a route
      # behind Authelia — referenced by plain name (`authelia`), since every fragment
      # is merged into one Traefik file-provider directory. Mirrors the middleware the
      # old container_backbone role defined once and every protected stack referenced
      # as `authelia@docker`; /api/authz/forward-auth is Authelia's current endpoint
      # for this (the old /api/verify is legacy).
      middlewares:
        authelia:
          forwardAuth:
            address: "http://authelia:9091/api/authz/forward-auth"
            trustForwardHeader: true
            authResponseHeaders:
              - Remote-User
              - Remote-Groups
              - Remote-Email
              - Remote-Name
  '';

  compose-stacks.stacks.auth = {
    inherit composeFile;
    environmentFile = config.sops.templates."compose-auth.env".path;
    dockerNetworks = [
      "web"
      "db"
      "ldap"
      "monitoring"
    ];
    extraAfter = [ "reverse-proxy-dynamic-config.service" ];
  };

  # lldap's own admin/group seeding was dead code in the original Ansible role — real
  # human users have always been created manually via lldap's web UI, and stay that
  # way. Groups, unlike users, are set-and-forget (matching the prod instance's
  # existing group list, carried over into lldap-bootstrap/group-configs/ — currently
  # unused by any access_control rule, since no stack besides `auth` itself exists
  # yet, but ready as more stacks are converted), so they're declared here alongside
  # the Authelia LDAP bind service account (which additionally gets
  # `lldap_password_manager`, letting users reset their password through Authelia
  # rather than needing a separate lldap login for that). Invoked via lldap's
  # bootstrap.sh (bundled in its image) separately from the main `up -d` so it
  # doesn't affect compose-auth's own restart lifecycle. bootstrap.sh's default
  # behavior only creates/updates what's declared in its JSON configs and never
  # deletes anything else, so this is safe to run alongside continued manual user
  # management.
  systemd.services.auth-lldap-bootstrap = {
    description = "Reconcile lldap's groups and Authelia service account via bootstrap.sh";
    after = [ "compose-auth.service" ];
    requires = [ "compose-auth.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "auth-lldap-bootstrap" ''
        set -euo pipefail
        for i in $(seq 1 30); do
          if ${pkgs.docker}/bin/docker compose --project-name auth -f ${composeFile} exec -T lldap /app/bootstrap.sh; then
            exit 0
          fi
          sleep 2
        done
        echo "lldap bootstrap failed after retries" >&2
        exit 1
      '';
    };
  };
}
