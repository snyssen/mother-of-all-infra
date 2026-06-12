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
    if [ ! -e "/key/${cfg.keyFilename}" ]; then
      echo "Waiting for USB key for LUKS decryption to appear..."
      current_attempt=0
      while [ $current_attempt -lt ${builtins.toString cfg.usbMount.attempts} ]; do
        current_attempt=$((current_attempt+1))
        echo "Attempt $current_attempt/${builtins.toString cfg.usbMount.attempts}"
        for id in ${lib.strings.concatStringsSep " " cfg.usbKeysIds}; do
          if [ -e "/dev/disk/by-uuid/$id" ]; then
            echo "Trying /dev/disk/by-uuid/$id"
            mount -n -t vfat -o ro "/dev/disk/by-uuid/$id" /key || true
            [ -e "/key/${cfg.keyFilename}" ] && break
          fi
        done
        [ -e "/key/${cfg.keyFilename}" ] && break
        sleep ${builtins.toString cfg.usbMount.waitBetweenAttempts}
      done
    fi
    # Always exit 0: if key was found, cryptsetup will use it;
    # if not found, cryptsetup will try the keyfile and fall back to password prompt.
    exit 0
  '';

  # Build all disko disk entries for a single named pool.
  #
  # Disko processes disks in alphabetical order of their attribute name.
  # For btrfs RAID1 over LUKS, we need every secondary LUKS container to be
  # opened *before* mkfs.btrfs runs on the primary disk.
  #
  # Inspired by https://discourse.nixos.org/t/btrfs-raid-with-disko/52503:
  # ‣ Secondary disks (indexes 1…n) are named "0-before:${poolName}:${i}".
  #   The '0-' prefix sorts before any letter, so disko will partition and
  #   open these LUKS containers first.  They carry no btrfs content — the
  #   primary's mkfs.btrfs already includes them.
  # ‣ The primary disk (index 0) is named "${poolName}" (no prefix).
  #   It runs mkfs.btrfs with the secondary /dev/mapper/* paths in extraArgs
  #   so they all join the same RAID1 set.
  poolDiskEntries =
    poolName: poolCfg:
    let
      luksName = i: "crypt-${poolName}-${builtins.toString i}";
      luksDevice = i: "/dev/mapper/${luksName i}";
      luksSettings = {
        keyFile = "/key/${cfg.keyFilename}";
      }
      // lib.optionalAttrs (poolCfg.storageMedia == "ssd") {
        # Allow TRIM operations on SSDs/NVMe drives
        allowDiscards = true;
      };

      # ── Secondary disks (processed first thanks to '0-before-' prefix) ────
      # Digits sort before letters in ASCII, so these are formatted before the
      # primary disk entry whose name starts with a letter (the pool name).
      secondaryDiskEntries = lib.listToAttrs (
        lib.imap0 (i: diskPath: {
          name = "0-before-${poolName}-${builtins.toString i}";
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
                    name = luksName (i + 1); # offset by 1 since index 0 is reserved for primary
                    passwordFile = "/tmp/secret.key";
                    settings = luksSettings;
                  };
                };
              };
            };
          };
        }) (lib.lists.drop 1 poolCfg.disks)
      );

      # ── Primary disk (processed after secondaries due to name sorting) ────
      primaryDiskEntry = {
        "${poolName}" = {
          device = builtins.head poolCfg.disks;
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              "luks-${poolName}" = {
                size = "100%";
                content = {
                  type = "luks";
                  name = luksName 0;
                  passwordFile = "/tmp/secret.key";
                  settings = luksSettings;
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
      };
    in
    secondaryDiskEntries // primaryDiskEntry;

  # Merge disk entries from every configured pool into a single attrset.
  # Only include pools with at least 2 disks to avoid builtins.head crashing
  # on invalid pools before assertions fire.
  allPoolDiskEntries = lib.foldl' lib.mergeAttrs { } (
    lib.mapAttrsToList poolDiskEntries (
      lib.filterAttrs (_: poolCfg: builtins.length poolCfg.disks >= 2) cfg.pools
    )
  );

  poolLuksDeviceNames = lib.flatten (
    lib.mapAttrsToList (
      poolName: poolCfg: lib.imap0 (i: _: "crypt-${poolName}-${builtins.toString i}") poolCfg.disks
    ) cfg.pools
  );
  mkCryptsetupUnitVariants =
    mapperName:
    let
      escapedMapperName = lib.replaceStrings [ "-" ] [ "\\x2d" ] mapperName;
    in
    lib.unique [
      "systemd-cryptsetup@${mapperName}.service"
      "systemd-cryptsetup@${escapedMapperName}.service"
    ];
  poolCryptsetupUnits = lib.flatten (
    lib.mapAttrsToList (
      poolName: poolCfg:
      lib.flatten (
        lib.imap0 (i: _: mkCryptsetupUnitVariants "crypt-${poolName}-${builtins.toString i}") poolCfg.disks
      )
    ) cfg.pools
  );
  luksKeyDependencyUnits = [ "systemd-cryptsetup@cryptroot.service" ] ++ poolCryptsetupUnits;
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
    boot.initrd.systemd.services.mount-luks-key = {
      description = "Mount USB key before LUKS activation";
      wantedBy = [
        "initrd.target"
        "cryptsetup-pre.target"
      ]
      ++ luksKeyDependencyUnits;
      before = [ "cryptsetup-pre.target" ] ++ luksKeyDependencyUnits;

      unitConfig.DefaultDependencies = "no";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
      script = usbMountScript;
    };

    assertions =
      # Ensure each pool configured for btrfs RAID1 has at least 2 disks.
      (lib.mapAttrsToList (poolName: poolCfg: {
        assertion = builtins.length poolCfg.disks >= 2;
        message = "disko.${layoutName}.pools.${poolName}.disks: btrfs RAID1 requires at least 2 disks (got ${toString (builtins.length poolCfg.disks)}).";
      }) cfg.pools)
      # Prevent pool names from colliding with reserved disk keys (e.g. \"main\")
      # which are used under `disko.devices.disk` and merged via `//`.
      ++ (lib.mapAttrsToList (poolName: poolCfg: {
        assertion = !(builtins.elem poolName [ "main" ]);
        message = "disko.${layoutName}.pools.${poolName}: pool name '${poolName}' conflicts with reserved disk name 'main' used for the OS disk. Please choose a different pool name.";
      }) cfg.pools);

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
