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

  # should be set by blueprint, except it's not: https://github.com/numtide/blueprint/issues/115
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [
    inputs.nix-vscode-extensions.overlays.default
    (final: _: {
      # this allows you to access `pkgs.unstable` anywhere in your config
      unstable = import inputs.nixpkgs-unstable {
        inherit (final.stdenv.hostPlatform) system;
        inherit (final) config;
      };
    })
  ];

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
      hashedPasswordFile = config.sops.secrets."users/snyssen/passwordHash".path;
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
        flake.modules.nixos.gaming
      ];

      gaming.extraPkgs = with pkgs; [ ckan ];

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
