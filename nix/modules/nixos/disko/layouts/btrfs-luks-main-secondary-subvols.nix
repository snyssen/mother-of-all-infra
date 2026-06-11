{ config, lib, ... }:
let
  layoutName = "btrfs-luks-main-secondary-subvols";
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
  '';

  mkLuksSettings =
    storageMedia:
    {
      keyFile = "/key/${cfg.keyFilename}";
    }
    // lib.optionalAttrs (storageMedia == "ssd") {
      allowDiscards = true;
    };

  mkSubvolumes =
    mountpoints:
    lib.mapAttrs' (
      subvolumeName: mountpoint:
      lib.nameValuePair "/${subvolumeName}" {
        inherit mountpoint;
        mountOptions = [
          "compress=zstd"
          "noatime"
        ];
      }
    ) mountpoints;

  secondaryDiskEntries = lib.listToAttrs (
    lib.imap0 (
      i: secondaryDisk:
      let
        diskName = "secondary-${builtins.toString i}-${secondaryDisk.name}";
      in
      {
        # Sort before "main" so secondary LUKS devices are opened first.
        name = "0-before-${diskName}";
        value = {
          device = secondaryDisk.diskPath;
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              "luks-${diskName}" = {
                size = "100%";
                content = {
                  type = "luks";
                  name = "crypt-${diskName}";
                  passwordFile = "/tmp/secret.key";
                  settings = mkLuksSettings secondaryDisk.storageMedia;
                  content = {
                    type = "btrfs";
                    extraArgs = [
                      "-L"
                      secondaryDisk.name
                      "-f"
                    ];
                    subvolumes = mkSubvolumes secondaryDisk.mountpoints;
                  };
                };
              };
            };
          };
        };
      }
    ) cfg.secondaryDisks
  );

  secondaryDiskNames = lib.map (d: d.name) cfg.secondaryDisks;
  secondaryDiskPaths = lib.map (d: d.diskPath) cfg.secondaryDisks;
  secondaryMountpoints = lib.flatten (
    lib.map (d: builtins.attrValues d.mountpoints) cfg.secondaryDisks
  );
  secondaryLuksDeviceNames = lib.imap0 (
    i: secondaryDisk:
    "crypt-secondary-${builtins.toString i}-${secondaryDisk.name}"
  ) cfg.secondaryDisks;
  secondaryCryptsetupUnits = lib.imap0 (
    i: secondaryDisk:
    "systemd-cryptsetup@crypt-secondary-${builtins.toString i}-${secondaryDisk.name}.service"
  ) cfg.secondaryDisks;
  luksKeyDependencyUnits = [ "systemd-cryptsetup@cryptroot.service" ] ++ secondaryCryptsetupUnits;
  reservedMainMountpoints = [
    "/"
    "/home"
    "/swap"
    "/boot"
  ]
  ++ lib.optionals cfg.main.mountNix [ "/nix" ];
in
{
  options.disko."${layoutName}" = {
    mainDiskPath = lib.mkOption {
      type = lib.types.str;
      default = "/dev/sda";
      description = "Device path of the primary disk (e.g. /dev/mmcblk0 or /dev/sda).";
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

    main = {
      mountNix = lib.mkEnableOption "mounting /nix on the primary disk" // {
        default = true;
      };
    };

    swap = {
      enable = lib.mkEnableOption "swap partition";
      size = lib.mkOption {
        type = lib.types.str;
        default = "8G";
      };
    };

    secondaryDisks = lib.mkOption {
      default = [ ];
      description = ''
        Ordered list of secondary disks. Each secondary disk is provisioned as:
          GPT (single 100% partition) -> LUKS -> btrfs
        and can expose multiple mountpoints through btrfs subvolumes.

        Example:

          secondaryDisks = [
            {
              name = "appdata";
              diskPath = "/dev/disk/by-id/ata-SSD_120GB_XXXXXXXX";
              storageMedia = "ssd";
              mountpoints = {
                nix = "/nix";
                varlib = "/var/lib";
              };
            }
          ];
      '';
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Logical name of this secondary disk (used in labels and LUKS mapper names).";
              example = "appdata";
            };
            diskPath = lib.mkOption {
              type = lib.types.str;
              description = "Disk path (e.g. /dev/disk/by-id/...) for this secondary disk.";
            };
            storageMedia = lib.mkOption {
              type = lib.types.enum [
                "hdd"
                "ssd"
              ];
              description = ''
                Type of storage media used for this secondary disk.
                - "hdd": spinning hard drives — TRIM/discard is disabled.
                - "ssd": solid-state drives or NVMe — TRIM/discard is enabled.
              '';
            };
            mountpoints = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              description = ''
                Mapping of btrfs subvolume name -> mountpoint.

                Example:
                  mountpoints = {
                    nix = "/nix";
                    varlib = "/var/lib";
                  };
              '';
            };
          };
        }
      );
    };
  };

  config = lib.mkIf (config.disko.layout == layoutName) {
    boot.initrd.systemd.services.mount-luks-key = {
      description = "Mount USB key before LUKS activation";
      wantedBy = [ "initrd.target" ] ++ luksKeyDependencyUnits;
      before = luksKeyDependencyUnits;

      unitConfig.DefaultDependencies = "no";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
      script = usbMountScript;
    };

    assertions = [
      {
        assertion = builtins.length secondaryDiskNames == builtins.length (lib.unique secondaryDiskNames);
        message = "disko.${layoutName}.secondaryDisks: each secondary disk name must be unique.";
      }
      {
        assertion = builtins.length secondaryDiskPaths == builtins.length (lib.unique secondaryDiskPaths);
        message = "disko.${layoutName}.secondaryDisks: each secondary disk path must be unique.";
      }
      {
        assertion =
          builtins.length secondaryMountpoints == builtins.length (lib.unique secondaryMountpoints);
        message = "disko.${layoutName}.secondaryDisks: mountpoints must be globally unique across all secondary disks.";
      }
    ]
    ++ (lib.imap0 (i: secondaryDisk: {
      assertion = secondaryDisk.mountpoints != { };
      message = "disko.${layoutName}.secondaryDisks.${builtins.toString i} (${secondaryDisk.name}): at least one mountpoint is required.";
    }) cfg.secondaryDisks)
    ++ (lib.imap0 (i: secondaryDisk: {
      assertion = lib.all (mountpoint: lib.strings.hasPrefix "/" mountpoint) (
        builtins.attrValues secondaryDisk.mountpoints
      );
      message = "disko.${layoutName}.secondaryDisks.${builtins.toString i} (${secondaryDisk.name}): all mountpoints must be absolute paths.";
    }) cfg.secondaryDisks)
    ++ (lib.imap0 (i: secondaryDisk: {
      assertion =
        !(lib.any (mountpoint: builtins.elem mountpoint reservedMainMountpoints) (
          builtins.attrValues secondaryDisk.mountpoints
        ));
      message = "disko.${layoutName}.secondaryDisks.${builtins.toString i} (${secondaryDisk.name}): mountpoints must not collide with primary disk mountpoints (${lib.strings.concatStringsSep ", " reservedMainMountpoints}).";
    }) cfg.secondaryDisks);

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
                  settings = mkLuksSettings "ssd";
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
                      "/nix" = lib.mkIf cfg.main.mountNix {
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
      // lib.optionalAttrs (cfg.secondaryDisks != [ ]) secondaryDiskEntries;
    };

    # Enable autoscrubbing for all btrfs filesystems (primary and secondaries).
    services.btrfs.autoScrub.enable = true;
  };
}
