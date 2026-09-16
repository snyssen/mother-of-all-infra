{
  lib,
  config,
  pkgs,
  ...
}:
let
  # Central list of app databases (also used as the Postgres role name for each,
  # matching the Ansible convention). Adding an entry here plus a matching
  # `compose-stacks/databases/postgres/passwords/<name>` SOPS leaf and
  # `PG_PASSWORD_<NAME>` line in docker-compose.yaml's `provision` service is enough
  # to provision a new app database without touching the existing Postgres data volume.
  #
  # `attic` is intentionally excluded: it's moving to a dedicated VM, not `apps`.
  dbNames = [
    "lldap"
    "authelia"
    "nextcloud"
    "recipes"
    "paperless"
    "team_wiki"
    "rallly"
    "speedtest_tracker"
    "umami"
    "sharkey"
    "semaphore"
    "matrix"
    "matrix_mas"
    "matrix_discord"
    "matrix_signal"
    "matrix_whatsapp"
    "matrix_meta"
    "maubot"
    "peertube"
    "audiomuse"
  ];

  envVarName = name: "PG_PASSWORD_${lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] name)}";

  # Copy the whole directory (not just docker-compose.yaml) into the store so the
  # compose file's relative bind mounts (./provision.sh, ./hooks) resolve against its
  # sibling files instead of against /nix/store itself.
  composeFile = "${./.}/docker-compose.yaml";
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/app-data/databases/postgres/data 0700 999 999 -"
  ];

  sops.secrets =
    (lib.listToAttrs (
      map (name: {
        name = "compose-stacks/databases/postgres/passwords/${name}";
        value = {
          sopsFile = ../../data/secrets.yaml;
          restartUnits = [ "databases-provision.service" ];
        };
      }) (dbNames ++ [ "superuser" ])
    ))
    // {
      "compose-stacks/databases/pgadmin/email" = {
        sopsFile = ../../data/secrets.yaml;
      };
      "compose-stacks/databases/pgadmin/password" = {
        sopsFile = ../../data/secrets.yaml;
      };
      "compose-stacks/databases/pg_dump_healthcheck_id" = {
        sopsFile = ../../data/secrets.yaml;
      };
    };

  sops.templates."compose-databases.env".content =
    ''
      POSTGRES_PASSWORD=${config.sops.placeholder."compose-stacks/databases/postgres/passwords/superuser"}
      DB_NAMES=${lib.concatStringsSep "," dbNames}
      PGADMIN_DEFAULT_EMAIL=${config.sops.placeholder."compose-stacks/databases/pgadmin/email"}
      PGADMIN_DEFAULT_PASSWORD=${config.sops.placeholder."compose-stacks/databases/pgadmin/password"}
      HEALTHCHECK_ID=${config.sops.placeholder."compose-stacks/databases/pg_dump_healthcheck_id"}
    ''
    + lib.concatMapStringsSep "\n" (
      name: "${envVarName name}=${
        config.sops.placeholder."compose-stacks/databases/postgres/passwords/${name}"
      }"
    ) dbNames;

  compose-stacks.stacks.databases = {
    inherit composeFile;
    environmentFile = config.sops.templates."compose-databases.env".path;
    dockerNetworks = [ "db" ];
    # postgres_backups writes dumps under /mnt/bulk/backups/postgres.
    extraAfter = [ "mnt-bulk.mount" ];
  };

  # `compose-databases.service` only brings up the long-running containers
  # (`docker compose up -d`). Provisioning runs as its own `docker compose run --rm`
  # invocation in a separate unit so that adding a database or rotating a password
  # never stops/restarts the already-running Postgres/pgAdmin/backup containers.
  systemd.services.databases-provision = {
    description = "Run the databases stack's Postgres provisioning step";
    after = [ "compose-databases.service" ];
    requires = [ "compose-databases.service" ];
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [ config.sops.templates."compose-databases.env".content ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.docker}/bin/docker compose --project-name databases -f ${composeFile} run --rm provision";
      EnvironmentFile = config.sops.templates."compose-databases.env".path;
    };
  };
}
