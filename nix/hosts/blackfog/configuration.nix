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
    flake.modules.nixos.shell
    flake.modules.nixos.locale
    flake.modules.nixos.nh
    flake.modules.nixos.syncthing
    flake.modules.nixos.docker
    flake.modules.nixos.tailscale
    flake.modules.nixos.sunshine
    flake.modules.nixos.prometheus-node-exporter
    flake.modules.nixos.onedrive
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

  sops.secrets = {
    "users/snyssen/passwordHash" = {
      sopsFile = ./data/secrets.yaml;
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
      initialPassword = config.sops.secrets."users/snyssen/passwordHash".path;
    };
  };

  grub.timeout = 10;
  gnome = {
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
    };
  };

  onedrive.gui.enable = true;

  stylix = with theming.dark; {
    wallpaper = lib.mkDefault wallpaper;
    schemeName = lib.mkDefault scheme;
  };

  specialisation = {
    gaming.configuration = {
      imports = [
        flake.modules.nixos.steam
      ];
      stylix = with theming.gaming; {
        wallpaper = wallpaper;
        schemeName = scheme;
      };
      environment.systemPackages = with pkgs; [
        prismlauncher
        (retroarch.withCores (
          cores: with cores; [
            beetle-psx-hw # PS1
            pcsx2 # PS2
          ]
        ))
      ];
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
