{
  lib,
  config,
  pkgs,
  ...
}:
# Restore commands generated from the same options that describe the backups.
#
# Disaster recovery and "import another host's snapshots with translated paths" look
# like different tools, but strip away what differs (where the group list comes from,
# whether `to` equals `from`) and what remains is identical: resolve one snapshot per
# group, restore subpaths to targets as root, preflight, confirm, report. So: one
# script, instantiated once per command — separate binaries rather than one binary with
# a mode flag, so disaster recovery can never be driven with import semantics by accident.
#
# This lives in the backrest module rather than next to its data because the module is
# the only place that knows the repo-id -> password-secret -> env-vars mapping. Deriving
# it anywhere else would mean declaring that mapping a second time, and a stale copy
# fails in the worst possible way: at restore time.
#
# The script itself is a plain file (scripts/restore.sh) with no Nix interpolation in
# it. Everything Nix knows is handed over as a JSON manifest instead, which keeps the
# shell readable and lintable on its own terms rather than as an escaped Nix string.
let
  cfg = config.backrest;
  inherit (import ./paths.nix) dataDir;

  restorePathType = lib.types.submodule {
    options = {
      from = lib.mkOption {
        type = lib.types.str;
        description = ''
          Absolute path inside the snapshot. May be *deeper* than the snapshot's own
          declared root path (e.g. restoring .../grafana/data out of a snapshot rooted
          at .../grafana) — restic's snapshotID:subfolder syntax handles that, and it
          is verified working against the real repository.
        '';
      };
      to = lib.mkOption {
        type = lib.types.str;
        description = "Absolute target path on this host. restic creates it and any missing parents.";
      };
      owner = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "33:100";
        description = ''
          If set, `chown -R` the target after restoring. Needed only when the source
          host's numeric uid/gid differ from this host's, since restic restores numeric
          owners verbatim when running as root.

          Recursive is not optional: systemd-tmpfiles `d` rules re-assert ownership of
          the *top-level* directory on every activation but never touch its children, so
          a shallow chown leaves a correct-looking directory full of wrongly-owned files.
        '';
      };
    };
  };

  # A restore group is exactly one backup plan (ours) or one autorestic location
  # (legacy prod's) — which is also the unit restic can resolve to a single snapshot.
  # Grouping this way is what lets a multi-path plan resolve its snapshot *once*:
  # issuing an independent `latest:` restore per path would let the paths of one plan
  # come from two different snapshots.
  restoreGroupType = lib.types.submodule {
    options = {
      repo = lib.mkOption {
        type = lib.types.str;
        description = "Name of the backrest.repos.<name> to restore from.";
      };
      snapshotFilter = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        example = [
          "--tag"
          "ar:location:monitoring"
          "--host"
          "snyssen.be"
        ];
        description = ''
          restic snapshot-selection flags identifying this group's snapshot series,
          passed verbatim to `restic snapshots`. The one snapshot chosen out of those
          (the newest, or the newest at or before --at) is then reused for every path
          in the group.
        '';
      };
      stopUnits = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Units stopped before the restore and restarted after — only those that were actually running.";
      };
      paths = lib.mkOption {
        type = lib.types.listOf restorePathType;
        description = "The (from -> to) pairs this group restores.";
      };
    };
  };

  mkManifest =
    commandName: groups:
    pkgs.writeText "${commandName}-manifest.json" (
      builtins.toJSON {
        command = commandName;
        groups = lib.mapAttrs (_: group: {
          repo =
            let
              repo = cfg.repos.${group.repo};
            in
            {
              inherit (repo) uri;
              passwordFile = config.sops.secrets.${repo.passwordSecret}.path;
              env = lib.mapAttrs (_: secretPath: config.sops.secrets.${secretPath}.path) repo.env;
            };
          inherit (group) snapshotFilter stopUnits paths;
        }) groups;
      }
    );

  mkRestoreCommand =
    commandName: groups:
    pkgs.writeShellApplication {
      name = commandName;
      runtimeInputs = with pkgs; [
        restic
        jq
        coreutils
        gnugrep
        systemd
      ];
      text = ''
        MANIFEST=${mkManifest commandName groups}
        export MANIFEST
        export HOME=${lib.escapeShellArg dataDir}

      ''
      + builtins.readFile ./scripts/restore.sh;
    };

  # Disaster recovery, derived from the backup plans themselves rather than restated:
  # one group per plan, targets identical to sources. A plan added later is covered
  # automatically, which is the whole point — a hand-maintained second copy of the path
  # list would drift, and would only reveal that it had drifted during an actual
  # recovery.
  drGroups = lib.mapAttrs (_: plan: {
    inherit (plan) repo stopUnits;
    # Both tags rather than --tag + --host: these are the two things Backrest provably
    # stamps on every snapshot it creates. Whether it also passes --host to restic, and
    # with what value, is unverified — and `instance` is evaluated at build time, so a
    # VM rebuilt from this configuration matches regardless of its runtime hostname.
    snapshotFilter = [
      "--tag"
      "plan:${plan.id}"
      "--tag"
      "created-by:${cfg.instance}"
    ];
    # plan.excludes is deliberately NOT forwarded: excludes are applied at *backup*
    # time, so the snapshot simply does not contain them. Passing them to restore would
    # be a second, differently-interpreted filter for no gain.
    paths = map (p: {
      from = p;
      to = p;
      owner = null;
    }) plan.paths;
  }) cfg.plans;
in
{
  options.backrest.restore = {
    commandName = lib.mkOption {
      type = lib.types.str;
      default = "backrest-restore";
      description = ''
        Name of the disaster-recovery command generated from `backrest.plans` (one
        group per plan, restoring every path back to where it came from). Not
        generated at all when no plans are declared.
      '';
    };

    extra = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf restoreGroupType);
      default = { };
      example = lib.literalExpression ''
        {
          prod-import.monitoring = {
            repo = "backup_snyssen_be";
            snapshotFilter = [ "--tag" "ar:location:monitoring" "--host" "snyssen.be" ];
            stopUnits = [ "compose-monitoring.service" ];
            paths = [
              { from = "/home/snyssen/data/grafana/data"; to = "/var/lib/app-data/monitoring/grafana"; owner = "472:472"; }
            ];
          };
        }
      '';
      description = ''
        Additional restore commands, keyed by command name, each holding its own
        groups. Unlike the auto-derived disaster-recovery command these are written by
        hand — they exist for restoring *another* host's snapshots, where paths and
        numeric ownership have to be translated on the way in.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.flatten (
      lib.mapAttrsToList (
        cmd: groups:
        lib.mapAttrsToList (name: group: {
          assertion = cfg.repos ? ${group.repo};
          message = "backrest.restore.extra.${cmd}.${name}.repo refers to \"${group.repo}\", which is not declared in backrest.repos.";
        }) groups
      ) cfg.restore.extra
    );

    environment.systemPackages = lib.mapAttrsToList mkRestoreCommand (
      lib.optionalAttrs (cfg.plans != { }) { ${cfg.restore.commandName} = drGroups; } // cfg.restore.extra
    );
  };
}
