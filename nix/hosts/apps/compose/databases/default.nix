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

  # Loading the dumps back into the cluster. This is the other half of a restore:
  # `backrest-restore` puts the dump *files* back, but a directory of dumps is not a
  # database. Lives here rather than in the backrest module because it's pg_restore,
  # not restic, and this file already owns dbNames and envVarName.
  #
  # Same shape as the backrest module's restore commands: the shell lives in its own
  # file and everything Nix knows is handed over as a JSON manifest, so the script
  # stays readable on its own terms instead of as an escaped Nix string.
  postgresRestoreManifest = pkgs.writeText "postgres-restore-manifest.json" (
    builtins.toJSON {
      command = "postgres-restore";
      composeFile = composeFile;
      envFile = config.sops.templates."compose-databases.env".path;
      defaultFrom = "/mnt/bulk/backups/postgres";
      databases = lib.listToAttrs (map (name: lib.nameValuePair name (envVarName name)) dbNames);
    }
  );

  postgresRestore = pkgs.writeShellApplication {
    name = "postgres-restore";
    runtimeInputs = with pkgs; [
      docker
      jq
      coreutils
      findutils
    ];
    text = ''
      MANIFEST=${postgresRestoreManifest}
      export MANIFEST

    ''
    + builtins.readFile ./scripts/postgres-restore.sh;
  };
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
          restartUnits = [ "compose-databases.service" ];
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
      "compose-stacks/databases/pgadmin/oidc/client_id" = {
        sopsFile = ../../data/secrets.yaml;
        restartUnits = [ "compose-databases.service" ];
      };
      "compose-stacks/databases/pgadmin/oidc/client_secret" = {
        sopsFile = ../../data/secrets.yaml;
        restartUnits = [ "compose-databases.service" ];
      };
      # Hashed, for Authelia's own client config — same plaintext/hash split already
      # used for Grafana/CrowdSec/PeerTube's OIDC clients.
      "compose-stacks/databases/pgadmin/oidc/client_secret_hash" = {
        sopsFile = ../../data/secrets.yaml;
        restartUnits = [ "compose-auth.service" ];
      };
    };

  # pgAdmin's container runs as uid 5050 internally; no NixOS user maps to that uid
  # (unlike the crowdsec-web-ui case elsewhere in this migration, where pinning
  # snyssen's own uid to match was worthwhile). World-readable is the pragmatic
  # tradeoff here instead, same as that case's own first fallback — acceptable for a
  # single-operator test VM.
  sops.templates."pgadmin-config_local.py" = {
    content = import ./pgadmin-config-local.nix { inherit config; };
    mode = "0444";
  };

  sops.templates."compose-databases.env".content = ''
    POSTGRES_PASSWORD=${config.sops.placeholder."compose-stacks/databases/postgres/passwords/superuser"}
    DB_NAMES=${lib.concatStringsSep "," dbNames}
    PGADMIN_DEFAULT_EMAIL=${config.sops.placeholder."compose-stacks/databases/pgadmin/email"}
    PGADMIN_DEFAULT_PASSWORD=${config.sops.placeholder."compose-stacks/databases/pgadmin/password"}
    HEALTHCHECK_ID=${config.sops.placeholder."compose-stacks/databases/pg_dump_healthcheck_id"}
    PGADMIN_CONFIG_LOCAL_PATH=${config.sops.templates."pgadmin-config_local.py".path}
  ''
  + lib.concatMapStringsSep "\n" (
    name:
    "${envVarName name}=${
      config.sops.placeholder."compose-stacks/databases/postgres/passwords/${name}"
    }"
  ) dbNames;

  # No authelia middleware: pgAdmin is the OIDC relying party itself (see
  # pgadmin-config-local.nix + the Authelia client in auth/authelia-configuration.nix),
  # same pattern as Grafana/CrowdSec-webui/PeerTube elsewhere in this migration — not
  # gated by Authelia's forwardAuth. The direct :8888 publish in docker-compose.yaml
  # stays untouched, independent of Traefik entirely.
  reverseProxy.dynamicConfig.pgadmin = ''
    http:
      routers:
        pgadmin:
          rule: "Host(`pgadmin.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: pgadmin
          tls:
            certResolver: le_main
      services:
        pgadmin:
          loadBalancer:
            servers:
              - url: "http://pgadmin:80"
  '';

  compose-stacks.stacks.databases = {
    inherit composeFile;
    environmentFile = config.sops.templates."compose-databases.env".path;
    dockerNetworks = [
      "db"
      "web"
    ];
    # postgres_backups writes dumps under /mnt/bulk/backups/postgres.
    extraAfter = [
      "mnt-bulk.mount"
      "reverse-proxy-dynamic-config.service"
    ];
  };

  # Provisioning runs as an ExecStartPost on the same unit that brings up
  # postgres/pgadmin/postgres_backups, right after `docker compose up -d` — adding a
  # database or rotating a password restarts the whole stack (a few seconds of
  # Postgres downtime), which is an acceptable cost here in exchange for not needing a
  # second unit: this only ever happens via a deliberate `nixos-rebuild switch`, never
  # as a surprise. `provision`'s `profiles` entry keeps `up -d` itself from also trying
  # to start it as an ordinary service.
  systemd.services.compose-databases.serviceConfig.ExecStartPost = [
    "${pkgs.docker}/bin/docker compose --project-name databases -f ${composeFile} run --rm provision"
  ];

  environment.systemPackages = [ postgresRestore ];
}
