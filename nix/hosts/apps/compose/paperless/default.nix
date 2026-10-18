{ config, pkgs, ... }:
let
  composeFile = "${./.}/docker-compose.yaml";
in
{
  # Local (fast SSD) app-data only. The documents themselves live under /mnt/bulk and
  # are created by paperless-storage-dirs below instead, since ordinary tmpfiles rules
  # run before the NFS mount backing /mnt/bulk is necessarily up.
  #
  # uid 33 / gid 100 mirrors the legacy role's "33 is the Nextcloud user id" choice
  # (see USERMAP_UID in docker-compose.yaml); redis runs as its own 999 as everywhere
  # else here.
  systemd.tmpfiles.rules = [
    "d /var/lib/app-data/paperless/redis 0750 999 999 -"
    "d /var/lib/app-data/paperless/data 0750 33 100 -"
  ];

  sops.secrets = {
    "compose-stacks/paperless/secret_key" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-paperless.service" ];
    };
    "compose-stacks/paperless/oidc/client_id" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-paperless.service" ];
    };
    "compose-stacks/paperless/oidc/client_secret" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-paperless.service" ];
    };
    # Hashed, for Authelia's own client config — same plaintext/hash split already used
    # for Grafana/CrowdSec/PeerTube/pgAdmin/Immich's OIDC clients.
    "compose-stacks/paperless/oidc/client_secret_hash" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-auth.service" ];
    };
  };

  # The secret key and the OIDC client id/secret are carried over unchanged from the
  # legacy vault rather than rotated, and both have to be:
  #
  # - PAPERLESS_SECRET_KEY is what signs session cookies *and* what Django's
  #   PasswordResetTokenGenerator and allauth's stored state derive from. Rotating it
  #   alongside an imported database is not fatal, but it invalidates every session and
  #   every outstanding token for no gain here.
  # - the OIDC client secret is shared state with Authelia's client entry below, and
  #   the client id is what the imported socialaccount rows point at.
  #
  # The database password is the exception: it is *not* the legacy one. Paperless'
  # Postgres role lives in the central `databases` cluster, which provisions every role
  # from its own sops-held PG_PASSWORD_* values — so this references that stack's
  # secret rather than duplicating a second password for the same role.
  sops.templates."compose-paperless.env".content = ''
    PAPERLESS_DBPASS=${config.sops.placeholder."compose-stacks/databases/postgres/passwords/paperless"}
    PAPERLESS_SECRET_KEY=${config.sops.placeholder."compose-stacks/paperless/secret_key"}
    PAPERLESS_URL=https://paperless.${config.domains.main}
    PAPERLESS_OIDC_CLIENT_ID=${config.sops.placeholder."compose-stacks/paperless/oidc/client_id"}
    PAPERLESS_OIDC_CLIENT_SECRET=${
      config.sops.placeholder."compose-stacks/paperless/oidc/client_secret"
    }
    PAPERLESS_OIDC_SERVER_URL=https://auth.${config.domains.main}/.well-known/openid-configuration
  '';

  # Authelia-gated, but not in the usual "nothing gets through without a session" way:
  # Paperless is an OIDC relying party in its own right (PAPERLESS_SOCIALACCOUNT_*), so
  # the forwardAuth middleware exists here only to enforce the one thing Paperless
  # cannot express itself — keeping Django's /admin away from non-sysadmins. The
  # access_control rules in auth/authelia-configuration.nix do that and then bypass the
  # rest of the host, exactly as the legacy config did. Dropping the middleware would
  # silently un-gate /admin; dropping the bypass rule would put a second, redundant
  # login in front of the OIDC flow (and break the mobile/API clients outright).
  reverseProxy.dynamicConfig.paperless = ''
    http:
      routers:
        paperless:
          rule: "Host(`paperless.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: paperless
          middlewares:
            - authelia
          tls:
            certResolver: le_main
      services:
        paperless:
          loadBalancer:
            servers:
              - url: "http://paperless:8000"
  '';

  compose-stacks.stacks.paperless = {
    inherit composeFile;
    environmentFile = config.sops.templates."compose-paperless.env".path;
    dockerNetworks = [
      "web"
      "db"
    ];
    # Documents, the consume inbox and the nightly export all live on the NFS mount.
    extraAfter = [
      "mnt-bulk.mount"
      "reverse-proxy-dynamic-config.service"
      "paperless-storage-dirs.service"
    ];
  };

  # Same shape as streaming-storage-dirs / immich-storage-dirs: /mnt/bulk subpaths
  # can't go through ordinary tmpfiles rules (those run early in boot, before the NFS
  # mount is up). 0750 rather than the streaming stack's 0774 — these are personal
  # documents, and the only consumers are uid 33 (paperless, and later Nextcloud
  # reading `consume`).
  systemd.services.paperless-storage-dirs = {
    description = "Create /mnt/bulk directories the paperless stack expects";
    after = [ "mnt-bulk.mount" ];
    requires = [ "mnt-bulk.mount" ];
    before = [ "compose-paperless.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "paperless-storage-dirs" ''
        set -euo pipefail
        install -d -m 0750 -o 33 -g 100 \
          /mnt/bulk/paperless/media \
          /mnt/bulk/paperless/export \
          /mnt/bulk/paperless/consume
      '';
    };
  };

  # Replaces the legacy role's root crontab entry (`43 22 * * * docker exec paperless
  # document_exporter ../export`). The export is a self-contained, application-agnostic
  # copy of every document plus a manifest — the one artifact that can rebuild the
  # library with neither this Postgres nor this Paperless version, which is why prod
  # backs it up as its own autorestic location and why `backrest.plans.paperless-export`
  # does the same here.
  #
  # `../export` in the legacy command resolved against the image's WORKDIR to the same
  # /usr/src/paperless/export the volume is mounted at; spelled absolutely here so it
  # no longer depends on that WORKDIR.
  #
  # `--delete` is a deliberate divergence from prod, which omits it. Without the flag
  # the exporter only ever adds, so a document deleted in the UI stays in the export
  # forever: the directory grows without bound and stops being the mirror of the
  # library it is supposed to be. Protection against a *wrong* deletion comes from the
  # restic snapshots of this directory (daily 14 / weekly 4 / monthly 6 / yearly 1),
  # not from the export being append-only.
  #
  # The one case where the flag bites: run against an empty or not-yet-restored
  # database, the exporter finds no documents and therefore deletes everything here.
  # That is reachable during the migration, since `prod-import paperless` restarts the
  # stack when it finishes — run `postgres-restore paperless` before the next 22:43, or
  # pass `--keep-stopped` so the export cannot fire at all. Recoverable either way,
  # from a snapshot or by re-running the export once the database is back.
  #
  # --no-progress-bar because there is no TTY under systemd: the progress bar would
  # otherwise write carriage-return spam into the journal.
  systemd.services.paperless-export = {
    description = "Export the paperless document library to /mnt/bulk/paperless/export";
    after = [ "compose-paperless.service" ];
    serviceConfig = {
      Type = "oneshot";
      # -T because there is no TTY under systemd. Goes through `docker compose exec`
      # rather than `docker exec <name>`: containers here have no container_name:, so
      # the project/service pair is the only stable handle.
      ExecStart = "${pkgs.docker}/bin/docker compose --project-name paperless -f ${composeFile} exec -T paperless document_exporter /usr/src/paperless/export --delete --no-progress-bar";
    };
  };

  systemd.timers.paperless-export = {
    description = "Nightly paperless document export";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 22:43:00";
      # Deliberately not Persistent: a missed run is caught by the next night, whereas
      # catching up would fire a full re-export of the whole library during boot —
      # which is exactly when the NFS mount and the stack are least settled. Same
      # behaviour as the cron entry this replaces.
      Persistent = false;
    };
  };
}
