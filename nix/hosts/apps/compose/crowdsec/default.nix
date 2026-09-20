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
    "d /var/lib/app-data/crowdsec/data 0755 root root -"
    "d /var/lib/app-data/crowdsec-web-ui 0755 root root -"
  ];

  sops.secrets = {
    # Shared between the LAPI's BOUNCER_KEY_firewall env (registers it as a valid
    # bouncer key) and apps's own crowdsec-firewall-bouncer.apiKeyPath in
    # configuration.nix — same key, two consumers, matching the legacy role's
    # "same key on both ends" pattern.
    "compose-stacks/crowdsec/firewall_bouncer/api_key" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-crowdsec.service" ];
    };
    # A separate bouncer identity for the Traefik plugin (see the WAF scope note
    # below) — each bouncer gets its own key, matching the legacy setup's approach.
    # Also consumed directly (as a raw file, not a placeholder) by reverse-proxy's
    # Traefik container — see crowdsecLapiKeyFile in the dynamicConfig fragment below
    # for why: a dynamicConfig fragment's string content is written via
    # pkgs.writeText, not rendered through sops.templates, so a placeholder embedded
    # in it would never actually get substituted (the same class of bug already
    # caught once this session for authelia-configuration.yml).
    "compose-stacks/crowdsec/waf_bouncer/api_key" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [
        "compose-crowdsec.service"
        "compose-reverse-proxy.service"
      ];
    };
    "compose-stacks/crowdsec/webui/lapi_user" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [
        "compose-crowdsec.service"
        "crowdsec-machine-bootstrap.service"
      ];
    };
    "compose-stacks/crowdsec/webui/lapi_password" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [
        "compose-crowdsec.service"
        "crowdsec-machine-bootstrap.service"
      ];
    };
    "compose-stacks/crowdsec/oidc/client_id" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-crowdsec.service" ];
    };
    # Plaintext, referenced directly via a `file:` path by the web UI's own config —
    # see crowdsec-web-ui-configuration.nix. Bind-mounted straight into
    # crowdsec-web-ui, which drops from root to uid 1000 (gosu node, confirmed in its
    # entrypoint) before starting. Owned by snyssen (pinned to uid 1000 in this host's
    # own user config) rather than a raw "1000" string — sops-install-secrets does a
    # real name lookup, not a chown-style numeric ID (confirmed the hard way:
    # activation failed with "unknown user 1000") — and rather than a new dedicated
    # system user, since snyssen already *is* uid 1000 and Linux's permission check
    # only cares about the raw uid matching, not which name owns it on which side of
    # the bind mount. No group needed: mode 0400 doesn't grant group access anyway.
    "compose-stacks/crowdsec/oidc/client_secret" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-crowdsec.service" ];
      owner = "snyssen";
      mode = "0400";
    };
    # Hashed, for Authelia's own client config — same plaintext/hash split already
    # used for Grafana's OIDC client.
    "compose-stacks/crowdsec/oidc/client_secret_hash" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-auth.service" ];
    };
  };

  sops.templates."compose-crowdsec.env".content = ''
    BOUNCER_KEY_firewall=${config.sops.placeholder."compose-stacks/crowdsec/firewall_bouncer/api_key"}
    BOUNCER_KEY_traefik=${config.sops.placeholder."compose-stacks/crowdsec/waf_bouncer/api_key"}
    CROWDSEC_LAPI_PASSWORD=${config.sops.placeholder."compose-stacks/crowdsec/webui/lapi_password"}
    CROWDSEC_WEBUI_CONFIG_PATH=${config.sops.templates."crowdsec-web-ui-configuration.yml".path}
    CROWDSEC_OIDC_CLIENT_SECRET_PATH=${config.sops.secrets."compose-stacks/crowdsec/oidc/client_secret".path}
  '';

  sops.templates."crowdsec-web-ui-configuration.yml" = {
    content = import ./crowdsec-web-ui-configuration.nix { inherit config; };
    # Same reasoning as the oidc/client_secret secret above: owned by snyssen (pinned
    # to uid 1000 to match) rather than a raw "1000" owner string or a new dedicated
    # system user.
    owner = "snyssen";
    mode = "0400";
  };

  # crowdsec-waf is scoped to this stack's own two routes only — see the WAF scope
  # decision in the plan this was built from. Extending it to other stacks' routers
  # (reverse-proxy/auth/monitoring) is a deliberate, separate follow-up: Traefik has
  # no way to apply a middleware to every router on an entrypoint declaratively, so
  # doing that here would mean editing every other stack's fragment too.
  #
  # crowdsec (LAPI) is reachable by any tailnet host's firewall bouncer, gated by the
  # tailnet-whitelist middleware already defined in monitoring's own fragment — same
  # cross-fragment reference pattern already used for `authelia`. crowdsec-ui is
  # human-facing, gated by Authelia instead.
  reverseProxy.dynamicConfig.crowdsec = ''
    http:
      routers:
        crowdsec:
          rule: "Host(`crowdsec.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: crowdsec
          middlewares:
            - crowdsec-waf
            - tailnet-whitelist
          tls:
            certResolver: le_main
        crowdsec-ui:
          rule: "Host(`crowdsec-ui.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: crowdsec-ui
          middlewares:
            - crowdsec-waf
            - authelia
          tls:
            certResolver: le_main
      services:
        crowdsec:
          loadBalancer:
            servers:
              - url: "http://crowdsec:8080"
        crowdsec-ui:
          loadBalancer:
            servers:
              - url: "http://crowdsec-web-ui:3000"
      middlewares:
        crowdsec-waf:
          plugin:
            crowdsec-bouncer:
              enabled: true
              crowdsecMode: live
              crowdsecLapiHost: "crowdsec:8080"
              # File, not crowdsecLapiKey inline — see the comment on this secret
              # above for why. Bind-mounted directly into the Traefik container by
              # reverse-proxy/docker-compose.yaml at this fixed path.
              crowdsecLapiKeyFile: "/run/secrets/crowdsec_waf_bouncer_key"
  '';

  compose-stacks.stacks.crowdsec = {
    inherit composeFile;
    environmentFile = config.sops.templates."compose-crowdsec.env".path;
    dockerNetworks = [
      "web"
      "monitoring"
    ];
    extraAfter = [ "reverse-proxy-dynamic-config.service" ];
  };

  # crowdsec-web-ui authenticates to the LAPI as a password-based "machine" — unlike
  # bouncer API keys (auto-registered via the BOUNCER_KEY_* env vars above), the
  # crowdsec image has no env-var mechanism to pre-seed this at startup (confirmed
  # against its own docs); `cscli machines add` run against a running container is
  # the actual supported way. Mirrors auth-lldap-bootstrap's shape exactly: retries
  # until the container answers, and --force makes re-running safe (updates this one
  # named machine's password instead of erroring if it already exists) so this can
  # re-run on every activation/secret rotation without manual intervention.
  systemd.services.crowdsec-machine-bootstrap = {
    description = "Register crowdsec-web-ui's LAPI machine credential";
    after = [ "compose-crowdsec.service" ];
    requires = [ "compose-crowdsec.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "crowdsec-machine-bootstrap" ''
        set -euo pipefail
        lapi_user="$(cat ${config.sops.secrets."compose-stacks/crowdsec/webui/lapi_user".path})"
        lapi_password="$(cat ${config.sops.secrets."compose-stacks/crowdsec/webui/lapi_password".path})"
        for i in $(seq 1 30); do
          if ${pkgs.docker}/bin/docker compose --project-name crowdsec -f ${composeFile} exec -T crowdsec \
            cscli machines add "$lapi_user" --password "$lapi_password" --force; then
            exit 0
          fi
          sleep 2
        done
        echo "crowdsec machine bootstrap failed after retries" >&2
        exit 1
      '';
    };
  };
}
