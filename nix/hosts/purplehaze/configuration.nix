{
  pkgs,
  lib,
  inputs,
  flake,
  config,
  ...
}:
let
  syncthingData = import ../../data/syncthing.nix;
  theming = {
    light = {
      wallpaper = ../../files/wallpapers/icy_pink_sunrise.jpg;
      scheme = "atelier-cave-light";
    };
    dark = {
      wallpaper = ../../files/wallpapers/purple_bubbles.jpg;
      scheme = "stella";
    };
  };
in
{

  #
  ## WORKAROUNDS
  #

  #########################

  imports = [
    inputs.nixos-hardware.nixosModules.framework-12-13th-gen-intel
    flake.modules.nixos.disko
    ./hardware-configuration.nix

    flake.modules.nixos.sops
    flake.modules.nixos.comin
    flake.modules.nixos.cache
    flake.modules.nixos.grub
    flake.modules.nixos.kbd-layout
    flake.modules.nixos.logitech
    flake.modules.nixos.stylix
    flake.modules.nixos.cosmic
    flake.modules.nixos.gnome
    flake.modules.nixos.shell
    flake.modules.nixos.locale
    flake.modules.nixos.nh
    flake.modules.nixos.gaming
    flake.modules.nixos.syncthing
    flake.modules.nixos.printing
    flake.modules.nixos.docker
    flake.modules.nixos.tailscale
    flake.modules.nixos.sunshine

    flake.inputs.argunix.nixosModules.argunix-builder
  ];

  sops.defaultSshKeys.mode = "user";
  sops.secrets = {
    "users/snyssen/passwordHash" = {
      neededForUsers = true; # ensure this secret is available before creating the user account that depends on it
    };
    "argunix/builder_enrollment/token" = {
      sopsFile = ./data/secrets.yaml;
      owner = "argunix-builder";
      group = "argunix-builder";
      mode = "0400";
    };
    "nix-caches/cache_snyssen_be/signing_key" = {
      sopsFile = ./data/secrets.yaml;
      owner = "snyssen";
      mode = "0400";
    };
  };

  comin.desktop.enable = true;

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

  disko =
    let
      ly = "single-btrfs-luks";
    in
    {
      layout = ly;
      "${ly}" = {
        mainDiskPath = "/dev/nvme0n1";
        usbKeysIds = [
          "75E6-4B88" # Kingston Data Traveller
          "8B34-7D3C" # Philips 8GB
        ];
        swap.enable = true;
      };
    };

  grub.timeout = 10;
  gnome = {
    enable = lib.mkDefault true;
    autoLogin.enable = true;
    touchScreen.enable = true;
  };

  syncthing = {
    username = "snyssen";
    devices = syncthingData.devices;
    folders = {
      Notes = {
        path = "/home/snyssen/Notes";
        devices = [
          "sync.snyssen.be"
          "Pixel 8 Pro"
          "gaming"
          "blackfog"
        ];
      };
    };
  };

  gaming = {
    heroic.enable = false;
    minecraft.enable = false;
    retroarch.enable = false;
  };

  stylix = with theming.dark; {
    wallpaper = wallpaper;
    schemeName = scheme;
  };

  services.argunix-builder = {
    enable = true;
    argunixHost = "argunix.snyssen.be";
    argunixPort = 45678;
    enrollmentTokenFile = config.sops.secrets."argunix/builder_enrollment/token".path;
  };

  specialisation = {
    gnome-light.configuration.stylix = with theming.light; {
      wallpaper = lib.mkForce wallpaper;
      schemeName = lib.mkForce scheme;
      isLightTheme = false;
    };
    cosmic.configuration = with theming.dark; {
      gnome.enable = false;
      cosmic.enable = true;
      stylix = {
        wallpaper = lib.mkForce wallpaper;
        schemeName = lib.mkForce scheme;
      };
    };
    scanner.configuration = {
      sops.secrets."paperless/api-token" = {
        sopsFile = ./data/secrets.yaml;
        owner = "scanservjs";
        group = "scanservjs";
        mode = "0400";
      };
      printing = {
        enable = true;
        scanner = {
          enable = true;
          paperless = {
            enable = true;
            apiTokenPath = config.specialisation.scanner.configuration.sops.secrets."paperless/api-token".path;
          };
        };
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
  system.name = "purplehaze";
  networking.hostName = "purplehaze";
  system.stateVersion = "23.05";
}
