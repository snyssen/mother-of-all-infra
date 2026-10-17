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
  };
}
