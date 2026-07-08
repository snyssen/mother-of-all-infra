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
    # light = {
    #   wallpaper = ../../files/wallpapers/icy_pink_sunrise.jpg;
    #   scheme = "atelier-cave-light";
    # };
    dark = {
      wallpaper = ../../files/wallpapers/foggy_night_bridge.jpg;
      scheme = "nord";
    };
    gaming = {
      wallpaper = ../../files/wallpapers/hazy_dusk_mountains.jpg;
      scheme = "catppuccin-frappe";
    };
  };
in
{

  #
  ## WORKAROUNDS
  #

  #########################

  imports = [
    inputs.nixos-hardware.nixosModules.framework-desktop-amd-ai-max-300-series
    flake.modules.nixos.disko
    ./hardware-configuration.nix

    flake.modules.nixos.sops
    flake.modules.nixos.cache
    flake.modules.nixos.grub
    flake.modules.nixos.kbd-layout
    flake.modules.nixos.logitech
    flake.modules.nixos.stylix
    flake.modules.nixos.gnome
    flake.modules.nixos.cosmic
    flake.modules.nixos.shell
    flake.modules.nixos.locale
    flake.modules.nixos.nh
    flake.modules.nixos.syncthing
    flake.modules.nixos.docker
    flake.modules.nixos.libvirtd
    flake.modules.nixos.tailscale
    flake.modules.nixos.sunshine
    flake.modules.nixos.prometheus-node-exporter
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

  grub.timeout = 10;
  cosmic = {
    enable = lib.mkDefault true;
    autoLogin.enable = true;
  };
  shell.default = "fish";

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
          "purplehaze"
        ];
      };
      PrismLauncher = {
        path = "/home/snyssen/.local/share/PrismLauncher";
        devices = [
          "sync.snyssen.be"
          "gaming"
        ];
      };
      RetroArch = {
        path = "/home/snyssen/.config/retroarch";
        devices = [
          "sync.snyssen.be"
          "gaming"
        ];
      };
      KSP = {
        path = "/home/snyssen/Games/Heroic/Kerbal\ Space\ Program/";
        devices = [
          "sync.snyssen.be"
          "gaming"
        ];
      };
    };
  };

  services.ollama = {
    enable = true;
    # Optional: preload models, see https://ollama.com/library
    loadModels = [
      "deepseek-r1:8b"
      "gemma4:latest"
      "gemma4:31b"
      "qwen3:30b"
      "qwen3-coder:30b"
    ];
  };
  services.open-webui = {
    enable = true;
    port = 8888;
  };

  libvirtd = {
    enable = true;
    windowsGuestSupport = true;
    desktopClientSupport = true;
  };

  stylix = with theming.dark; {
    wallpaper = lib.mkDefault wallpaper;
    schemeName = lib.mkDefault scheme;
  };

  specialisation = {
    gnome.configuration = with theming.dark; {
      cosmic.enable = false;
      gnome.enable = true;
      gnome.autoLogin.enable = true;
      stylix = {
        wallpaper = lib.mkForce wallpaper;
        schemeName = lib.mkForce scheme;
      };
    };
    gaming.configuration = {
      imports = [
        flake.modules.nixos.gaming
      ];
      gaming.extraPkgs = with pkgs; [ ckan ];
      services.ollama.enable = lib.mkForce false;
      services.open-webui.enable = lib.mkForce false;
      stylix = with theming.gaming; {
        wallpaper = wallpaper;
        schemeName = scheme;
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
  system.name = "blackfog";
  networking.hostName = "blackfog";
  system.stateVersion = "23.05";
}
