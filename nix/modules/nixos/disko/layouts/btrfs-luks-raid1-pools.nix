{ config, lib, ... }:
let
  layoutName = "btrfs-luks-raid1-pools";
  cfg = config.disko."${layoutName}";

  # Idempotent USB-key mount script shared by all LUKS containers.
  # Checks /proc/mounts (always available in initrd) to see whether /key is
  # already mounted before attempting to mount it, preventing races when
  # multiple LUKS pre-open hooks run in sequence.
  usbMountScript = ''
    mkdir -m 0755 -p /key
    if ! grep -q ' /key ' /proc/mounts; then
      echo "Waiting for USB key for LUKS decryption to appear..."
      current_attempt=0
      while true; do
        current_attempt=$((current_attempt+1))
        echo "  Attempt $current_attempt/${builtins.toString cfg.usbMount.attempts}"
        if (ls /dev/disk/by-uuid | grep -e '${lib.strings.concatStringsSep "' -e '" cfg.usbKeysIds}' -q) || [ $current_attempt -eq '${builtins.toString cfg.usbMount.attempts}' ]; then
          break
        fi
        sleep ${builtins.toString cfg.usbMount.waitBetweenAttempts}
      done
      echo "Trying to mount USB key..."
      ${lib.strings.concatMapStringsSep " || " (
        id: "mount -n -t vfat -o ro -U ${id} /key"
      ) cfg.usbKeysIds}
    fi
  '';

  # Build all disko disk entries for a single named pool.
  # Index 0 is the *primary* disk: it runs mkfs.btrfs and references all other
  # opened LUKS devices in extraArgs so they join the same RAID1 set.
  # Indexes 1…n are *secondary* disks: their LUKS containers are opened but no
  # filesystem is created on them (Disko's `content` defaults to null), because
  # the primary's mkfs.btrfs already includes them.
  poolDiskEntries = poolName: poolCfg:
    let
      luksName = i: "crypt-${poolName}-${builtins.toString i}";
      luksDevice = i: "/dev/mapper/${luksName i}";
      luksSettings = {
        keyFile = "/key/${cfg.keyFilename}";
        # Inspired from: https://wiki.nixos.org/wiki/Full_Disk_Encryption#Option_2:_Copy_Key_as_file_onto_a_vfat_USB_stick
        fallbackToPassword = true;
        preOpenCommands = usbMountScript;
      } // lib.optionalAttrs (poolCfg.storageMedia == "ssd") {
        # Allow TRIM operations on SSDs/NVMe drives
        allowDiscards = true;
      };
    in
    lib.listToAttrs (
      lib.imap0 (i: diskPath: {
        name = "${poolName}-${builtins.toString i}";
        value = {
          device = diskPath;
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              "luks-${poolName}" = {
                size = "100%";
                content = {
                  type = "luks";
                  name = luksName i;
                  passwordFile = "/tmp/secret.key";
                  settings = luksSettings;
                }
                // lib.optionalAttrs (i == 0) {
                  # Primary disk: create the btrfs RAID1 filesystem.
                  # The secondary device mapper paths are appended so that a
                  # single mkfs.btrfs call creates the full multi-device set.
                  content = {
                    type = "btrfs";
                    extraArgs = [
                      "-L"
                      poolName
                      "-d"
                      "raid1"
                      "-m"
                      "raid1"
                      "-f"
                    ]
                    ++ (lib.lists.drop 1 (lib.imap0 (j: _: luksDevice j) poolCfg.disks));
                    subvolumes = {
                      "/${poolName}" = {
                        mountpoint = poolCfg.mountpoint;
                        mountOptions = [
                          "compress=zstd"
                          "noatime"
                        ];
                      };
                    };
                  };
                };
              };
            };
          };
        };
      }) poolCfg.disks
    );

  # Merge disk entries from every configured pool into a single attrset.
  allPoolDiskEntries = lib.foldl' lib.mergeAttrs { } (
    lib.mapAttrsToList poolDiskEntries cfg.pools
  );
in
{
  options.disko."${layoutName}" = {
    # ── OS disk (identical to single-btrfs-luks) ──────────────────────────────
    mainDiskPath = lib.mkOption {
      default = "/dev/sda";
    };
    usbKeysIds = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "List of IDs (as seen under /dev/disk/by-uuid) to look for for mounting your USB key(s)";
    };
    usbMount = {
      attempts = lib.mkOption {
        type = lib.types.ints.positive;
        default = 3;
      };
      waitBetweenAttempts = lib.mkOption {
        type = lib.types.ints.positive;
        default = 5;
      };
    };
    keyFilename = lib.mkOption {
      type = lib.types.str;
      description = "Filename of the key file to look for from the root of the USB disk";
      default = config.system.name;
    };
    swap = {
      enable = lib.mkEnableOption "swap partition";
      size = lib.mkOption {
        type = lib.types.str;
        default = "8G";
      };
    };

    # ── Extra storage pools ───────────────────────────────────────────────────
    pools = lib.mkOption {
      default = { };
      description = ''
        Attribute set of additional btrfs RAID1 storage pools.  Each key
        becomes the pool name (used as the btrfs label, LUKS mapper prefix,
        and default mount-point stem).

        Example with two pools:

          pools = {
            bulk = {
              disks = [ "/dev/disk/by-id/ata-…" "/dev/disk/by-id/ata-…" ];
              storageMedia = "hdd";
            };
            vmstore = {
              disks = [ "/dev/disk/by-id/nvme-…" "/dev/disk/by-id/nvme-…" ];
              storageMedia = "ssd";
            };
          };
      '';
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              disks = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                description = ''
                  Ordered list of disk paths (e.g. /dev/disk/by-id/…) that form
                  this btrfs RAID1 pool.

                  At least two disks are required for RAID1.  The first disk in the
                  list is the *primary*: mkfs.btrfs is run there and all other disks
                  are passed as additional devices.  All disks are given their own
                  LUKS container and share the same USB keyfile / passphrase as the
                  OS disk.
                '';
                default = [ ];
                example = [
                  "/dev/disk/by-id/ata-TOSHIBA_HDWD140_XXXXXXXX"
                  "/dev/disk/by-id/ata-WDC_WD20EZAZ_WD-XXXXXX1"
                ];
              };
              storageMedia = lib.mkOption {
                type = lib.types.enum [
                  "hdd"
                  "ssd"
                ];
                description = ''
                  Type of storage media used for this pool.
                  - "hdd": spinning hard drives — TRIM/discard is disabled.
                  - "ssd": solid-state drives or NVMe — TRIM/discard is enabled on
                    all LUKS containers in this pool.
                '';
              };
              mountpoint = lib.mkOption {
                type = lib.types.str;
                description = "Mountpoint for this btrfs RAID1 pool.";
                default = "/mnt/${name}";
              };
            };
          }
        )
      );
    };
  };

  config = lib.mkIf (config.disko.layout == layoutName) {
    assertions = lib.mapAttrsToList (poolName: poolCfg: {
      assertion = poolCfg.disks == [ ] || builtins.length poolCfg.disks >= 2;
      message = "disko.${layoutName}.pools.${poolName}.disks: btrfs RAID1 requires at least 2 disks.";
    }) cfg.pools;

    # Kernel modules needed for mounting USB VFAT devices in initrd stage
    boot.initrd.kernelModules = [
      "uas"
      "usbcore"
      "usb_storage"
      "vfat"
      "nls_cp437"
      "nls_iso8859_1"
    ];

    disko.devices = {
      disk = {
        # ── OS (NVMe) disk ──────────────────────────────────────────────────
        main = {
          device = cfg.mainDiskPath;
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                label = "boot";
                name = "ESP";
                size = "512M";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = [
                    "defaults"
                  ];
                };
              };
              luks = {
                size = "100%";
                label = "luks";
                content = {
                  type = "luks";
                  name = "cryptroot";
                  passwordFile = "/tmp/secret.key";
                  settings = {
                    allowDiscards = true; # Allow TRIM operations on SSD
                    keyFile = "/key/${cfg.keyFilename}";
                    # Inspired from: https://wiki.nixos.org/wiki/Full_Disk_Encryption#Option_2:_Copy_Key_as_file_onto_a_vfat_USB_stick
                    fallbackToPassword = true;
                    preOpenCommands = usbMountScript;
                  };
                  content = {
                    type = "btrfs";
                    extraArgs = [
                      "-L"
                      "nixos"
                      "-f"
                    ];
                    subvolumes = {
                      "/root" = {
                        mountpoint = "/";
                        mountOptions = [
                          "subvol=root"
                          "compress=zstd"
                          "noatime"
                        ];
                      };
                      "/home" = {
                        mountpoint = "/home";
                        mountOptions = [
                          "subvol=home"
                          "compress=zstd"
                          "noatime"
                        ];
                      };
                      "/nix" = {
                        mountpoint = "/nix";
                        mountOptions = [
                          "subvol=nix"
                          "compress=zstd"
                          "noatime"
                        ];
                      };
                      "/swap" = lib.mkIf cfg.swap.enable {
                        mountpoint = "/swap";
                        swap.swapfile.size = cfg.swap.size;
                      };
                    };
                  };
                };
              };
            };
          };
        };
      }
      # ── Extra storage pool disks (conditionally appended) ─────────────────
      // lib.optionalAttrs (cfg.pools != { }) allPoolDiskEntries;
    };

    # Enable autoscrubbing for all btrfs filesystems (OS disk and all pools) to
    # proactively detect and work around potential data corruption.
    services.btrfs.autoScrub.enable = true;
  };
}
