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

  #########################

  imports = [
    flake.modules.nixos.disko
    ./hardware-configuration.nix

    flake.modules.nixos.sops
    flake.modules.nixos.cache
    flake.modules.nixos.grub
    flake.modules.nixos.kbd-layout
    flake.modules.nixos.shell
    flake.modules.nixos.locale
    flake.modules.nixos.nh

    flake.modules.nixos.tailscale
    flake.modules.nixos.prometheus-node-exporter
    flake.modules.nixos.grafana-alloy
    flake.modules.nixos.libvirtd
    flake.modules.nixos.nfs-exports

    ./network.nix
  ];

  # Intel iGPU (QuickSync) passthrough for the `apps` VM's Jellyfin.
  #
  # Phase 1: enable IOMMU. Verified after deploy+reboot — the GPU (0000:00:02.0) sits
  # completely alone in its own IOMMU group (group 0), not even sharing with its own
  # HD Audio companion device (0000:00:03.0, its own separate group) — no ACS override
  # patch needed. `iommu=pt` keeps every other device (this box's RAID pools
  # especially) on passthrough-mode DMA instead of the slower translated path, since
  # only the GPU is meant to be isolated for VFIO.
  #
  # Phase 2: dedicate the GPU to vfio-pci. i915 is blacklisted host-wide (this is the
  # box's only GPU and it's headless — no display manager, no local graphical session —
  # so losing host-side use of it costs nothing) and vfio-pci claims the device early
  # in initrd, before i915 ever gets a chance to bind it (blacklisting alone doesn't
  # guarantee ordering). `8086:0412` is this specific Haswell chip's PCI id — the one
  # value that will need re-deriving (`lspci -nn`) when this moves to prod hardware.
  boot.kernelParams = [
    "intel_iommu=on"
    "iommu=pt"
  ];
  boot.blacklistedKernelModules = [ "i915" ];
  boot.initrd.kernelModules = [
    "vfio_pci"
    "vfio"
    "vfio_iommu_type1"
  ];
  boot.extraModprobeConfig = "options vfio-pci ids=8086:0412";

  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets = {
    "users/snyssen/passwordHash" = {
      sopsFile = ./data/secrets.yaml;
      neededForUsers = true; # ensure this secret is available before creating the user account that depends on it
    };
    "users/ansible/passwordHash" = {
      sopsFile = ./data/secrets.yaml;
      neededForUsers = true;
    };
    "tailscale/authKey" = {
      sopsFile = ./data/secrets.yaml;
    };
  };
  tailscale.autoconnect = {
    enable = true;
    authKeyPath = config.sops.secrets."tailscale/authKey".path;
    enableSSH = true;
  };

  grafana-alloy = {
    varlogs.enable = true;
    journald.enable = true;
    nodeMetrics.enable = true;
    # TODO: drop the *.snyssen1.xyz entries once domains.main returns to snyssen.be
    # and the legacy *.snyssen.be entries once that box is decommissioned post-cutover.
    loki.endpoints = [
      "https://loki.snyssen.be/loki/api/v1/push"
      "https://loki.snyssen1.xyz/loki/api/v1/push"
    ];
    remoteWrite.endpoints = [
      "https://prometheus.snyssen.be/api/v1/write"
      "https://prometheus.snyssen1.xyz/api/v1/write"
    ];
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
          "9FBA-884A" # Generic Flash Disk (no casing)
          "8B34-7D3C" # Philips 8GB
        ];
        usbMount.attempts = 5; # Generic Flash Disk is slooow
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

  users = {
    mutableUsers = false;
    users = {
      snyssen = {
        isNormalUser = true;
        extraGroups = [
          "networkmanager"
          "wheel"
        ];
        hashedPasswordFile = config.sops.secrets."users/snyssen/passwordHash".path;
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG68A6FS8yzwzaOUsoKHL9bc+2gB1P5OQriFjEWzG/LH snyssen@blackfog"
        ];
      };
      ansible = {
        isNormalUser = true;
        extraGroups = [
          "wheel"
        ];
        hashedPasswordFile = config.sops.secrets."users/ansible/passwordHash".path;
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG68A6FS8yzwzaOUsoKHL9bc+2gB1P5OQriFjEWzG/LH ansible@blackfog"
        ];
      };
    };
  };

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "no";
  };

  libvirtd = {
    enable = true;
    vncLanAccess = true;
  };

  nfsExports = {
    enable = true;
    # lanCidr defaults to "192.168.1.0/24" — override here if your LAN differs
    lanCidr = "100.64.0.0/10"; # Tailnet IP range
    exports = [
      { path = "/mnt/bulk/scrypted"; }
      { path = "/mnt/bulk/apps"; }
    ];
  };

  environment.systemPackages = [
    pkgs.btop
  ];

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
