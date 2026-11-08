{ config, pkgs, ... }:
let
  composeFile = "${./.}/docker-compose.yaml";
in
{
  systemd.tmpfiles.rules = [
    # Immich's Postgres runs as uid 999 inside its container, same as the central one.
    # Local SSD rather than /mnt/bulk: this is a live database, and the NFS mount is
    # neither fast enough nor safe for Postgres' fsync expectations.
    "d /var/lib/app-data/immich/postgres 0700 999 999 -"
  ];

  sops.secrets = {
    "compose-stacks/immich/db/password" = {
      sopsFile = ../../data/immich.yaml;
    };
    "compose-stacks/immich/db_dump_healthcheck_id" = {
      sopsFile = ../../data/immich.yaml;
    };
    "compose-stacks/immich/oidc/client_id" = {
      sopsFile = ../../data/immich.yaml;
    };
    "compose-stacks/immich/oidc/client_secret" = {
      sopsFile = ../../data/immich.yaml;
    };
    # Hashed, for Authelia's own client config — same plaintext/hash split already used
    # for Grafana/CrowdSec/PeerTube/pgAdmin's OIDC clients.
    "compose-stacks/immich/oidc/client_secret_hash" = {
      sopsFile = ../../data/immich.yaml;
    };
  };

  # Carried over unchanged from the legacy vault rather than rotated: reusing the DB
  # password means an imported prod dump keeps working, and reusing the OIDC client
  # secret means Authelia's client entry and Immich's own admin-configured OAuth
  # settings still agree after a restore.
  #
  # DB_BACKUP_HOOKS_PATH points at the *databases* stack's hook script rather than a
  # copy: the legacy role mounted ../databases/hooks, which cannot work here since each
  # stack is a separate store path. Referencing the directory makes Nix copy that one
  # directory into the store and hands over its path.
  sops.templates."compose-immich.env".content = ''
    IMMICH_DB_PASSWORD=${config.sops.placeholder."compose-stacks/immich/db/password"}
    IMMICH_DB_DUMP_HEALTHCHECK_ID=${
      config.sops.placeholder."compose-stacks/immich/db_dump_healthcheck_id"
    }
    DB_BACKUP_HOOKS_PATH=${../databases/hooks}
  '';

  # No authelia middleware: Immich is the OIDC relying party itself (its OAuth settings
  # live in its own admin UI, not in env vars), same pattern as Grafana/PeerTube/pgAdmin
  # elsewhere in this migration. Access is gated by the photos_policy on Immich's
  # Authelia client — see auth/authelia-configuration.nix.
  reverseProxy.dynamicConfig.immich = ''
    http:
      routers:
        immich:
          rule: "Host(`photos.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: immich
          tls:
            certResolver: le_main
      services:
        immich:
          loadBalancer:
            servers:
              - url: "http://immich-server:2283"
  '';

  compose-stacks.stacks.immich = {
    restartTriggers = [
      ../../data/immich.yaml
      config.sops.templates."compose-immich.env".content
    ];
    inherit composeFile;
    environmentFile = config.sops.templates."compose-immich.env".path;
    dockerNetworks = [
      "web"
      "db"
    ];
    # Photos and the dump directory both live on the NFS mount.
    extraAfter = [
      "mnt-bulk.mount"
      "reverse-proxy-dynamic-config.service"
      "immich-storage-dirs.service"
    ];
  };

  # /mnt/bulk subpaths can't go through ordinary tmpfiles rules — those run early in
  # boot, before the NFS mount backing /mnt/bulk is necessarily up. Same shape as
  # streaming-storage-dirs. uid 5050 matches the dump sidecar's own user; the photos
  # directory is owned by the server container's uid.
  systemd.services.immich-storage-dirs = {
    description = "Create /mnt/bulk directories the immich stack expects";
    after = [ "mnt-bulk.mount" ];
    requires = [ "mnt-bulk.mount" ];
    before = [ "compose-immich.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "immich-storage-dirs" ''
        set -euo pipefail
        install -d -m 0750 -o 0 -g 0 \
          /mnt/bulk/photos \
          /mnt/bulk/backups/immich
      '';
    };
  };

  # Immich's PostgreSQL registered with the same `postgres-restore` command the central
  # cluster uses. Its database lives in a different container for a real reason (the
  # vectorchord extensions), but that is this stack's problem, not the operator's:
  # `postgres-restore immich` reaches the right place on its own, and
  # `postgres-restore --all` no longer skips it.
  postgresRestore.instances.immich = {
    inherit composeFile;
    envFile = config.sops.templates."compose-immich.env".path;
    service = "backup";
    dbHost = "database";
    dumpDir = "/mnt/bulk/backups/immich";
    databases.immich = "IMMICH_DB_PASSWORD";
  };
}
