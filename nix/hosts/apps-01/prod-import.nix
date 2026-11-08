{ lib, ... }:
# TEMPORARY — scaffolding for pulling legacy-production (snyssen.be) data onto this host
# from its restic snapshots.
#
# Why this exists: production's data has to land here with paths translated from the
# legacy layout (/mnt/storage/... and /home/snyssen/data/...) to this host's
# (/mnt/bulk/... and /var/lib/app-data/...). restic does the translation natively via its
# `snapshotID:subfolder` syntax, so each entry is just a (from -> to) pair. The pairs
# live in ./prod-layout.nix, shared with `legacy-import`, which copies the /mnt/storage
# groups off production's data disks instead. For those groups this command is the
# fallback; for everything from production's boot SSD it is the only way.
#
# Delete this file, its import in configuration.nix and ./prod-layout.nix once Phase B is
# done — they have no purpose once prod is gone.
#
# Usage:  prod-import --list
#         prod-import monitoring streaming-config --dry-run
#         prod-import monitoring
#
# Never `--all` at the cutover: that includes the ~10.6 TB of media, which
# `legacy-import` copies from the disks instead.
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

  inRestic = lib.filterAttrs (_: group: group.location != null) (import ./prod-layout.nix);
in
{
  backrest.restore.extra.prod-import = lib.mapAttrs (
    _: group:
    fromLocation group.location
    // {
      inherit (group) stopUnits paths;
    }
  ) inRestic;
}
