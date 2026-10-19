_:
# TEMPORARY — scaffolding for pulling legacy-production (snyssen.be) data onto `apps`.
#
# Why this exists: verifying that a migrated stack behaves identically to prod means
# running it against prod's real data, with paths translated from the legacy layout
# (/mnt/storage/... and /home/snyssen/data/...) to this host's (/mnt/bulk/... and
# /var/lib/app-data/...). restic does the translation natively via its
# `snapshotID:subfolder` syntax, so each entry below is just a (from -> to) pair.
#
# Delete this whole file and its import in configuration.nix at the Phase B cutover —
# it has no purpose once prod is gone.
#
# Usage:  prod-import --list
#         prod-import monitoring streaming-config --dry-run
#         prod-import monitoring
let
  # autorestic stamps every snapshot it makes with ar:location:<name>; the legacy box
  # is the only host writing to this repo, but filtering on it too keeps the selector
  # unambiguous if that ever stops being true.
  fromLocation = name: {
    repo = "backup_snyssen_be";
    snapshotFilter = [
      "--tag"
      "ar:location:${name}"
      "--host"
      "snyssen.be"
    ];
  };

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
in
{
  backrest.restore.extra.prod-import = {
    monitoring = fromLocation "monitoring" // {
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
        {
          # Prod kept uptime beside grafana; here it lives under monitoring/ with the
          # rest of the stack. Kuma resets this to root itself regardless.
          from = "/home/snyssen/data/uptime";
          to = "/var/lib/app-data/monitoring/uptime";
          owner = "0:0";
        }
      ];
    };

    streaming-config = fromLocation "streaming-config" // {
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

    # Media backups, left disabled for now since this is where the bulk of the data is
    # and test VM does not have the storage for it
    # TODO: re-enable when going to prod
    # audiobooks = fromLocation "audiobooks" // {
    #   paths = [
    #     {
    #       from = "/mnt/storage/streaming/media/audiobooks";
    #       to = "/mnt/bulk/streaming/media/audiobooks";
    #     }
    #     {
    #       from = "/mnt/storage/streaming/media/audiobooks_vi";
    #       to = "/mnt/bulk/streaming/media/audiobooks_vi";
    #     }
    #   ];
    # };
    # movies = fromLocation "movies" // {
    #   paths = [
    #     {
    #       from = "/mnt/storage/streaming/media/movies";
    #       to = "/mnt/bulk/streaming/media/movies";
    #     }
    #   ];
    # };
    # tv = fromLocation "tv" // {
    #   paths = [
    #     {
    #       from = "/mnt/storage/streaming/media/tv";
    #       to = "/mnt/bulk/streaming/media/tv";
    #     }
    #   ];
    # };
    # music = fromLocation "music" // {
    #   paths = [
    #     {
    #       from = "/mnt/storage/streaming/media/music";
    #       to = "/mnt/bulk/streaming/media/music";
    #     }
    #     {
    #       from = "/mnt/storage/streaming/media/music_vi";
    #       to = "/mnt/bulk/streaming/media/music_vi";
    #     }
    #   ];
    # };

    postgres = fromLocation "postgres" // {
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
          # restic creates the target and any missing parents itself, so nothing needs
          # to pre-create this. It lands root:root 0755 with the dumps keeping their own
          # 0644 — the same shape /mnt/bulk/backups/postgres already has.
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
    immich = fromLocation "postgres" // {
      stopUnits = [ ];
      paths = [
        {
          from = "/mnt/storage/backups/immich";
          to = "/mnt/bulk/restore/prod-immich";
          owner = "0:0";
        }
      ];
    };

    # ~353 GB, the largest enabled group by a wide margin — expect hours over
    # NFS-over-Tailscale, and run it in tmux. The capacity preflight prices it before
    # anything is written.
    #
    # Nextcloud is all-or-nothing in a way the other stacks are not: its database
    # indexes this tree, so restoring one without the other gives an instance that
    # boots and then cannot find its own files. Pair it with:
    #   postgres-restore nextcloud
    # and leave compose-nextcloud.service stopped until both have landed — the stack
    # ships with autostart = false for exactly this reason.
    nextcloud = fromLocation "nextcloud" // {
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
    # there is nothing to import.
    paperless = fromLocation "paperless" // {
      stopUnits = [ "compose-paperless.service" ];
      paths = [
        {
          # 33:100 rather than prod's 33:1000 — same uid, but gid 1000 means something
          # entirely different on this host (see mediaApps above).
          from = "/home/snyssen/data/paperless/data";
          to = "/var/lib/app-data/paperless/data";
          owner = "33:100";
        }
        {
          from = "/mnt/storage/paperless/media";
          to = "/mnt/bulk/paperless/media";
          owner = "33:100";
        }
      ];
    };

    # Its own autorestic location on prod, so its own group here. Roughly doubles what
    # `paperless` above restores (document_exporter writes a full copy of every
    # original), which is why it is separately selectable — run it on its own, or skip
    # it entirely and let the nightly paperless-export timer regenerate it once the
    # library is in place.
    # Left as documentation, but I decided to comment it since it brings no value to the migration (data will be rebuilt anyway)
    # paperless-export = fromLocation "paperless-export" // {
    #   # Nothing live reads this directory; only the export timer writes it.
    #   stopUnits = [ ];
    #   paths = [
    #     {
    #       from = "/mnt/storage/paperless/export";
    #       to = "/mnt/bulk/paperless/export";
    #       owner = "33:100";
    #     }
    #   ];
    # };

    # ~88 GB, by far the largest group that is actually enabled here — expect hours
    # over NFS-over-Tailscale, and run it in tmux. Unlike the dump groups this restores
    # straight to the live path: these are the original files Immich serves, not
    # something that needs loading afterwards.
    #
    # Immich is stopped while they land so it cannot half-index an incomplete library.
    # TODO: re-enable when going to prod
    # photos = fromLocation "photos" // {
    #   stopUnits = [ "compose-immich.service" ];
    #   paths = [
    #     {
    #       from = "/mnt/storage/photos";
    #       to = "/mnt/bulk/photos";
    #       # immich-server runs as root in its container, both here and on prod, so this
    #       # is already an identity mapping — stated rather than left to chance.
    #       owner = "0:0";
    #     }
    #   ];
    # };
  };
}
