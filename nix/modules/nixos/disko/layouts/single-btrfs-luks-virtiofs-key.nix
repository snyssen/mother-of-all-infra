# This layout is intended to be used by VMs running on KVM/QEMU
# with a single virtio disk and virtiofs for passing the LUKS key file from the host into the initrd.
{ config, lib, ... }:
let
  layoutName = "single-btrfs-luks-virtiofs-key";
  cfg = config.disko."${layoutName}";
in
{
  options.disko."${layoutName}" = {
    mainDiskPath = lib.mkOption {
      type = lib.types.str;
      default = "/dev/vda";
      description = "Device path of the main disk (e.g. /dev/vda for a KVM virtio disk)";
    };
    virtiofsTag = lib.mkOption {
      type = lib.types.str;
      default = "keys";
      description = "virtiofs share tag as configured in the libvirt domain XML";
    };
    mountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/run/keys";
      description = "Mountpoint inside initrd where the virtiofs key share is mounted";
    };
    keyFileName = lib.mkOption {
      type = lib.types.str;
      default = "luks.key";
      description = "Filename of the LUKS key file inside the virtiofs share";
    };
    qcowOptions = {
      diskImageSize = lib.mkOption {
        type = lib.types.str;
        default = "32G";
        description = "Size of the qcow2 disk image to create (e.g. '64G')";
      };
    };
    swap = {
      enable = lib.mkEnableOption "swap partition" // {
        default = true;
      };
      size = lib.mkOption {
        type = lib.types.str;
        default = "8G";
        description = "Size of the swap file (e.g. '4G', '8G')";
      };
    };
  };

  config = lib.mkIf (config.disko.layout == layoutName) {
    boot.initrd.systemd.services.mount-luks-key-virtiofs = {
      description = "Mount virtiofs key share before LUKS activation";
      wantedBy = [ "systemd-cryptsetup@cryptroot.service" ];
      before = [ "systemd-cryptsetup@cryptroot.service" ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
      script = ''
        mkdir -m 0700 -p ${cfg.mountPoint}
        echo "Mounting virtiofs key share (${cfg.virtiofsTag}) at ${cfg.mountPoint}..."
        mount -n -o ro -t virtiofs ${cfg.virtiofsTag} ${cfg.mountPoint}
      '';
    };

    boot.initrd.systemd.services.umount-luks-key-virtiofs = {
      description = "Unmount virtiofs key share after LUKS activation";
      wantedBy = [ "systemd-cryptsetup@cryptroot.service" ];
      after = [ "systemd-cryptsetup@cryptroot.service" ];
      before = [ "initrd-switch-root.target" ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig = {
        Type = "oneshot";
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
      script = ''
        if grep -q ' ${cfg.mountPoint} ' /proc/mounts; then
          echo "Unmounting virtiofs key share at ${cfg.mountPoint}..."
          umount ${cfg.mountPoint}
        fi
      '';
    };

    # Kernel modules needed for mounting virtiofs shares in the initrd stage
    boot.initrd.kernelModules = [
      "virtio_pci"
      "virtio_blk"
      "virtiofs"
    ];

    disko.imageBuilder.imageFormat = "qcow2";
    disko.devices = {
      disk = {
        main = {
          device = cfg.mainDiskPath;
          type = "disk";
          imageSize = cfg.qcowOptions.diskImageSize;
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
                  passwordFile = "/tmp/secret.key"; # written by nixos-anywhere/disko during initial installation
                  settings = {
                    allowDiscards = true;
                    keyFile = "${cfg.mountPoint}/${cfg.keyFileName}";
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
