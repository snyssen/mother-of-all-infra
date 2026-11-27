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
    "d /var/lib/app-data/crowdsec/hub 0755 root root -"
    # The web UI drops from root to uid 1000 (gosu node) before opening its SQLite
    # database, so it needs to own this directory and everything in it — Z also
    # re-owns any files already created or restored there as root.
    "d /var/lib/app-data/crowdsec-web-ui 0755 1000 1000 -"
    "Z /var/lib/app-data/crowdsec-web-ui - 1000 1000 -"
  ];

  sops.secrets = {
    # Shared between the LAPI's BOUNCER_KEY_firewall env (registers it as a valid
    # bouncer key) and apps's own crowdsec-firewall-bouncer.apiKeyPath in
    # configuration.nix — same key, two consumers, matching the legacy role's
    # "same key on both ends" pattern.
    "compose-stacks/crowdsec/firewall_bouncer/api_key" = {
      sopsFile = ../../data/crowdsec.yaml;
    };
    # The `ingress` host's firewall bouncer key: the same value as that host's own
    # `crowdsec-firewall-bouncer/api_key` (nix/hosts/ingress/data/secrets.yaml),
    # registered here so the LAPI accepts it. Legacy prod registered it outside the
    # repo, so it did not survive the move to this host: the bouncer got 403s from
    # then on.
    "compose-stacks/crowdsec/ingress_bouncer/api_key" = {
      sopsFile = ../../data/crowdsec.yaml;
    };
    # The `ingress` host's Traefik plugin, calling the AppSec listener on 7423 (see the
    # crowdsec-appsec-ingress route below). Same value as that host's
    # `crowdsec/appsec_key` (nix/hosts/ingress/data/secrets.yaml).
    "compose-stacks/crowdsec/ingress_waf_bouncer/api_key" = {
      sopsFile = ../../data/crowdsec.yaml;
    };
    "compose-stacks/crowdsec/webui/lapi_user" = {
      sopsFile = ../../data/crowdsec.yaml;
    };
    "compose-stacks/crowdsec/webui/lapi_password" = {
      sopsFile = ../../data/crowdsec.yaml;
    };
    "compose-stacks/crowdsec/oidc/client_id" = {
      sopsFile = ../../data/crowdsec.yaml;
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
      sopsFile = ../../data/crowdsec.yaml;
      owner = "snyssen";
      mode = "0400";
    };
    # Hashed, for Authelia's own client config — same plaintext/hash split already
    # used for Grafana's OIDC client.
    "compose-stacks/crowdsec/oidc/client_secret_hash" = {
      sopsFile = ../../data/crowdsec.yaml;
    };
  };

  sops.templates."compose-crowdsec.env".content = ''
    BOUNCER_KEY_firewall=${config.sops.placeholder."compose-stacks/crowdsec/firewall_bouncer/api_key"}
    BOUNCER_KEY_ingress=${config.sops.placeholder."compose-stacks/crowdsec/ingress_bouncer/api_key"}
    BOUNCER_KEY_ingress_waf=${
      config.sops.placeholder."compose-stacks/crowdsec/ingress_waf_bouncer/api_key"
    }
    CROWDSEC_LAPI_PASSWORD=${config.sops.placeholder."compose-stacks/crowdsec/webui/lapi_password"}
    CROWDSEC_WEBUI_CONFIG_PATH=${config.sops.templates."crowdsec-web-ui-configuration.yml".path}
    CROWDSEC_OIDC_CLIENT_SECRET_PATH=${
      config.sops.secrets."compose-stacks/crowdsec/oidc/client_secret".path
    }
  '';

  sops.templates."crowdsec-web-ui-configuration.yml" = {
    content = import ./crowdsec-web-ui-configuration.nix { inherit config; };
    # Same reasoning as the oidc/client_secret secret above: owned by snyssen (pinned
    # to uid 1000 to match) rather than a raw "1000" owner string or a new dedicated
    # system user.
    owner = "snyssen";
    mode = "0400";
  };

  # No AppSec on apps-01's own routes: the WAF sits on ingress, in front of the public
  # routes only (docs/plans/crowdsec-appsec.md), so LAN and tailnet access never
  # depends on it. apps-01 used to run it on these two routes as a test; removed
  # 2026-11-27, since neither is public and it put the remote firewall bouncers' LAPI
  # polling behind a fail-closed AppSec check.
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
            - tailnet-whitelist
          tls:
            certResolver: le_main
        crowdsec-ui:
          rule: "Host(`crowdsec-ui.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: crowdsec-ui
          middlewares:
            - authelia
          tls:
            certResolver: le_main
        # ingress's Traefik sends every public request here for an AppSec check
        # (crowdsec-waf in nix/hosts/ingress/traefik-configuration.nix).
        crowdsec-appsec-ingress:
          rule: "Host(`appsec.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: crowdsec-appsec-ingress
          middlewares:
            - ingress-only
          tls:
            certResolver: le_main
          # One line per public request otherwise: these calls are not traffic, and in
          # the access log they would also feed CrowdSec's own HTTP scenarios.
          observability:
            accessLogs: false
      services:
        crowdsec:
          loadBalancer:
            servers:
              - url: "http://crowdsec:8080"
        crowdsec-ui:
          loadBalancer:
            servers:
              - url: "http://crowdsec-web-ui:3000"
        crowdsec-appsec-ingress:
          loadBalancer:
            servers:
              - url: "http://crowdsec:7423"
      middlewares:
        # Only ingress calls the AppSec listener on 7423. The bouncer key is still
        # required on top; this keeps the endpoint closed to the rest of the tailnet.
        ingress-only:
          ipAllowList:
            sourceRange:
              - "100.120.249.84/32"
  '';

  compose-stacks.stacks.crowdsec = {
    restartTriggers = [
      ../../data/crowdsec.yaml
      config.sops.templates."compose-crowdsec.env".content
      config.sops.templates."crowdsec-web-ui-configuration.yml".content
    ];
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
    # Re-register if the LAPI credentials change.
    restartTriggers = [ ../../data/crowdsec.yaml ];
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

  # Keeps scenarios/parsers/AppSec rules current — that is how new CVE detections and
  # virtual patches reach this instance. The entrypoint already updates the hub on
  # every start (see the hub volume in docker-compose.yaml), but the container can run
  # for weeks between starts. SIGHUP reloads crowdsec in place (it is PID 1 via the
  # entrypoint's exec) rather than restarting it, which would briefly cut off the LAPI
  # and ingress's AppSec checks.
  systemd.services.crowdsec-hub-upgrade = {
    description = "Update and upgrade crowdsec hub content";
    after = [ "compose-crowdsec.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecCondition = pkgs.writeShellScript "crowdsec-hub-upgrade-condition" ''
        ${pkgs.docker}/bin/docker compose --project-name crowdsec -f ${composeFile} \
          ps --status running --services | ${pkgs.gnugrep}/bin/grep -qx crowdsec
      '';
      ExecStart = pkgs.writeShellScript "crowdsec-hub-upgrade" ''
        set -euo pipefail
        compose() {
          ${pkgs.docker}/bin/docker compose --project-name crowdsec -f ${composeFile} "$@"
        }
        compose exec -T crowdsec cscli hub update
        compose exec -T crowdsec cscli hub upgrade
        compose kill -s SIGHUP crowdsec
      '';
    };
  };

  systemd.timers.crowdsec-hub-upgrade = {
    description = "Daily crowdsec hub update";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "1h";
      Persistent = true;
    };
  };
}
