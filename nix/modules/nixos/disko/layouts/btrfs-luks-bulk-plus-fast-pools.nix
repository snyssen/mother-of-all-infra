{ config, lib, ... }:
let
  layoutName = "btrfs-luks-bulk-plus-fast-pools";
  cfg = config.disko."${layoutName}";

  # Return the LUKS mapper name for bulk disk at index i
  bulkLuksName = i: "crypt-bulk-${builtins.toString i}";

  # Return the /dev/mapper path for bulk disk at index i
  bulkLuksDevice = i: "/dev/mapper/${bulkLuksName i}";

  # Return the LUKS mapper name for vmstore disk at index i
  vmstoreLuksName = i: "crypt-vmstore-${builtins.toString i}";

  # Return the /dev/mapper path for vmstore disk at index i
  vmstoreLuksDevice = i: "/dev/mapper/${vmstoreLuksName i}";

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

  # LUKS settings for the bulk pool HDDs (no allowDiscards – HDDs don't support TRIM)
  bulkLuksSettings = {
    keyFile = "/key/${cfg.keyFilename}";
    # Inspired from: https://wiki.nixos.org/wiki/Full_Disk_Encryption#Option_2:_Copy_Key_as_file_onto_a_vfat_USB_stick
    fallbackToPassword = true;
    preOpenCommands = usbMountScript;
  };

  # LUKS settings for the vmstore pool NVMe drives (allowDiscards enabled for TRIM support)
  vmstoreLuksSettings = {
    allowDiscards = true;
    keyFile = "/key/${cfg.keyFilename}";
    fallbackToPassword = true;
    preOpenCommands = usbMountScript;
  };

  # Build one disko disk entry per bulk pool disk.
  # Index 0 is the *primary* disk: it runs mkfs.btrfs and references all other
  # opened LUKS devices in extraArgs so they join the same RAID1 set.
  # Indexes 1…n are *secondary* disks: their LUKS containers are opened but no
  # filesystem is created on them (Disko's `content` defaults to null), because
  # the primary's mkfs.btrfs already includes them.
  bulkDiskEntries = lib.listToAttrs (
    lib.imap0 (i: diskPath: {
      name = "bulk-${builtins.toString i}";
      value = {
        device = diskPath;
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            luks-bulk = {
              size = "100%";
              content = {
                type = "luks";
                name = bulkLuksName i;
                passwordFile = "/tmp/secret.key";
                settings = bulkLuksSettings;
              }
              // lib.optionalAttrs (i == 0) {
                # Primary disk: create the btrfs RAID1 filesystem.
                # The secondary device mapper paths are appended so that a
                # single mkfs.btrfs call creates the full multi-device set.
                content = {
                  type = "btrfs";
                  extraArgs = [
                    "-L"
                    "bulk"
                    "-d"
                    "raid1"
                    "-m"
                    "raid1"
                    "-f"
                  ]
                  ++ (lib.lists.drop 1 (lib.imap0 (j: _: bulkLuksDevice j) cfg.bulkPool.disks));
                  subvolumes = {
                    "/bulk" = {
                      mountpoint = cfg.bulkPool.mountpoint;
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
    }) cfg.bulkPool.disks
  );

  # Build one disko disk entry per vmstore pool disk.
  # Same pattern as bulkDiskEntries: index 0 is the primary (runs mkfs.btrfs),
  # indexes 1…n are secondary (LUKS opened, no mkfs).
  vmstoreDiskEntries = lib.listToAttrs (
    lib.imap0 (i: diskPath: {
      name = "vmstore-${builtins.toString i}";
      value = {
        device = diskPath;
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            luks-vmstore = {
              size = "100%";
              content = {
                type = "luks";
                name = vmstoreLuksName i;
                passwordFile = "/tmp/secret.key";
                settings = vmstoreLuksSettings;
              }
              // lib.optionalAttrs (i == 0) {
                # Primary disk: create the btrfs RAID1 filesystem.
                content = {
                  type = "btrfs";
                  extraArgs = [
                    "-L"
                    "vmstore"
                    "-d"
                    "raid1"
                    "-m"
                    "raid1"
                    "-f"
                  ]
                  ++ (lib.lists.drop 1 (lib.imap0 (j: _: vmstoreLuksDevice j) cfg.vmstorePool.disks));
                  subvolumes = {
                    "/vmstore" = {
                      mountpoint = cfg.vmstorePool.mountpoint;
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
    }) cfg.vmstorePool.disks
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

    # ── Bulk storage pool ─────────────────────────────────────────────────────
    bulkPool = {
      disks = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = ''
          Ordered list of disk paths (e.g. /dev/disk/by-id/…) that form the
          bulk storage btrfs RAID1 pool.

          At least two disks are required for RAID1.  The first disk in the
          list is the *primary*: mkfs.btrfs is run there and all other disks
          are passed as additional devices.  All disks are given their own LUKS
          container and share the same USB keyfile / passphrase as the OS disk.
        '';
        default = [ ];
        example = [
          "/dev/disk/by-id/ata-TOSHIBA_HDWD140_XXXXXXXX"
          "/dev/disk/by-id/ata-WDC_WD20EZAZ_WD-XXXXXX1"
          "/dev/disk/by-id/ata-WDC_WD20EZAZ_WD-XXXXXX2"
        ];
      };
      mountpoint = lib.mkOption {
        type = lib.types.str;
        description = "Mountpoint for the bulk storage btrfs RAID1 pool.";
        default = "/mnt/bulk";
        example = "/mnt/storage";
      };
    };

    # ── VM store pool (NVMe) ──────────────────────────────────────────────────
    vmstorePool = {
      disks = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = ''
          Ordered list of disk paths (e.g. /dev/disk/by-id/…) that form the
          VM store btrfs RAID1 pool on NVMe drives.

          At least two disks are required for RAID1.  The first disk in the
          list is the *primary*: mkfs.btrfs is run there and all other disks
          are passed as additional devices.  All disks are given their own LUKS
          container (with TRIM/discard support) and share the same USB keyfile /
          passphrase as the OS disk.
        '';
        default = [ ];
        example = [
          "/dev/disk/by-id/nvme-SAMSUNG_MZVLB1T0HBLR-000L7_XXXXXXXX"
          "/dev/disk/by-id/nvme-SAMSUNG_MZVLB1T0HBLR-000L7_YYYYYYYY"
          "/dev/disk/by-id/nvme-WD_Blue_SN570_500GB_ZZZZZZZZ"
        ];
      };
      mountpoint = lib.mkOption {
        type = lib.types.str;
        description = "Mountpoint for the VM store btrfs RAID1 pool.";
        default = "/mnt/vmstore";
        example = "/mnt/vmstore";
      };
    };
  };

  config = lib.mkIf (config.disko.layout == layoutName) {
    assertions = [
      {
        assertion = cfg.bulkPool.disks == [ ] || builtins.length cfg.bulkPool.disks >= 2;
        message = "disko.${layoutName}.bulkPool.disks: btrfs RAID1 requires at least 2 disks.";
      }
      {
        assertion = cfg.vmstorePool.disks == [ ] || builtins.length cfg.vmstorePool.disks >= 2;
        message = "disko.${layoutName}.vmstorePool.disks: btrfs RAID1 requires at least 2 disks.";
      }
    ];

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
      # ── Bulk HDD pool disks (conditionally appended) ──────────────────────
      // lib.optionalAttrs (cfg.bulkPool.disks != [ ]) bulkDiskEntries
      # ── VM store NVMe pool disks (conditionally appended) ─────────────────
      // lib.optionalAttrs (cfg.vmstorePool.disks != [ ]) vmstoreDiskEntries;
    };

    # Enable autoscrubbing for all btrfs subvolumes (OS disk and bulk pool), to proactively detect and work around potential data corruption on the HDDs.
    services.btrfs.autoScrub.enable = true;
  };
}
