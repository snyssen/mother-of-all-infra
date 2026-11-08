# TEMPORARY — the map from legacy production (snyssen.be) to this host, shared by the
# two tools that carry its data across at the Phase B cutover:
#
# - `prod-import` (./prod-import.nix, on apps-01) restores a group from production's
#   restic snapshots;
# - `legacy-import` (../hypervisor-01/legacy-import.nix, on the hypervisor) copies it
#   straight off production's two data disks, which survive the reinstall untouched.
#
# One table, so the paths and owners `prod-import` was tested with on the Phase A VM are
# exactly the ones `legacy-import` uses; only the transport differs. Delete this file
# together with both tools once Phase B is done.
#
# Each group:
#   location   the autorestic location it is in, or null when it is in none (then only
#              `legacy-import` has it, and `prod-import` leaves it out)
#   stopUnits  what `prod-import` stops while restoring (see the backrest restore docs)
#   paths      from (production path) / to (this host's path) / owner (recursive chown)
#
# Every group draws from a single source: production's boot SSD (/home/snyssen/data,
# wiped by the reinstall, so restic only) or its data disks (/mnt/storage). That is why
# paperless and sharkey come as two groups each. `legacy-import` takes the groups whose
# paths are all under /mnt/storage, and refuses a group that mixes the two.
#
# /mnt/storage was a mergerfs pool over the two data disks, so any directory may be
# split across both; `legacy-import` copies from each.
let
  # uid 33 with gid 100 is this host's convention for the *arr/jellyfin family (see the
  # tmpfiles rules in compose/streaming/default.nix). Prod used the deploy user's own
  # gid (1000) instead, so every one of these needs the chown — restic restores numeric
  # owners verbatim, and gid 1000 means something entirely different here.
  mediaApps = "33:100";

  arrConfig = name: {
    from = "/home/snyssen/data/${name}/config";
    to = "/var/lib/app-data/${name}/config";
    owner = mediaApps;
  };

  media = name: {
    from = "/mnt/storage/streaming/media/${name}";
    to = "/mnt/bulk/streaming/media/${name}";
    owner = mediaApps;
  };
in
{
  monitoring = {
    location = "monitoring";
    stopUnits = [ "compose-monitoring.service" ];
    paths = [
      {
        # Note the depth: prod's snapshot is rooted at .../grafana, but only its
        # `data` subdirectory corresponds to this host's path. restic's subfolder
        # syntax handles a path deeper than the snapshot root fine.
        from = "/home/snyssen/data/grafana/data";
        to = "/var/lib/app-data/monitoring/grafana";
        owner = "472:472";
      }
    ];
  };

  streaming-config = {
    location = "streaming-config";
    stopUnits = [ "compose-streaming.service" ];
    paths = [
      # jellyfin and audiobookshelf are straight prefix swaps: prod's directory
      # already has the same data/config/cache/logs shape this host expects.
      {
        from = "/home/snyssen/data/jellyfin";
        to = "/var/lib/app-data/jellyfin";
        owner = mediaApps;
      }
      {
        from = "/home/snyssen/data/audiobookshelf";
        to = "/var/lib/app-data/audiobookshelf";
        owner = mediaApps;
      }
    ]
    ++ map arrConfig [
      "sonarr"
      "radarr"
      "lidarr"
      "prowlarr"
      "bazarr"
      "pinchflat"
      "lidatube"
      "lidify"
    ]
    ++ [
      {
        # PeerTube runs as its own uid on both sides, so this one needs no chown —
        # listed explicitly rather than folded into arrConfig for exactly that reason.
        from = "/home/snyssen/data/peertube/config";
        to = "/var/lib/app-data/peertube/config";
        owner = "999:999";
      }
    ];
  };

  # The media itself, ~10.6 TB. On-site only on prod (movies and tv never went to B2),
  # and far too big to want through restic: `legacy-import` copies it off the disks.
  # Listed for `prod-import` too, as the fallback.
  audiobooks = {
    location = "audiobooks";
    stopUnits = [ "compose-streaming.service" ];
    paths = map media [
      "audiobooks"
      "audiobooks_vi"
    ];
  };
  movies = {
    location = "movies";
    stopUnits = [ "compose-streaming.service" ];
    paths = map media [ "movies" ];
  };
  tv = {
    location = "tv";
    stopUnits = [ "compose-streaming.service" ];
    paths = map media [ "tv" ];
  };
  music = {
    location = "music";
    stopUnits = [ "compose-streaming.service" ];
    paths = map media [
      "music"
      "music_vi"
    ];
  };
  # In no autorestic location: only the disks have these.
  media-extra = {
    location = null;
    stopUnits = [ "compose-streaming.service" ];
    paths = map media [
      "podcasts"
      "podcasts_vi"
      "books"
    ];
  };
  # PeerTube's videos, also in no location. Its media directory is uid/gid 999, the
  # container's own user (compose/streaming/default.nix).
  peertube-data = {
    location = null;
    stopUnits = [ "compose-streaming.service" ];
    paths = [
      {
        from = "/mnt/storage/streaming/peertube/data";
        to = "/mnt/bulk/streaming/peertube/data";
        owner = "999:999";
      }
    ];
  };

  postgres = {
    location = "postgres";
    # Nothing to stop: this writes to a staging directory, not to anything live.
    stopUnits = [ ];
    paths = [
      {
        from = "/mnt/storage/backups/postgres";
        # Deliberately NOT /mnt/bulk/backups/postgres. Landing prod's dumps on the
        # live path would overwrite this host's own dumps and then feed prod's data
        # into this host's `databases` backup plan. Staging them separately keeps the
        # two apart; load them with:
        #   postgres-restore --from /mnt/bulk/restore/prod-postgres
        # Both tools create the target and any missing parents themselves, so nothing
        # needs to pre-create this. It lands root:root 0755 with the dumps keeping
        # their own 0644 — the same shape /mnt/bulk/backups/postgres already has.
        to = "/mnt/bulk/restore/prod-postgres";
        owner = "0:0";
      }
    ];
  };

  # Immich's dumps ride in the same prod location as the central ones (autorestic's
  # `postgres` covers four dump directories), but they belong to Immich's own
  # PostgreSQL, so they get their own group and their own staging path. Load them the
  # same way as any other database — `postgres-restore` knows which instance `immich`
  # belongs to:
  #   postgres-restore --from /mnt/bulk/restore/prod-immich immich
  immich = {
    location = "postgres";
    stopUnits = [ ];
    paths = [
      {
        from = "/mnt/storage/backups/immich";
        to = "/mnt/bulk/restore/prod-immich";
        owner = "0:0";
      }
    ];
  };

  # Pair with `postgres-restore --from /mnt/bulk/restore/prod-postgres` for matrix,
  # matrix_mas and the bridges' databases: that is where nearly all of the state is.
  # This is the media beside them. Prod's location also covers the rest of
  # /mnt/storage/matrix/synapse, which is config generated here — the signing key
  # included, which comes from sops instead — and maubot's plugin databases, which
  # are not carried over (maubot stays on prod only).
  matrix = {
    location = "matrix";
    stopUnits = [ "compose-matrix.service" ];
    paths = [
      {
        from = "/mnt/storage/matrix/synapse/media_store";
        to = "/mnt/bulk/matrix/synapse/media_store";
        owner = "991:991";
      }
    ];
  };

  # Same as immich: Dawarich's dumps ride in prod's `postgres` location but belong to
  # its own PostGIS. Load them with:
  #   postgres-restore --from /mnt/bulk/restore/prod-dawarich dawarich
  dawarich = {
    location = "postgres";
    stopUnits = [ ];
    paths = [
      {
        from = "/mnt/storage/backups/dawarich";
        to = "/mnt/bulk/restore/prod-dawarich";
        owner = "0:0";
      }
    ];
  };
  # The original import files (GPX, Google Takeout...) and generated exports. In no
  # autorestic location, so only the disks have them. root-owned: the app runs as root
  # in its container (compose/dawarich/default.nix).
  dawarich-storage = {
    location = null;
    stopUnits = [ "compose-dawarich.service" ];
    paths = [
      {
        from = "/mnt/storage/dawarich/storage";
        to = "/mnt/bulk/dawarich/storage";
        owner = "0:0";
      }
    ];
  };

  # ~353 GB.
  #
  # Nextcloud is all-or-nothing in a way the other stacks are not: its database
  # indexes this tree, so restoring one without the other gives an instance that
  # boots and then cannot find its own files. Pair it with:
  #   postgres-restore nextcloud
  # and leave compose-nextcloud.service stopped until both have landed.
  nextcloud = {
    location = "nextcloud";
    stopUnits = [ "compose-nextcloud.service" ];
    paths = [
      {
        from = "/mnt/storage/nextcloud";
        to = "/mnt/bulk/nextcloud";
        # www-data on both sides, so this is already an identity mapping — stated
        # rather than left to chance, as with immich's photos.
        owner = "33:33";
      }
    ];
  };

  # Documents, not dumps: these restore straight to the live paths, so Paperless is
  # stopped while they land rather than left to index a half-written library.
  #
  # Prod's `consume` and `redis` directories are deliberately absent — neither is
  # backed up on prod either (one is a transient inbox, the other a task queue), so
  # there is nothing to import. 33:100 rather than prod's 33:1000 — same uid, but gid
  # 1000 means something entirely different on this host (see mediaApps above).
  paperless = {
    location = "paperless";
    stopUnits = [ "compose-paperless.service" ];
    paths = [
      {
        from = "/home/snyssen/data/paperless/data";
        to = "/var/lib/app-data/paperless/data";
        owner = "33:100";
      }
    ];
  };
  paperless-media = {
    location = "paperless";
    stopUnits = [ "compose-paperless.service" ];
    paths = [
      {
        from = "/mnt/storage/paperless/media";
        to = "/mnt/bulk/paperless/media";
        owner = "33:100";
      }
    ];
  };

  # A straight prefix swap. root on both sides: the server runs as root in its
  # container, whatever owner the legacy role gave the directory itself.
  actual-budget = {
    location = "actual-budget";
    stopUnits = [ "compose-actual-budget.service" ];
    paths = [
      {
        from = "/home/snyssen/data/actual-budget";
        to = "/var/lib/app-data/actual-budget";
        owner = "0:0";
      }
    ];
  };

  # Both worlds, from prod's single `minecraft` location. uid 1000 is the image's
  # runtime user on both sides.
  minecraft = {
    location = "minecraft";
    stopUnits = [ "compose-minecraft.service" ];
    paths = [
      {
        from = "/mnt/storage/minecraft/data";
        to = "/mnt/bulk/minecraft/data";
        owner = "1000:1000";
      }
      {
        from = "/mnt/storage/mc-usw/data";
        to = "/mnt/bulk/mc-usw/data";
        owner = "1000:1000";
      }
    ];
  };

  # Pair with `postgres-restore --from /mnt/bulk/restore/prod-postgres sharkey`: the
  # notes and accounts are in the database, and the drive's file records point into
  # `files`. Prod's config directory is skipped: the config file is generated here.
  sharkey = {
    location = "sharkey";
    stopUnits = [ "compose-sharkey.service" ];
    paths = [
      {
        from = "/home/snyssen/data/sharkey/redis";
        to = "/var/lib/app-data/sharkey/redis";
        # Prod gave the group to the deploy user (1000), which means nothing here.
        owner = "999:999";
      }
    ];
  };
  # /mnt/storage/sharkey/files only joined prod's `sharkey` location recently, so
  # snapshots older than that lack it — check with --dry-run first.
  sharkey-files = {
    location = "sharkey";
    stopUnits = [ "compose-sharkey.service" ];
    paths = [
      {
        from = "/mnt/storage/sharkey/files";
        to = "/mnt/bulk/sharkey/files";
        owner = "991:991";
      }
    ];
  };

  # A straight prefix swap. uid 1000 on both sides — the image's `node` user, which on
  # prod happened to be the deploy user too.
  foundryvtt = {
    location = "foundryvtt";
    stopUnits = [ "compose-foundryvtt.service" ];
    paths = [
      {
        from = "/home/snyssen/data/foundryvtt";
        to = "/var/lib/app-data/foundryvtt";
        owner = "1000:1000";
      }
    ];
  };

  # Media only — prod's staticfiles are rebuilt by collectstatic on every start, so
  # there is nothing in them worth importing. Pair with `postgres-restore recipes`.
  recipes = {
    location = "recipes";
    stopUnits = [ "compose-recipes.service" ];
    paths = [
      {
        from = "/mnt/storage/recipes/mediafiles";
        to = "/mnt/bulk/recipes/mediafiles";
        owner = "0:0";
      }
    ];
  };

  # ~88 GB. These are the original files Immich serves, not something that needs loading
  # afterwards; Immich is stopped while they land so it cannot half-index an incomplete
  # library.
  photos = {
    location = "photos";
    stopUnits = [ "compose-immich.service" ];
    paths = [
      {
        from = "/mnt/storage/photos";
        to = "/mnt/bulk/photos";
        # immich-server runs as root in its container, both here and on prod, so this
        # is already an identity mapping — stated rather than left to chance.
        owner = "0:0";
      }
    ];
  };

  # Not imported, on purpose:
  # - paperless-export: roughly doubles paperless' bytes, and the nightly
  #   paperless-export timer regenerates it from the library.
  # - syncthing: apps-01 is a new device and fills its folders from its peers.
  # - torrent/usenet (in-progress downloads), paperless consume and dawarich watched
  #   (inboxes), garage (the Nix cache refills from the next pushes), recipes
  #   staticfiles (rebuilt on start).
}
