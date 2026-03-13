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
      ly = "btrfs-luks-bulk-plus-fast-pools";
    in
    {
      layout = ly;
      "${ly}" = {
        mainDiskPath = "/dev/disk/by-id/ata-WDC_WDS500G2B0B-00YS70_204246801987";
        usbKeysIds = [
          "8B34-7D3C" # Philips 8GB
        ];
        swap.enable = true;
        bulkPool.disks = [
          # 1× 4 TB HDD
          "/dev/disk/by-id/ata-ST4000VN008-2DR166_ZDH9AT9F"
          # 2× 2 TB HDD
          "/dev/disk/by-id/ata-ST2000VN004-2E4164_Z524CEHK"
          "/dev/disk/by-id/ata-WDC_WD20EZRZ-00Z5HB0_WD-WCC4N2RYUKT9"
        ];
        vmstorePool.disks = [
          # 2× 1 TB NVMe
          "/dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_1TB_XXXXXXXXXXXXXXXX"
          "/dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_1TB_YYYYYYYYYYYYYYYY"
          # 1× 500 GB NVMe
          "/dev/disk/by-id/nvme-WD_Blue_SN570_500GB_ZZZZZZZZZZZZZZZZ"
        ];
      };
    };

  grub.timeout = 10;

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "no";
  };

  networking.firewall = {
    enable = true;
  };

  # Use systemd-networkd instead of dhcpcd for more reliable DHCP
  # As there was an issue with my DHCP server being on 192.168.1.2 instead of 192.168.1.1
  # and dhcpcd would not trust that IP
  networking.useNetworkd = true;

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
