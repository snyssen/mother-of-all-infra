{
  lib,
  config,
  pkgs,
  ...
}:
# The Backrest service itself, and the config.json rendered from backrest.{repos,plans,users}.
let
  cfg = config.backrest;
  inherit (import ./paths.nix) dataDir configPath;

  bindPort = lib.toInt (lib.last (lib.splitString ":" cfg.bindAddress));

  mkEnvList =
    env: lib.mapAttrsToList (name: secretPath: "${name}=${config.sops.placeholder.${secretPath}}") env;

  renderRepo =
    repo:
    {
      inherit (repo) id uri guid;
      password = config.sops.placeholder.${repo.passwordSecret};
    }
    // lib.optionalAttrs (repo.env != { }) { env = mkEnvList repo.env; }
    // lib.optionalAttrs (repo.prunePolicy != null) { prunePolicy = repo.prunePolicy; }
    // lib.optionalAttrs (repo.checkPolicy != null) { checkPolicy = repo.checkPolicy; }
    // lib.optionalAttrs (repo.forgetPolicy != null) { forgetPolicy = repo.forgetPolicy; };

  # Note what is *not* forwarded: stopUnits. It is this repo's own addition for the
  # restore commands, and Backrest's config schema would reject the unknown field.
  renderPlan =
    plan:
    {
      inherit (plan)
        id
        repo
        paths
        retention
        schedule
        ;
    }
    // lib.optionalAttrs (plan.excludes != [ ]) { excludes = plan.excludes; };

  renderUser = user: {
    inherit (user) name;
    passwordBcrypt = config.sops.placeholder.${user.passwordHashSecret};
  };
in
{
  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      # Backrest's own state (oplog db, restic cache) — created once, never
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
        # See the comment in paths.nix for why this matters beyond performance.
        HOME = dataDir;
      };
      serviceConfig = {
        ExecStart = "${pkgs.backrest}/bin/backrest";
        Restart = "on-failure";
      };
    };
  };
}
