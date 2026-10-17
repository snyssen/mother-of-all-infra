{
  lib,
  config,
  ...
}:
# Backrest (https://github.com/garethgeorge/backrest): a web UI and scheduler wrapped
# around restic. Split across:
#
#   default.nix  — the options describing repos, plans and users (this file)
#   service.nix  — the systemd service and the config.json rendered from those options
#   restore.nix  — the restore commands generated from those same options
#   paths.nix    — the couple of on-disk paths service.nix and restore.nix must agree on
#
# Everything is declared here rather than through Backrest's own UI, so the repos and
# plans in git are the source of truth. Backrest does rewrite config.json at runtime
# (it injects its own multihost "sync" identity, for instance) — harmless, because a
# redeploy restarts the service against a freshly rendered file, and the real data
# lives in the restic repositories, never in this config.
let
  cfg = config.backrest;

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
        stopUnits = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Units the *restore* command stops before rewriting this plan's paths and
            restarts afterwards. Not used at backup time — Backrest has its own hooks
            for that. Usually empty: a real disaster recovery runs with everything
            masked (see the runbook in docs/backups.md), so there is nothing to stop.
            Set it when restoring onto a live host is a realistic thing to do.
          '';
        };
      };
    }
  );
in
{
  imports = [
    ./service.nix
    ./restore.nix
  ];

  options.backrest = {
    enable = lib.mkEnableOption "Backrest (web UI and orchestrator for restic)";

    instance = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = ''
        Backrest's own "instance" label. It stamps every snapshot it creates with
        `created-by:<instance>`, which is how the generated restore commands find them,
        so changing it orphans existing snapshots from this host's point of view.
      '';
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      # Not loopback-only: Traefik reaches host-native services via the docker
      # bridge gateway (host.docker.internal), not 127.0.0.1 — same reasoning as
      # cadvisor's listenAddress default in docker.nix. The NixOS firewall (left
      # closed unless openFirewall) plus the existing docker-bridge trust rule in
      # docker.nix is what actually restricts reachability, not the bind address.
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
      description = ''
        Backup plans (what to back up, on what schedule, into which repo). These are
        also what the generated disaster-recovery command restores — see restore.nix —
        so a stack with state but no plan is a silent gap in recovery, not just a
        missing backup.
      '';
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
    assertions =
      lib.mapAttrsToList (name: plan: {
        assertion = cfg.repos ? ${plan.repo};
        message = "backrest.plans.${name}.repo refers to \"${plan.repo}\", which is not declared in backrest.repos.";
      }) cfg.plans
      ++ lib.mapAttrsToList (name: repo: {
        assertion = config.sops.secrets ? ${repo.passwordSecret};
        message = "backrest.repos.${name}.passwordSecret refers to the sops secret \"${repo.passwordSecret}\", which is not declared in sops.secrets.";
      }) cfg.repos;
  };
}
