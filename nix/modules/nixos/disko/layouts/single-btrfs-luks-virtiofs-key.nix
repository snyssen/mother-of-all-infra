# This layout is intended to be used by VMs running on KVM/QEMU
# with a single virtio disk and virtiofs for passing the LUKS key file from the host into the initrd.
{
  config,
  lib,
  pkgs,
  ...
}:
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
    autoResizeOnBoot = {
      enable = lib.mkEnableOption "grow root partition/LUKS/Btrfs to fill disk on boot";
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

    systemd.services.disko-grow-root-on-boot = lib.mkIf cfg.autoResizeOnBoot.enable {
      description = "Grow partition 2, cryptroot and Btrfs root to match disk size";
      wantedBy = [ "multi-user.target" ];
      after = [
        "local-fs.target"
        "systemd-cryptsetup@cryptroot.service"
      ];
      wants = [ "systemd-cryptsetup@cryptroot.service" ];
      path = with pkgs; [
        btrfs-progs
        cloud-utils
        cryptsetup
        gnugrep
        systemd
        util-linux
      ];
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        set -euo pipefail

        disk="${cfg.mainDiskPath}"
        if [ ! -b "$disk" ]; then
          echo "Disk $disk not present, skipping resize."
          exit 0
        fi

        case "$disk" in
          *[0-9]) part="''${disk}p2" ;;
          *) part="''${disk}2" ;;
        esac

        if [ ! -b "$part" ]; then
          echo "Partition $part not present, skipping resize."
          exit 0
        fi

        growpart "$disk" 2 || {
          rc=$?
          if [ "$rc" -ne 1 ]; then
            echo "growpart failed with exit code $rc"
            exit "$rc"
          fi
          echo "growpart reported no change required."
        }

        blockdev --rereadpt "$disk" 2>/dev/null || true
        udevadm settle || true

        if [ -e /dev/mapper/cryptroot ]; then
          mounted_here=0
          if ! mountpoint -q ${cfg.mountPoint}; then
            mkdir -m 0700 -p ${cfg.mountPoint}
            if mount -n -o ro -t virtiofs ${cfg.virtiofsTag} ${cfg.mountPoint}; then
              mounted_here=1
            else
              echo "Could not mount virtiofs key share at ${cfg.mountPoint}, continuing without key mount."
            fi
          fi

          key_file="${cfg.mountPoint}/${cfg.keyFileName}"
          if [ -r "$key_file" ]; then
            if ! cryptsetup resize cryptroot --batch-mode --key-file "$key_file"; then
              echo "cryptsetup resize failed, continuing to Btrfs resize step."
            fi
          else
            echo "LUKS key file $key_file is not readable, skipping cryptsetup resize."
          fi

          if [ "$mounted_here" -eq 1 ]; then
            umount ${cfg.mountPoint}
          fi
        else
          echo "cryptroot mapper not found, skipping cryptsetup resize."
          exit 0
        fi

        if findmnt -n -o FSTYPE / | grep -q '^btrfs$'; then
          btrfs filesystem resize max /
        else
          echo "Root filesystem is not Btrfs, skipping filesystem resize."
        fi
      '';
    };

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
