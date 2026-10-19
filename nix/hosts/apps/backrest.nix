{ config, pkgs, ... }:
let
  # Every plan backs up on the same schedule and keeps the same depth. Both match the
  # legacy autorestic config (daily at 00:30; keep-daily 14 / weekly 4 / monthly 6 /
  # yearly 1), so retention behaviour doesn't silently change at cutover.
  #
  # These two objects are passed through to Backrest's config.json verbatim — the
  # module types them as free-form, so a misspelled field is accepted here and only
  # surfaces as a broken config at runtime. Field names below were read out of the
  # backrest binary itself rather than guessed.
  schedule = {
    cron = "30 0 * * *";
    clock = "CLOCK_LOCAL";
  };
  retention.policyTimeBucketed = {
    daily = 14;
    weekly = 4;
    monthly = 6;
    yearly = 1;
  };

  mkPlan =
    { paths, stopUnits }:
    {
      inherit
        paths
        stopUnits
        schedule
        retention
        ;
      repo = "apps";
    };
in
{
  # Two repos, deliberately distinct:
  #
  # - backup_snyssen_be: the *live production* repo, registered read-only so Backrest's
  #   UI can browse and restore any of autorestic's existing snapshots onto `apps`
  #   (Backrest indexes a repo's snapshots directly, regardless of what created them).
  #   No plans, and no prune/forget/check policy, ever — `apps` must not be able to
  #   change production's snapshot set.
  # - apps: `apps`'s own backups, a separate repo on the same rest-server (it runs
  #   without --private-repos, so a subpath is served as its own repository). Same LAN
  #   speed, but retention and pruning here can never touch production's snapshots.
  #
  # An off-site B2 copy for `apps` is still to come; until then the generated restore
  # commands take --repo-uri for the "on-site server is unreachable" case.
  sops.secrets."backrest/repos/backup_snyssen_be/password" = {
    sopsFile = ./data/secrets.yaml;
    restartUnits = [ "backrest.service" ];
  };
  sops.secrets."backrest/repos/apps/password" = {
    sopsFile = ./data/secrets.yaml;
    restartUnits = [ "backrest.service" ];
  };
  sops.secrets."backrest/users/snyssen/password_hash" = {
    sopsFile = ./data/secrets.yaml;
    restartUnits = [ "backrest.service" ];
  };

  backrest = {
    enable = true;
    # Direct access without going through Traefik/Authelia — safe to open now that
    # the UI has its own real login (see users below). Only reachable from the
    # tailnet/LAN anyway, never the open WAN (apps has no public-facing interface of
    # its own; see the migration plan).
    openFirewall = true;
    repos.backup_snyssen_be = {
      # On-site dedicated restic REST server — LAN-only, no auth. Chosen over the
      # off-site B2 repo (snyssen-be-autorestic) specifically for restore-testing:
      # LAN speed between it and `apps`, and it's the richer/more complete repo (every
      # autorestic location writes here; only some also go to B2).
      uri = "rest:http://backup.snyssen.be:8000/";
      passwordSecret = "backrest/repos/backup_snyssen_be/password"; # Uses sops templates behind the scene
      # Fixed/stable, not a secret — just needs to stay constant across redeploys.
      # Generated once with `openssl rand -hex 32`.
      guid = "6498b158e271405733d31947e066cf746e6a6a5b07206075cdb55763f09fb9db";
    };
    repos.apps = {
      uri = "rest:http://backup.snyssen.be:8000/apps/";
      passwordSecret = "backrest/repos/apps/password";
      guid = "f4fcafc27628201b204cd752d2ce0b080a833fe0554c94e92caa0284f4fc40d4";
    };
    users.snyssen.passwordHashSecret = "backrest/users/snyssen/password_hash";

    # Plan boundaries mirror the legacy autorestic locations — roughly one per stack,
    # which is also the unit a restore is selected by (`backrest-restore monitoring
    # streaming-config`). Only stacks with state worth keeping appear here:
    #
    # - no `auth`: lldap lives in Postgres, Authelia's sessions in a disposable volume.
    # - no `ntfy`, despite prod having a location for it: every user, ACL and token is
    #   provisioned declaratively from sops (NTFY_AUTH_* in compose/ntfy/default.nix),
    #   so the auth DB is rebuilt from this repo on any rebuild. The rest is the
    #   notification cache, which is disposable. A backup would protect nothing that
    #   isn't already in git.
    # - no media (/mnt/bulk/streaming/media): empty test data today. Those plans arrive
    #   with the real media, which — like prod's movies/tv — stays on-site only.
    plans = {
      # Dumps only, never the live Postgres data directory: a running cluster's files
      # aren't consistently snapshottable, and this matches what prod backs up. Also
      # the only reason `postgres-restore` has anything to read.
      databases = mkPlan {
        paths = [ "/mnt/bulk/backups/postgres" ];
        stopUnits = [ ];
      };
      monitoring = mkPlan {
        # Grafana dashboards and Uptime Kuma's monitor definitions — the hand-made
        # state. Prometheus/Loki are deliberately absent (as on prod): their TSDBs are
        # observability history, large and continuously regenerated, not configuration.
        paths = [
          "/var/lib/app-data/monitoring/grafana"
          "/var/lib/app-data/monitoring/uptime"
        ];
        stopUnits = [ "compose-monitoring.service" ];
      };
      streaming-config = mkPlan {
        # Mirrors prod's `streaming-config` location: app configuration and libraries,
        # never the media itself.
        paths = [
          "/var/lib/app-data/jellyfin"
          "/var/lib/app-data/audiobookshelf"
          "/var/lib/app-data/sonarr/config"
          "/var/lib/app-data/radarr/config"
          "/var/lib/app-data/lidarr/config"
          "/var/lib/app-data/prowlarr/config"
          "/var/lib/app-data/bazarr/config"
          "/var/lib/app-data/pinchflat/config"
          "/var/lib/app-data/lidatube/config"
          "/var/lib/app-data/lidify/config"
          "/var/lib/app-data/peertube/config"
        ];
        stopUnits = [ "compose-streaming.service" ];
      };
      # New relative to prod, which backs this up nowhere: holds the LAPI's machine and
      # bouncer registrations, so losing it means re-enrolling every bouncer by hand.
      crowdsec = mkPlan {
        paths = [
          "/var/lib/app-data/crowdsec/data"
          "/var/lib/app-data/crowdsec-web-ui"
        ];
        stopUnits = [ "compose-crowdsec.service" ];
      };
      # Also new, and tiny: acme.json. Without it a rebuild re-requests a certificate
      # for every hostname at once, and Let's Encrypt's weekly limits turn a second
      # failed attempt into days without TLS.
      reverse-proxy = mkPlan {
        paths = [ "/var/lib/app-data/reverse-proxy/certs" ];
        stopUnits = [ "compose-reverse-proxy.service" ];
      };
      # Immich's dumps, from its own Postgres rather than the central cluster. Separate
      # from the `databases` plan above so the two can be restored independently — they
      # belong to different clusters and nothing correlates them.
      immich = mkPlan {
        paths = [ "/mnt/bulk/backups/immich" ];
        stopUnits = [ ];
      };
      # Mirrors prod's `nextcloud` location exactly: the whole tree, application code
      # included. Prod has no excludes on it (the nextcloud entries in
      # snapraid_config_excludes are parity-array settings, not backup ones), and restic
      # dedupes the PHP tree across snapshots well enough that trimming it is an
      # optimisation, not a correctness matter — custom_apps/ in particular is real
      # state and must stay in.
      #
      # By far the largest plan here once imported (~353 GB on prod), and the one whose
      # first run will take hours.
      nextcloud = mkPlan {
        paths = [ "/mnt/bulk/nextcloud" ];
        stopUnits = [ "compose-nextcloud.service" ];
      };
      # Two plans, mirroring prod's two autorestic locations rather than collapsing
      # them. They hold the same documents in two different forms, and that is the
      # point: `paperless` is the live library (plus the thumbnails/index Paperless
      # rebuilds around it), while `paperless-export` is the portable
      # document_exporter output — restorable with neither this Postgres nor this
      # Paperless version, which is what makes it worth the duplicated bytes.
      #
      # Neither covers the database (the central `databases` plan does) nor
      # /mnt/bulk/paperless/consume, which is a transient inbox, nor the redis dir,
      # which is a disposable task queue — same exclusions as prod.
      paperless = mkPlan {
        paths = [
          "/var/lib/app-data/paperless/data"
          "/mnt/bulk/paperless/media"
        ];
        stopUnits = [ "compose-paperless.service" ];
      };
      paperless-export = mkPlan {
        # Nothing to stop: the export directory is only ever written by the
        # paperless-export timer, never read by the running stack.
        paths = [ "/mnt/bulk/paperless/export" ];
        stopUnits = [ ];
      };
      # The photo library itself — irreplaceable user data, and the one plan here whose
      # size is governed by how much is actually stored rather than by configuration
      # (~88 GB on prod today). Empty until the photos are imported, which costs nothing.
      photos = mkPlan {
        paths = [ "/mnt/bulk/photos" ];
        stopUnits = [ "compose-immich.service" ];
      };
    };
  };

  # Disaster recovery in one command; see scripts/apps-restore.sh for the rationale.
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "apps-restore";
      text = builtins.readFile ./scripts/apps-restore.sh;
    })
  ];

  # Defense in depth: Authelia gates this route same as every other admin UI here, on
  # top of Backrest's own login (declared above) — the latter alone is also what
  # protects the direct/firewall-opened path, which bypasses Authelia entirely.
  reverseProxy.dynamicConfig.backrest = ''
    http:
      routers:
        backrest:
          rule: "Host(`backrest.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: backrest
          middlewares:
            - authelia
          tls:
            certResolver: le_main
      services:
        backrest:
          loadBalancer:
            servers:
              - url: "http://host.docker.internal:9898"
  '';
}
