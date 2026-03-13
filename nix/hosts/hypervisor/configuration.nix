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
      ly = "single-btrfs-luks-bulk-pool";
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
          # TODO: replace each path with the real disk ID from `ls -l /dev/disk/by-id/` on the hypervisor
          # 1× 4 TB HDD
          "/dev/disk/by-id/ata-PLACEHOLDER_4TB_HDD_SERIALNUMBER"
          # 2× 2 TB HDD
          "/dev/disk/by-id/ata-PLACEHOLDER_2TB_HDD_SERIALNUMBER_1"
          "/dev/disk/by-id/ata-PLACEHOLDER_2TB_HDD_SERIALNUMBER_2"
        ];
      };
    };

  grub.timeout = 10;

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = false;
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
