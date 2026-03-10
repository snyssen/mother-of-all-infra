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
    inputs.nixos-hardware.nixosModules.framework-12-13th-gen-intel
    flake.modules.nixos.disko
    ./hardware-configuration.nix

    flake.modules.nixos.sops
    flake.modules.nixos.cache
    flake.modules.nixos.grub
    flake.modules.nixos.kbd-layout
    flake.modules.nixos.logitech
    flake.modules.nixos.stylix
    flake.modules.nixos.cosmic
    flake.modules.nixos.gnome
    flake.modules.nixos.user
    flake.modules.nixos.shell
    flake.modules.nixos.locale
    flake.modules.nixos.nh
    flake.modules.nixos.steam
    flake.modules.nixos.syncthing
    flake.modules.nixos.printing
    flake.modules.nixos.docker
    flake.modules.nixos.tailscale
    flake.modules.nixos.sunshine
  ];

  sops.secrets."paperless/api-token" = {
    sopsFile = ./data/secrets.yaml;
    owner = "scanservjs";
    group = "scanservjs";
    mode = "0400";
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
          "blackfog"
        ];
      };
    };
  };

  stylix = with theming.dark; {
    wallpaper = wallpaper;
    schemeName = scheme;
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
      printing = {
        enable = true;
        scanner = {
          enable = true;
          paperless = {
            enable = true;
            apiTokenPath = config.sops.secrets."paperless/api-token".path;
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
