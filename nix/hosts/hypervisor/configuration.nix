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
    flake.modules.nixos.nfs-exports

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
  };

  nfsExports = {
    enable = true;
    # lanCidr defaults to "192.168.1.0/24" — override here if your LAN differs
    exports = [
      { path = "/mnt/bulk/apps-vm"; }
      {
        path = "/mnt/bulk/homeassistant-vm";
        clients = [
          "192.168.1.0/24" # Home LAN
          "100.64.0.0/10" # Tailnet
        ];
      }
    ];
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
