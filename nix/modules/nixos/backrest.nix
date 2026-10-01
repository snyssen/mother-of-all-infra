{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.backrest;

  mkEnvList =
    env: lib.mapAttrsToList (name: secretPath: "${name}=${config.sops.placeholder.${secretPath}}") env;

  repoSubmodule = lib.types.submodule (
    { name, ... }:
    {
      options = {
        id = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Repo id as it appears in Backrest's config/UI. Defaults to the attribute name.";
        };
        uri = lib.mkOption {
          type = lib.types.str;
          description = "Restic repository URI, e.g. \"rest:http://host:8000/\" or \"s3:https://...\".";
        };
        passwordSecret = lib.mkOption {
          type = lib.types.str;
          description = "sops secret path (as passed to config.sops.secrets.<name>) holding the restic repository password.";
        };
        guid = lib.mkOption {
          type = lib.types.str;
          description = ''
            Fixed, stable identifier for this repo. Not a secret — just needs to stay
            the same across redeploys so Backrest doesn't treat the repo as new each
            time (its own operation-log bookkeeping is keyed by this). Generate once
            with `openssl rand -hex 32` and hardcode it.
          '';
        };
        env = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = ''
            Extra environment variables the restic backend needs (e.g. S3 credentials),
            as {ENV_VAR_NAME = sops secret path}. Rendered as Backrest's env: ["KEY=value"] list.
          '';
        };
        prunePolicy = lib.mkOption {
          type = lib.types.nullOr (lib.types.attrsOf lib.types.anything);
          default = null;
          description = "Backrest prunePolicy object, passed through as-is (see Backrest's config schema).";
        };
        checkPolicy = lib.mkOption {
          type = lib.types.nullOr (lib.types.attrsOf lib.types.anything);
          default = null;
          description = "Backrest checkPolicy object, passed through as-is.";
        };
        forgetPolicy = lib.mkOption {
          type = lib.types.nullOr (lib.types.attrsOf lib.types.anything);
          default = null;
          description = "Backrest forgetPolicy object, passed through as-is.";
        };
      };
    }
  );

  userSubmodule = lib.types.submodule (
    { name, ... }:
    {
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Login username. Defaults to the attribute name.";
        };
        passwordHashSecret = lib.mkOption {
          type = lib.types.str;
          description = ''
            sops secret path holding this user's password, in the exact encoding
            Backrest's `passwordBcrypt` config field expects — which, despite the
            name, is NOT a raw bcrypt hash string. Confirmed from Backrest's own
            source (internal/auth/auth.go): it base64-decodes this field, then
            bcrypt-compares the *decoded bytes* against the submitted password. So
            the secret must be base64(bcrypt_hash_string), a double encoding, e.g.:

              mkpasswd --method=bcrypt --rounds=12 --stdin | base64 -w0

            A raw `$2b$12$...` hash alone fails with "decode password: illegal
            base64 data at input byte 0" (the leading `$` isn't valid base64) — the
            exact, non-obvious mistake made (and fixed) building this module.
          '';
        };
      };
    }
  );

  planSubmodule = lib.types.submodule (
    { name, ... }:
    {
      options = {
        id = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Plan id as it appears in Backrest's config/UI. Defaults to the attribute name.";
        };
        repo = lib.mkOption {
          type = lib.types.str;
          description = "Name of the backrest.repos.<name> this plan backs up into.";
        };
        paths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = "Host paths to back up.";
        };
        excludes = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
        retention = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          description = "Backrest retention policy object, passed through as-is.";
        };
        schedule = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          description = "Backrest schedule object, passed through as-is.";
        };
      };
    }
  );

  renderRepo = repo: {
    inherit (repo) id uri guid;
    password = config.sops.placeholder.${repo.passwordSecret};
  }
  // lib.optionalAttrs (repo.env != { }) { env = mkEnvList repo.env; }
  // lib.optionalAttrs (repo.prunePolicy != null) { prunePolicy = repo.prunePolicy; }
  // lib.optionalAttrs (repo.checkPolicy != null) { checkPolicy = repo.checkPolicy; }
  // lib.optionalAttrs (repo.forgetPolicy != null) { forgetPolicy = repo.forgetPolicy; };

  renderPlan = plan: {
    inherit (plan) id repo paths retention schedule;
  }
  // lib.optionalAttrs (plan.excludes != [ ]) { excludes = plan.excludes; };

  renderUser = user: {
    inherit (user) name;
    passwordBcrypt = config.sops.placeholder.${user.passwordHashSecret};
  };

  dataDir = "/var/lib/backrest/data";
  configPath = "/var/lib/backrest/config/config.json";
  bindPort = lib.toInt (lib.last (lib.splitString ":" cfg.bindAddress));
in
{
  options.backrest = {
    enable = lib.mkEnableOption "Backrest (web UI and orchestrator for restic)";

    instance = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "Backrest's own \"instance\" label (used for its multihost sync feature, unused here).";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      # Not loopback-only: Traefik reaches host-native services via the docker
      # bridge gateway (host.docker.internal), not 127.0.0.1 — same reasoning as
      # cadvisor's listenAddress default in docker.nix. The NixOS firewall (left
      # closed here — no networking.firewall.allowedTCPPorts for this port) plus the
      # existing docker-bridge trust rule in docker.nix (also from cadvisor's
      # precedent) is what actually restricts reachability to this host's own docker
      # networks, not the bind address.
      default = "0.0.0.0:9898";
      description = "Address Backrest's web server binds to. Reach it through a reverse proxy; left closed on the NixOS firewall.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to open Backrest's port to the WAN/tailnet directly. Not needed to reach it through the reverse proxy — only for bypassing it.";
    };

    repos = lib.mkOption {
      type = lib.types.attrsOf repoSubmodule;
      default = { };
      description = "Restic repositories Backrest should know about.";
    };

    plans = lib.mkOption {
      type = lib.types.attrsOf planSubmodule;
      default = { };
      description = "Backup plans (what to back up, on what schedule, into which repo).";
    };

    users = lib.mkOption {
      type = lib.types.attrsOf userSubmodule;
      default = { };
      description = ''
        Login accounts for Backrest's own web UI. Backrest refuses to drop this to an
        open/unauthenticated UI on its own (it nags with an "Initial setup" banner
        until at least one user exists) — declare one here rather than through the UI.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      # Backrest's own state (oplog db, restic binary cache) — created once, never
      # Nix-managed content. Confirmed disposable (Backrest re-indexes snapshot
      # history straight from the repo on loss), but no reason to churn it.
      "d ${dataDir} 0700 root root -"
    ];

    # Backrest treats this file as read-write state, not read-only input: it
    # rewrites/reformats it on every start (confirmed empirically — e.g. it injects
    # its own auto-generated multihost "sync" identity block). That's fine: a Nix
    # redeploy always restarts the service, which re-reads this freshly-rendered file
    # before Backrest gets another chance to touch it, so Nix stays the actual source
    # of truth for repos/plans — any bookkeeping Backrest adds between deploys is
    # harmless churn, not data loss (real backup data lives in the restic repos
    # themselves, never in this file).
    sops.templates."backrest-config.json" = {
      content = builtins.toJSON (
        {
          version = 6;
          instance = cfg.instance;
          repos = lib.mapAttrsToList (_: renderRepo) cfg.repos;
        }
        // lib.optionalAttrs (cfg.plans != { }) {
          plans = lib.mapAttrsToList (_: renderPlan) cfg.plans;
        }
        // lib.optionalAttrs (cfg.users != { }) {
          auth.users = lib.mapAttrsToList (_: renderUser) cfg.users;
        }
      );
      path = configPath;
      restartUnits = [ "backrest.service" ];
    };

    networking.firewall.allowedTCPPorts = lib.optionals cfg.openFirewall [ bindPort ];

    # Native systemd service, not a compose-stacks container: Backrest needs broad
    # read access across every stack's data directories, each owned by a different
    # container's own uid (postgres 999, jellyfin 33, peertube 999, ...) — running it
    # as root sidesteps bind-mounting every single directory with matching ownership
    # into a container for zero real isolation benefit. Matches this repo's existing
    # pragmatic-root precedent (virtualisation.libvirtd.qemu.runAsRoot in libvirtd.nix).
    systemd.services.backrest = {
      description = "Backrest (restic backup web UI and orchestrator)";
      after = [ "network-online.target" ];
      requires = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        BACKREST_CONFIG = configPath;
        BACKREST_DATA = dataDir;
        BACKREST_PORT = cfg.bindAddress;
      };
      serviceConfig = {
        ExecStart = "${pkgs.backrest}/bin/backrest";
        Restart = "on-failure";
      };
    };
  };
}
