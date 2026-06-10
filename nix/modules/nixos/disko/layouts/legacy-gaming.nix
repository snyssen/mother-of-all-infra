{ config, lib, ... }:
let
  layoutName = "legacy-gaming";
  cfg = config.disko."${layoutName}";

  usbMountScript = ''
    mkdir -m 0755 -p /key
    if ! grep -q ' /key ' /proc/mounts; then
      echo "Trying to mount USB key for LUKS decryption..."
      sleep 3
      ${lib.strings.concatMapStringsSep " || " (
        id: "mount -n -t vfat -o ro -U ${id} /key"
      ) cfg.usbKeysIds}
    fi
  '';
in
{
  options.disko."${layoutName}" = {
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

  config = lib.mkIf (config.disko.layout == layoutName) {
    boot.initrd.systemd.services.mount-luks-key = {
      description = "Mount USB key before LUKS activation";
      wantedBy = [ "cryptsetup-pre.target" ];
      before = [ "cryptsetup-pre.target" ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
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

    disko.devices =
      let
        luksSettings = {
          keyFile = "/key/${cfg.keyFilename}";
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
        };
      };
  };
}
