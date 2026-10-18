{
  lib,
  config,
  pkgs,
  ...
}:
# One `postgres-restore` command covering every PostgreSQL instance on this host.
#
# Most stacks share the central cluster, but some must bring their own: Immich needs the
# vectorchord/pgvecto.rs extensions, and Dawarich and Mobilizon will want their own too.
# Rather than growing a separate restore command per instance — which would make the
# obvious command silently wrong for some databases — a stack registers its instance
# here and the single command resolves database -> instance on its own.
#
# What that buys, beyond ergonomics: `postgres-restore --all` really does mean all, so
# the disaster-recovery path (`apps-restore`) cannot quietly skip a database just because
# it happens to live in its own container.
#
# As with the backrest module, the shell lives in its own file and everything Nix knows
# is handed over as a JSON manifest, so the script stays readable on its own terms.
let
  cfg = config.postgresRestore;

  instanceType = lib.types.submodule (
    { name, ... }:
    {
      options = {
        project = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Compose project name this instance's containers belong to.";
        };
        composeFile = lib.mkOption {
          type = lib.types.either lib.types.path lib.types.str;
          description = "Compose file defining the instance.";
        };
        envFile = lib.mkOption {
          type = lib.types.either lib.types.path lib.types.str;
          description = ''
            Runtime environment file for that compose project — the same one systemd
            hands the stack. It supplies both the variables compose needs for its own
            interpolation and the per-database passwords named in `databases`.
          '';
        };
        service = lib.mkOption {
          type = lib.types.str;
          description = ''
            Compose service to run pg_restore in. Any service with the postgres client
            tools and network access to the server will do; in practice this is the
            dump sidecar, which already has both.
          '';
        };
        dbHost = lib.mkOption {
          type = lib.types.str;
          description = "Hostname the PostgreSQL server answers on inside that project's network.";
        };
        dumpDir = lib.mkOption {
          type = lib.types.str;
          description = "Host directory holding this instance's dumps, with the usual last/daily/weekly/monthly tiers.";
        };
        databases = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          description = ''
            The databases this instance serves, as {name = password env var}. The env
            var is looked up in `envFile` at restore time, so the password never reaches
            the command line or the manifest.
          '';
        };
      };
    }
  );

  manifest = pkgs.writeText "postgres-restore-manifest.json" (
    builtins.toJSON {
      command = "postgres-restore";
      instances = lib.mapAttrs (_: inst: {
        inherit (inst)
          project
          service
          dbHost
          dumpDir
          databases
          ;
        composeFile = toString inst.composeFile;
        envFile = toString inst.envFile;
      }) cfg.instances;
    }
  );

  # Every (database, instance) pair, used only to catch a name claimed twice.
  dbOwners = lib.foldlAttrs (
    acc: instName: inst:
    acc ++ map (db: { inherit db instName; }) (lib.attrNames inst.databases)
  ) [ ] cfg.instances;

  duplicatedDbs = lib.filter (db: lib.length (lib.filter (o: o.db == db) dbOwners) > 1) (
    lib.unique (map (o: o.db) dbOwners)
  );
in
{
  options.postgresRestore.instances = lib.mkOption {
    type = lib.types.attrsOf instanceType;
    default = { };
    description = ''
      PostgreSQL instances on this host, each contributing its databases to the single
      generated `postgres-restore` command. Declared by whichever stack owns the
      instance, so a stack and its restore path are added and removed together.
    '';
  };

  config = lib.mkIf (cfg.instances != { }) {
    # A database name is how the command picks an instance, so the same name in two
    # instances would make the choice arbitrary. Caught at build time rather than
    # discovered mid-restore.
    assertions = [
      {
        assertion = duplicatedDbs == [ ];
        message = "postgresRestore: database name(s) ${lib.concatStringsSep ", " duplicatedDbs} are declared in more than one instance; names must be unique across instances since they select the instance.";
      }
    ];

    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "postgres-restore";
        runtimeInputs = with pkgs; [
          docker
          jq
          coreutils
          findutils
          # Used only on the --at path; see the matching note in the backrest module.
          gawk
        ];
        text = ''
          MANIFEST=${manifest}
          export MANIFEST

        ''
        + builtins.readFile ./scripts/postgres-restore.sh;
      })
    ];
  };
}
