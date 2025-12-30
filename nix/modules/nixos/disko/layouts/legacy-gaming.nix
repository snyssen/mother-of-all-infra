{ config, lib, ... }:
let
  cfg = config.disko;
  layoutName = "single-btrfs-luks";
in
{
  options.disko = {
    usbKeysIds = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "List of IDs (as seen under /dev/disk/by-uuid) to look for for mounting your USB key(s)";
    };
    keyFilename = lib.mkOption {
      type = lib.types.str;
      description = "Filename of the key file to look for from the root of the USB disk";
      default = config.system.name;
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

    disko.devices =
      let
        luksSettings = {
          keyFile = "/key/${cfg.keyFilename}";
          # Inspired from: https://wiki.nixos.org/wiki/Full_Disk_Encryption#Option_2:_Copy_Key_as_file_onto_a_vfat_USB_stick
          fallbackToPassword = true;
          preOpenCommands = ''
            mkdir -m 0755 -p /key
            # Check if /key is not already mounted
            if [[ ! $(findmnt -M /key) ]]; then
              echo "Trying to mount USB key for LUKS decryption..."
              sleep 3 # Waiting for USB to be ready
              ${lib.strings.concatMapStringsSep " || " (
                id: "mount -n -t vfat -o ro -U ${id} /key"
              ) cfg.usbKeysIds}
            fi
          '';
        };
      in
      {
        disk = {
          main = {
            device = "/dev/nvme1n1";
            type = "disk";
            content = {
              type = "gpt";
              partitions = {
                ESP = {
                  type = "EF00";
                  size = "500M";
                  content = {
                    type = "filesystem";
                    format = "vfat";
                    mountpoint = "/boot";
                    mountOptions = [ "umask=0077" ];
                  };
                };
                luks = {
                  size = "100%";
                  content = {
                    type = "luks";
                    name = "crypted-main";
                    passwordFile = "/tmp/secret.key";
                    settings = lib.mkMerge [
                      luksSettings
                      { allowDiscards = true; }
                    ];
                    content = {
                      type = "filesystem";
                      format = "ext4";
                      mountpoint = "/";
                    };
                  };
                };
              };
            };
          };
          game-ssd = {
            device = "/dev/sdb";
            type = "disk";
            content = {
              type = "gpt";
              partitions = {
                luks = {
                  size = "100%";
                  content = {
                    type = "luks";
                    name = "crypted-game-ssd";
                    passwordFile = "/tmp/secret.key"; # Reuse key
                    settings = lib.mkMerge [
                      luksSettings
                      { allowDiscards = true; }
                    ];
                    content = {
                      type = "filesystem";
                      format = "ext4";
                      mountpoint = "/mnt/game-ssd";
                    };
                  };
                };
              };
            };
          };
          game-hdd = {
            device = "/dev/sda";
            type = "disk";
            content = {
              type = "gpt";
              partitions = {
                luks = {
                  size = "100%";
                  content = {
                    type = "luks";
                    name = "crypted-game-hdd";
                    passwordFile = "/tmp/secret.key"; # Reuse key
                    settings = luksSettings;
                    content = {
                      type = "filesystem";
                      format = "ext4";
                      mountpoint = "/mnt/game-hdd";
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
