{
  lib,
  config,
  pkgs,
  ...
}:
let
  composeFile = "${./.}/docker-compose.yaml";
  host = "location.${config.domains.main}";

  # Photon, the reverse geocoder, is off for now: it isn't needed to test a restore,
  # and its worldwide index is ~200 GB on prod, two-thirds of this VM's disk. Off means
  # its container is not started at all, so it downloads nothing and deletes nothing,
  # and Dawarich is not pointed at it. Turning it on is this one line — but see the
  # Phase B checklist for the disk space it needs first.
  photon.enable = false;
in
{
  # Owners are the images' own users, not just whatever works on first start: `d` rules
  # re-assert ownership on every activation, so a wrong one would take the directory
  # away from a running container.
  systemd.tmpfiles.rules = [
    # postgis/postgis:*-alpine runs Postgres as the Alpine image's `postgres`, uid 70 —
    # not the 999 of the Debian-based images elsewhere on this host.
    "d /var/lib/app-data/dawarich/postgres 0700 70 70 -"
    # Redis's `redis` user. Also mounted into the database container, as upstream does.
    "d /var/lib/app-data/dawarich/shared 0700 999 999 -"
  ]
  # Local disk, not /mnt/bulk: Photon's search index is a Lucene index, and Lucene's
  # own documentation warns that its file locking is unreliable on NFS. uid 9011 is
  # the image's `photon` user (its default PUID), which it chowns this to on start.
  ++ lib.optional photon.enable "d /var/lib/app-data/dawarich/photon 0755 9011 9011 -";

  # All carried over unchanged from the legacy vault: the database password so the
  # imported dumps restore as is, secret_key_base so sessions and anything Rails
  # encrypted on prod stay valid, and the OIDC client so Authelia's entry matches.
  sops.secrets = {
    "compose-stacks/dawarich/db/password" = {
      sopsFile = ../../data/dawarich.yaml;
    };
    "compose-stacks/dawarich/db_dump_healthcheck_id" = {
      sopsFile = ../../data/dawarich.yaml;
    };
    "compose-stacks/dawarich/secret_key_base" = {
      sopsFile = ../../data/dawarich.yaml;
    };
    "compose-stacks/dawarich/oidc/client_id" = {
      sopsFile = ../../data/dawarich.yaml;
    };
    "compose-stacks/dawarich/oidc/client_secret" = {
      sopsFile = ../../data/dawarich.yaml;
    };
    # Hashed, for Authelia's own client config — same plaintext/hash split as every
    # other OIDC client on this host.
    "compose-stacks/dawarich/oidc/client_secret_hash" = {
      sopsFile = ../../data/dawarich.yaml;
    };
  };

  # PHOTON_UPDATE_STRATEGY: prod's PARALLEL downloads the new index next to the old one
  # before swapping, so it needs twice the index's size free. Left at that, as on prod;
  # revisit together with the disk space.
  sops.templates."compose-dawarich.env".content = ''
    DAWARICH_HOST=${host}
    MAIN_DOMAIN=${config.domains.main}
    DAWARICH_DB_PASSWORD=${config.sops.placeholder."compose-stacks/dawarich/db/password"}
    DAWARICH_DB_DUMP_HEALTHCHECK_ID=${
      config.sops.placeholder."compose-stacks/dawarich/db_dump_healthcheck_id"
    }
    DAWARICH_SECRET_KEY_BASE=${config.sops.placeholder."compose-stacks/dawarich/secret_key_base"}
    DAWARICH_OIDC_CLIENT_ID=${config.sops.placeholder."compose-stacks/dawarich/oidc/client_id"}
    DAWARICH_OIDC_CLIENT_SECRET=${config.sops.placeholder."compose-stacks/dawarich/oidc/client_secret"}
    DAWARICH_OIDC_ISSUER=https://auth.${config.domains.main}
    DAWARICH_PHOTON_API_HOST=${lib.optionalString photon.enable "photon:2322"}
    COMPOSE_PROFILES=${lib.optionalString photon.enable "photon"}
    PHOTON_UPDATE_STRATEGY=PARALLEL
    SMTP_HOST=${config.sops.placeholder."smtp/host"}
    SMTP_PORT=${config.sops.placeholder."smtp/port"}
    SMTP_USER=${config.sops.placeholder."smtp/user"}
    SMTP_PASSWORD=${config.sops.placeholder."smtp/password"}
    DB_BACKUP_HOOKS_PATH=${../databases/hooks}
  '';

  # No forwardAuth: Dawarich is the OIDC relying party itself, and its mobile apps and
  # API keys have no browser session to offer. Access is gated by dawarich_policy on
  # its Authelia client — see auth/authelia-configuration.nix.
  reverseProxy.dynamicConfig.dawarich = ''
    http:
      routers:
        dawarich:
          rule: "Host(`${host}`)"
          entryPoints:
            - websecure
          service: dawarich
          tls:
            certResolver: le_main
      services:
        dawarich:
          loadBalancer:
            servers:
              - url: "http://dawarich_app:3000"
  '';

  compose-stacks.stacks.dawarich = {
    restartTriggers = [
      ../../data/dawarich.yaml
      ../../data/common.yaml
      config.sops.templates."compose-dawarich.env".content
    ];
    inherit composeFile;
    environmentFile = config.sops.templates."compose-dawarich.env".path;
    dockerNetworks = [
      "web"
      "db"
    ];
    extraAfter = [
      "mnt-bulk.mount"
      "reverse-proxy-dynamic-config.service"
      "dawarich-storage-dirs.service"
    ];
  };

  # Same shape as immich-storage-dirs: /mnt/bulk subpaths can't go through ordinary
  # tmpfiles rules, which run before the NFS mount is up. root-owned: the app runs as
  # root in its container (no PUID/PGID, as on prod), and so does the dump sidecar.
  systemd.services.dawarich-storage-dirs = {
    description = "Create /mnt/bulk directories the dawarich stack expects";
    after = [ "mnt-bulk.mount" ];
    requires = [ "mnt-bulk.mount" ];
    before = [ "compose-dawarich.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "dawarich-storage-dirs" ''
        set -euo pipefail
        install -d -m 0750 -o 0 -g 0 \
          /mnt/bulk/dawarich/watched \
          /mnt/bulk/dawarich/storage \
          /mnt/bulk/backups/dawarich
      '';
    };
  };

  # Same registration as Immich's: `postgres-restore dawarich` reaches this stack's own
  # PostgreSQL, and `postgres-restore --all` includes it.
  postgresRestore.instances.dawarich = {
    inherit composeFile;
    envFile = config.sops.templates."compose-dawarich.env".path;
    service = "dawarich_backups";
    dbHost = "dawarich_db";
    dumpDir = "/mnt/bulk/backups/dawarich";
    databases.dawarich = "DAWARICH_DB_PASSWORD";
  };
}
