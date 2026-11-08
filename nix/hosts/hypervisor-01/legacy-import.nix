{
  lib,
  config,
  pkgs,
  ...
}:
# TEMPORARY — copies legacy production's data straight off its two data disks, at disk
# speed, for the Phase B cutover (docs/hypervisor/apps-migration-phase-b.md, step D4).
#
# The legacy box kept everything under /mnt/storage, a mergerfs pool over two ext4 data
# disks (no partition table: a filesystem on each whole disk). Only its boot SSD and its
# SnapRAID parity disk are wiped by the reinstall; the two data disks come across
# untouched, so most of production's data never has to go through restic at all.
#
# Which paths go where comes from ../apps-01/prod-layout.nix, the same table
# `prod-import` (restic, on apps-01) restores from. This tool takes every group whose
# paths are all under /mnt/storage, and writes to this host's side of apps-01's bulk
# mount: apps-01's /mnt/bulk/X is this host's /mnt/bulk/apps/X. For each group it copies
# here, `prod-import <group>` on apps-01 is the fallback, except for the few groups that
# are in no restic location at all (marked "disks only").
#
# Imported on the test hypervisor too, with no disks, for the rehearsal (step P6), which
# points it at loop-mounted images with --sources.
#
# Delete this file, its imports and ../apps-01/prod-layout.nix once Phase B is done.
let
  cfg = config.legacyImport;
  layout = import ../apps-01/prod-layout.nix;

  storagePrefix = "/mnt/storage/";
  bulkPrefix = "/mnt/bulk/";
  fromStorage = row: lib.hasPrefix storagePrefix row.from;

  # A group is copied here only if every one of its paths is on the data disks; one that
  # mixes them with the boot SSD would be half-done by each tool.
  mixed = lib.filterAttrs (
    _: group: lib.any fromStorage group.paths && !lib.all fromStorage group.paths
  ) layout;
  local = lib.filterAttrs (_: group: lib.all fromStorage group.paths) layout;
  restOnly = lib.filterAttrs (_: group: !lib.all fromStorage group.paths) layout;

  # The media goes last in `--all`, so everything a database restore pairs with is in
  # first and those restores can start while the media is still copying.
  isMedia = group: lib.all (row: lib.hasPrefix "/mnt/bulk/streaming/" row.to) group.paths;

  toHost =
    row:
    assert lib.assertMsg (lib.hasPrefix bulkPrefix row.to)
      "legacy-import: ${row.from} goes to ${row.to}, which is not under ${bulkPrefix} (apps-01's bulk mount), so this host cannot reach it.";
    {
      from = lib.removePrefix storagePrefix row.from;
      to = "${cfg.bulkRoot}/${lib.removePrefix bulkPrefix row.to}";
      owner = if row ? owner && row.owner != null then row.owner else "";
    };

  manifest = pkgs.writeText "legacy-import.json" (
    builtins.toJSON {
      inherit (cfg) bulkRoot mountRoot disks;
      order =
        lib.attrNames (lib.filterAttrs (_: g: !isMedia g) local)
        ++ lib.attrNames (lib.filterAttrs (_: g: isMedia g) local);
      groups = lib.mapAttrs (_: group: {
        inherit (group) location;
        rows = map toHost group.paths;
      }) local;
      prodImportOnly = lib.attrNames restOnly;
    }
  );
in
{
  options.legacyImport = {
    disks = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Name of the mountpoint under mountRoot.";
            };
            device = lib.mkOption {
              type = lib.types.str;
              description = "The disk, by id: an ext4 filesystem on the whole disk.";
            };
          };
        }
      );
      default = [ ];
      description = "The legacy box's data disks, mounted read-only by the tool itself.";
    };
    mountRoot = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/legacy";
    };
    bulkRoot = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/bulk/apps";
      description = "This host's side of apps-01's /mnt/bulk (the NFS export).";
    };
  };

  config = {
    assertions = [
      {
        assertion = mixed == { };
        message = "legacy-import: groups ${lib.concatStringsSep ", " (lib.attrNames mixed)} in apps-01/prod-layout.nix mix /mnt/storage with other paths; split them.";
      }
    ];

    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "legacy-import";
        runtimeInputs = with pkgs; [
          coreutils
          findutils
          gnugrep
          jq
          rsync
          util-linux
        ];
        text = ''
          MANIFEST=${manifest}
          ${builtins.readFile ./scripts/legacy-import.sh}
        '';
      })
    ];
  };
}
