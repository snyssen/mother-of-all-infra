{
  config,
  pkgs,
  ...
}:
# Convenience backups of the work in progress on this workstation: what git doesn't
# protect in ~/source/repos (uncommitted and unpushed work, stashes, gitignored files such
# as .envrc), plus a short allowlist of home folders. Meant to get back up to speed after
# a hardware failure, not to archive anything, hence the short retention below.
#
# Plain `services.restic.backups` rather than the backrest module: no daemon or web UI
# to keep running on a workstation, and its systemd timer catches up on runs missed while
# the machine was off, which fixed cron schedules don't. Disaster recovery without this
# config at hand is restic-browser (home module restic-dr) plus the repo password, kept
# in the password manager as well as in sops.
#
# See docs/operations/backups.md, "Workstation backups (blackfog)".
let
  user = "snyssen";
  home = config.users.users.${user}.home;
  host = config.networking.hostName;
  tag = "workstation";

  # Its own repo with its own password on the on-site REST server, so nothing on this
  # machine can decrypt apps-01's backups. Reached over the tailnet (MagicDNS), so it
  # works off the LAN too.
  repository = "rest:http://backup.snyssen.be:8000/${host}/";
  passwordFile = config.sops.secrets."restic/${host}/password".path;

  # Report a job's outcome to its Gatus external endpoint (`workstations_<name>`), as
  # apps-01 does for its own jobs (nix/hosts/apps-01/compose/monitoring/gatus-push.nix,
  # which is bound to that host's domain and secrets, hence the copy). The token is this
  # host's own rather than apps-01's shared one, so a compromised workstation cannot fake
  # apps-01's backup results; it is sent from stdin so it never shows in a process list.
  gatusPush = pkgs.writeShellScript "gatus-push" ''
    set -euo pipefail
    printf 'Authorization: Bearer %s\n' "$(cat ${config.sops.secrets."gatus/push_token".path})" \
      | ${pkgs.curl}/bin/curl -fsS -m 10 --retry 5 -o /dev/null -H @- -X POST \
        "https://uptime.snyssen.be/api/v1/endpoints/$1/external?success=$2"
  '';
  # Runs as the unit's ExecStopPost (the module's backupCleanupCommand), where systemd
  # sets $SERVICE_RESULT to its verdict on the whole run: anything but `success` is
  # pushed as a failure, including restic's exit 3 (some files could not be read), as
  # apps-01 counts warnings as failures too. A failed push must not fail the job itself.
  heartbeat = endpoint: ''
    #!${pkgs.runtimeShell}
    if [ "$SERVICE_RESULT" = success ]; then result=true; else result=false; fi
    ${gatusPush} workstations_${endpoint} "$result" || echo "gatus push to ${endpoint} failed" >&2
  '';

  # Both jobs share the repo, so each waits for the other's lock instead of failing on
  # it. --retry-lock is a global restic flag, accepted after the subcommand; the module's
  # own `extraOptions` would render it as a `-o` backend option instead.
  retryLock = "--retry-lock 30m";
in
{
  sops.secrets = {
    "restic/${host}/password" = {
      sopsFile = ./data/secrets.yaml;
      owner = user;
      mode = "0400";
    };
    # Same value as apps-01's compose-stacks/monitoring/gatus/push_token_blackfog.
    "gatus/push_token" = {
      sopsFile = ./data/secrets.yaml;
      owner = user;
      mode = "0400";
    };
  };

  services.restic.backups = {
    # Hourly while the machine is on. Runs as the user who owns every one of these files:
    # no root needed, and the generated `restic-blackfog` wrapper works from their shell.
    ${host} = {
      inherit repository passwordFile user;
      initialize = true;
      paths = map (p: "${home}/${p}") [
        "source/repos"
        "Documents"
        "Pictures"
        "Music"
        "Videos"
        # For config and known_hosts. The private keys are excluded below: they never
        # leave this machine, and recovering them goes through the breakglass key.
        ".ssh"
      ];
      exclude = [
        "${home}/.ssh/id_*"
        # Syncthing's state, which the syncthing module keeps inside ~/Documents by default.
        # Nothing in it is worth restoring: the device identity comes from sops, the config
        # from Nix, and the index is rebuilt by rescanning. Worse, restoring its live SQLite
        # index (and WAL) over a running Syncthing would corrupt it, and since the index
        # changes constantly, it would also defeat --skip-if-unchanged.
        config.syncthing.configDir
        # Build output and tool state, all regenerable. Excluding `bin` also skips
        # uncommitted edits inside a tracked bin/ directory; accepted, git has the rest.
        "bin"
        "obj"
        "node_modules"
        "target"
        ".direnv"
        "result"
        ".terraform"
        ".venv"
        "__pycache__"
      ];
      extraBackupArgs = [
        "--tag ${tag}"
        "--exclude-caches"
        # No new snapshot when nothing changed, rather than one every hour.
        "--skip-if-unchanged"
        # Database dumps and other bulk files lying around in repos: not what this
        # backup is for, and one of them alone would outweigh everything else.
        "--exclude-larger-than 1G"
        retryLock
      ];
      timerConfig = {
        OnCalendar = "hourly";
        # Runs at boot when the machine was off at the scheduled time, which is also
        # what clears the heartbeat after nights and weekends.
        Persistent = true;
        RandomizedDelaySec = "5m";
      };
      # No `inhibitsSleep`: its systemd-inhibit, run as this user from a system service
      # (outside any login session), falls under polkit's `allow_any`, which for blocking
      # sleep is auth_admin_keep, so it would be refused and fail every backup. A backup
      # cut short by suspend is just picked up by the next run.
      backupCleanupCommand = heartbeat host;
    };

    # Retention and integrity, daily rather than after every hourly backup. No paths: the
    # module runs only `forget --prune` and `check` for such a job.
    "${host}-maintenance" = {
      inherit repository passwordFile user;
      paths = [ ];
      createWrapper = false;
      # About a month: enough to span a long holiday, nothing kept beyond it.
      pruneOpts = [
        "--tag ${tag}"
        "--group-by host,tags"
        "--keep-hourly 48"
        "--keep-daily 7"
        "--keep-weekly 4"
        retryLock
      ];
      # A different 5% of the data each day, so the whole repo is read about monthly.
      checkOpts = [
        "--read-data-subset=5%"
        retryLock
      ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "30m";
      };
      backupCleanupCommand = heartbeat "${host}-maintenance";
    };
  };

  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "${host}-restore";
      runtimeInputs = with pkgs; [
        jq
        coreutils
      ];
      # `restic-blackfog` itself is resolved from PATH: it is the wrapper the restic
      # module generates, carrying the repository and password settings.
      text = ''
        BACKUP_ROOT=${home}
        SNAPSHOT_HOST=${host}
        SNAPSHOT_TAG=${tag}
        RESTIC=restic-${host}

      ''
      + builtins.readFile ./scripts/blackfog-restore.sh;
    })
  ];
}
