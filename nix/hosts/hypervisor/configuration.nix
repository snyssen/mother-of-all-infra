{
  pkgs,
  lib,
  inputs,
  flake,
  config,
  ...
}:
{

  #
  ## WORKAROUNDS
  #

  # should be set by blueprint, except it's not: https://github.com/numtide/blueprint/issues/115
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [
    inputs.nix-vscode-extensions.overlays.default
    (final: _: {
      unstable = import inputs.nixpkgs-unstable {
        inherit (final.stdenv.hostPlatform) system;
        inherit (final) config;
      };
    })
  ];

  #########################

  imports = [
    flake.modules.nixos.disko
    ./hardware-configuration.nix

    flake.modules.nixos.sops
    flake.modules.nixos.cache
    flake.modules.nixos.grub
    flake.modules.nixos.kbd-layout
    flake.modules.nixos.user
    flake.modules.nixos.shell
    flake.modules.nixos.locale
    flake.modules.nixos.nh

    flake.modules.nixos.tailscale
    flake.modules.nixos.libvirtd

    ./network.nix
  ];

  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets."tailscale/authKey" = {
    sopsFile = ./data/secrets.yaml;
  };
  tailscale.autoconnect = {
    enable = true;
    authKeyPath = config.sops.secrets."tailscale/authKey".path;
    enableSSH = true;
  };

  disko =
    let
      ly = "btrfs-luks-raid1-pools";
    in
    {
      layout = ly;
      "${ly}" = {
        # Micron 1 TB NVMe
        mainDiskPath = "/dev/disk/by-id/nvme-Micron_2300_NVMe_1024GB__20292942A517";
        usbKeysIds = [
          "8B34-7D3C" # Philips 8GB
        ];
        swap.enable = true;
        pools = {
          bulk = {
            disks = [
              # 1× 4 TB HDD
              "/dev/disk/by-id/ata-ST4000VN008-2DR166_ZDH9AT9F"
              # 2× 2 TB HDD
              "/dev/disk/by-id/ata-ST2000VN004-2E4164_Z524CEHK"
              # TODO: re-enable to run pool extension test
              # "/dev/disk/by-id/ata-WDC_WD20EZRZ-00Z5HB0_WD-WCC4N2RYUKT9"
            ];
            storageMedia = "hdd";
          };
          vmstore = {
            disks = [
              # 1× 1 TB NVMe
              "/dev/disk/by-id/nvme-KINGSTON_SNV3S1000G_50026B7383A64113"
              # 2× 500 GB NVMe/SATA
              # TODO: re-enable to run pool extension test
              #! WARN: this disk might be failing (could not format it with Disko, lots of I/O errors), but it might also just be a SATA cable issue
              # TODO: re-seat cables and check SMART status of the disk
              # "/dev/disk/by-id/ata-WDC_WDS500G2B0B-00YS70_181146803034"
              "/dev/disk/by-id/ata-WDC_WDS500G2B0B-00YS70_204246801987"
            ];
            storageMedia = "ssd";
          };
        };
      };
    };

  grub.timeout = 10;

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "no";
  };

  libvirtd = {
    enable = true;
    vms = {
      # "apps-vm" = {
      #   uuid = "ba7c2df4-81f4-422d-9cec-074718c95d07";
      #   vcpus = 4;
      #   memoryGiB = 4;
      #   diskSizeGiB = 80;
      # };
      "homeassistant-vm" = {
        uuid = "d1fa0fc8-e862-47cc-9700-014336b7c26c";
        vcpus = 2;
        memoryGiB = 2;
        diskSizeGiB = 32;
      };
    };
  };

  # TODO: make this part automatically defined
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
  };
  system.name = "hypervisor";
  networking.hostName = "hypervisor";
  system.stateVersion = "25.11";
}
