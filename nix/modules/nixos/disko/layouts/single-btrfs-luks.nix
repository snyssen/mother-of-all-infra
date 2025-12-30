{ config, lib, ... }:
let
  cfg = config.disko;
  layoutName = "single-btrfs-luks";
in
{
  options.disko = {
    mainDiskPath = lib.mkOption {
      default = "/dev/sda";
    };
    usbKeysIds = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "List of IDs (as seen under /dev/disk/by-uuid) to look for for mounting your USB key(s)";
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
  };

  config = lib.mkIf (cfg.layout == layoutName) {
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
                    # Inspired from: https://wiki.nixos.org/wiki/Full_Disk_Encryption#Option_2:_Copy_Key_as_file_onto_a_vfat_USB_stick
                    fallbackToPassword = true;
                    preOpenCommands = ''
                      mkdir -m 0755 -p /key
                      echo "Trying to mount USB key for LUKS decryption..."
                      sleep 3 # Waiting for USB to be ready
                      ${lib.strings.concatMapStringsSep " || " (
                        id: "mount -n -t vfat -o ro -U ${id} /key"
                      ) cfg.usbKeysIds}
                    '';
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
  };
}
