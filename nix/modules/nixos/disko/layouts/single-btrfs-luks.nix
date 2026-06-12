{ config, lib, ... }:
let
  layoutName = "single-btrfs-luks";
  cfg = config.disko."${layoutName}";

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
            umount /key 2>/dev/null || true
            mount -n -t vfat -o ro "/dev/disk/by-uuid/$id" /key || true
            if [ -e "/key/${cfg.keyFilename}" ]; then
              break
            fi
          fi
        done
        [ -e "/key/${cfg.keyFilename}" ] && break
        sleep ${builtins.toString cfg.usbMount.waitBetweenAttempts}
      done
    fi
  '';
in
{
  options.disko."${layoutName}" = {
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
    mountPointsNeededForBoot = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "/"
        "/home"
      ];
    };
  };

  config = lib.mkIf (config.disko.layout == layoutName) {
    boot.initrd.systemd.services.mount-luks-key = {
      description = "Mount USB key before LUKS activation";
      wantedBy = [ "systemd-cryptsetup@cryptroot.service" ];
      before = [ "systemd-cryptsetup@cryptroot.service" ];

      unitConfig.DefaultDependencies = "no";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
      script = usbMountScript;
    };

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
      };
    };

    fileSystems = lib.listToAttrs (
      lib.map (vol: {
        name = vol;
        value = {
          neededForBoot = true;
        };
      }) cfg.mountPointsNeededForBoot
    );
  };
}
