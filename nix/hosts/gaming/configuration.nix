{
  pkgs,
  inputs,
  system,
  flake,
  lib,
  config,
  ...
}:
let
  syncthingData = import ../../data/syncthing.nix;
  theming = {
    dark = {
      wallpaper = ../../files/wallpapers/Elite_wallpaper_4k_8.jpg;
      scheme = "horizon-dark";
    };
  };
in
{

  #
  ## WORKAROUNDS
  #

  # nixpkgs.config.permittedInsecurePackages = [
  #   "libsoup-2.74.3"
  # ];

  #########################

  imports = [
    flake.modules.nixos.disko
    ./hardware-configuration.nix

    flake.modules.nixos.sops
    flake.modules.nixos.cache
    flake.modules.nixos.grub
    flake.modules.nixos.nvidia
    flake.modules.nixos.kbd-layout
    flake.modules.nixos.logitech
    flake.modules.nixos.stylix
    flake.modules.nixos.cosmic
    flake.modules.nixos.gaming
    flake.modules.nixos.shell
    flake.modules.nixos.locale
    flake.modules.nixos.nh
    flake.modules.nixos.syncthing
    flake.modules.nixos.docker
    flake.modules.nixos.libvirtd
    flake.modules.nixos.tailscale
    flake.modules.nixos.prometheus-node-exporter
    flake.modules.nixos.sunshine
  ];

  disko =
    let
      ly = "single-btrfs-luks";
    in
    {
      layout = ly;
      "${ly}" = {
        mainDiskPath = "/dev/nvme0n1";
        usbKeysIds = [
          "8B34-7D3C" # Philips 8GB
          "75E6-4B88" # Kingston Data Traveller
        ];
        swap.enable = true;
      };
    };

  sops.defaultSshKeys.mode = "user";
  sops.secrets = {
    "users/snyssen/passwordHash" = {
      neededForUsers = true; # ensure this secret is available before creating the user account that depends on it
    };
  };

  users = {
    mutableUsers = false;
    users.snyssen = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "networkmanager"
      ];
      hashedPasswordFile = config.sops.secrets."users/snyssen/passwordHash".path;
    };
  };

  nvidia.open = true;
  cosmic = {
    enable = lib.mkDefault true;
    autoLogin.enable = true;
  };

  syncthing = {
    username = "snyssen";
    devices = syncthingData.devices;
    folders = {
      PrismLauncher = {
        path = "/home/snyssen/.local/share/PrismLauncher";
        devices = [
          "sync.snyssen.be"
          "blackfog"
        ];
      };
      RetroArch = {
        path = "/home/snyssen/.config/retroarch";
        devices = [
          "sync.snyssen.be"
          "blackfog"
        ];
      };
      KSP = {
        path = "/home/snyssen/Games/Heroic/Kerbal\ Space\ Program/";
        devices = [
          "sync.snyssen.be"
          "blackfog"
        ];
      };
      Notes = {
        path = "/home/snyssen/Notes";
        devices = [
          "sync.snyssen.be"
          "Pixel 8 Pro"
          "sninful"
          "purplehaze"
          "blackfog"
        ];
      };
    };
  };

  libvirtd = {
    enable = true;
    windowsGuestSupport = true;
    desktopClientSupport = true;
  };

  gaming.extraPkgs = with pkgs; [
    ckan
    lutris
  ];

  stylix = with theming.dark; {
    wallpaper = lib.mkDefault wallpaper;
    schemeName = lib.mkDefault scheme;
  };

  # TODO: make this part automatically defined
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
  };
  system.name = "gaming";
  networking.hostName = "gaming";
  system.stateVersion = "23.05";
}
