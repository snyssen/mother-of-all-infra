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
    flake.modules.nixos.openssh

    flake.modules.nixos.tailscale
    flake.modules.nixos.prometheus-node-exporter
    flake.modules.nixos.grafana-alloy
    flake.modules.nixos.libvirtd
    flake.modules.nixos.nfs-exports

    ./network.nix
    # Transitional: delete with its file once Phase B is done.
    ./legacy-import.nix
  ];

  # Intel iGPU (QuickSync) passthrough for the `apps-01` VM's Jellyfin, as on the test
  # hypervisor (see its configuration.nix for how it was verified there).
  #
  # IOMMU on, with `iommu=pt` so every other device (the pools especially) stays on
  # passthrough-mode DMA. i915 blacklisted host-wide (the box is headless) and vfio-pci
  # claiming the iGPU in initrd, before i915 could bind it. The PCI id is this box's
  # i5-13400 iGPU, from `lspci -nn` (Phase B runbook, step P2); check after the install
  # that it sits alone in its IOMMU group (step D3).
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
  # from `lspci -nn | grep -i vga`
  boot.extraModprobeConfig = "options vfio-pci ids=8086:4682";

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
    loki.endpoints = [
      "https://loki.snyssen.be/loki/api/v1/push"
    ];
    remoteWrite.endpoints = [
      "https://prometheus.snyssen.be/api/v1/write"
    ];
  };

  disko =
    let
      ly = "btrfs-luks-raid1-pools";
    in
    {
      layout = ly;
      "${ly}" = {
        mainDiskPath = "/dev/disk/by-id/nvme-SPCC_M.2_PCIe_SSD_AA230711NV01KG14278";
        # The same two sticks as the test hypervisor, each carrying a second keyfile
        # named after this host (`/key/hypervisor-01`; keyFilename defaults to
        # system.name). Step P4 of the Phase B runbook writes it.
        usbKeysIds = [
          "73A2-0467" # Kingston SD card
          "9FBA-884A" # Generic Flash Disk (no casing)
          "8B34-7D3C" # Philips 8GB
        ];
        usbMount.attempts = 5; # Generic Flash Disk is slooow
        swap.enable = true;
        # !!! nixos-anywhere FORMATS EVERY DISK LISTED HERE. !!!
        #
        # Both pools start with one disk (no redundancy) and grow after the cutover:
        # docs/hypervisor/apps-migration-phase-b.md, steps A1 and A2.
        #
        # NEVER list the legacy box's two data disks before step A1. They hold the
        # production data `legacy-import` copies from, and are its only copy on disk:
        #   ata-ST8000VN004-3CP101_WWZ3XVDG   (8 TB, legacy /mnt/disk1)
        #   ata-ST12000NM0538-2K2101_ZHZ12PTZ (12 TB, legacy /mnt/disk2)
        pools = {
          bulk = {
            disks = [
              # 16 TB Seagate Exos X18, the legacy box's SnapRAID parity disk: the only
              # one of its HDDs that holds no data.
              "/dev/disk/by-id/ata-ST16000NM000J-2TW103_ZR58BLR6"
            ];
            storageMedia = "hdd";
          };
          vmstore = {
            disks = [
              # 1 TB Kingston NVMe, moved from the test hypervisor's vmstore (step P7).
              "/dev/disk/by-id/nvme-KINGSTON_SNV3S1000G_50026B7383A64113"
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

  libvirtd = {
    enable = true;
    vncLanAccess = true;
  };

  # The legacy box's two data disks, which legacy-import copies production's data from.
  # Never formatted by this host's install: see the warning on `pools` above.
  legacyImport.disks = [
    {
      name = "disk1";
      device = "/dev/disk/by-id/ata-ST8000VN004-3CP101_WWZ3XVDG"; # 8 TB IronWolf
    }
    {
      name = "disk2";
      device = "/dev/disk/by-id/ata-ST12000NM0538-2K2101_ZHZ12PTZ"; # 12 TB Exos X14
    }
  ];

  nfsExports = {
    enable = true;
    # lanCidr defaults to "192.168.1.0/24" — override here if your LAN differs
    lanCidr = "100.64.0.0/10"; # Tailnet IP range
    exports = [
      { path = "/mnt/bulk/apps"; }
    ];
  };

  environment.systemPackages = [
    pkgs.btop
    pkgs.screen
    # sgdisk, for the disk procedures in docs/hypervisor/overview.md
    pkgs.gptfdisk
  ];

  # TODO: make this part automatically defined
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
  };
  system.name = "hypervisor-01";
  networking.hostName = "hypervisor-01";
  system.stateVersion = "25.11";
}
