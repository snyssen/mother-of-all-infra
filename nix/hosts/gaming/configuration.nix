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

  # nixpkgs.config.permittedInsecurePackages = [
  #   "libsoup-2.74.3"
  # ];

  #########################

  imports = [
    inputs.disko.nixosModules.disko
    flake.modules.nixos.disko
    ./hardware-configuration.nix
    inputs.sops-nix.nixosModules.sops
    inputs.stylix.nixosModules.stylix

    flake.modules.nixos.sops
    flake.modules.nixos.cache
    flake.modules.nixos.grub
    flake.modules.nixos.kbd-layout
    flake.modules.nixos.cosmic
    flake.modules.nixos.gnome
    flake.modules.nixos.user
    flake.modules.nixos.locale
    flake.modules.nixos.nh
    flake.modules.nixos.steam
    flake.modules.nixos.nvidia
    flake.modules.nixos.syncthing
    flake.modules.nixos.logitech
    flake.modules.nixos.prometheus-node-exporter
    flake.modules.nixos.docker
    flake.modules.nixos.tailscale
    flake.modules.nixos.sunshine
  ];

  specialisation = {
    cosmic.configuration = {
      gnome.enable = false;
      cosmic.enable = true;
    };
  };

  disko.layout = "legacy-gaming";
  disko.usbKeysIds = [ "9FBA-884A" ];

  grub.timeout = 10;
  nvidia.open = true;
  gnome = {
    enable = lib.mkDefault true;
    autoLogin.enable = true;
  };
  user.zsh.enable = true;

  prometheus-node-exporter.openFirewall = true;

  environment.systemPackages = with pkgs; [
    lutris
    # nexusmods-app-unfree
    smartmontools
    tmux
    htop
  ];

  syncthing = {
    username = "snyssen";
    devices = syncthingData.devices;
    folders = {
      PrismLauncher = {
        path = "/home/snyssen/.local/share/PrismLauncher";
        devices = [ "sync.snyssen.be" ];
      };
      RetroArch = {
        path = "/home/snyssen/.config/retroarch";
        devices = [
          "sync.snyssen.be"
        ];
      };
      Notes = {
        path = "/home/snyssen/Notes";
        devices = [
          "sync.snyssen.be"
          "Pixel 8 Pro"
          "sninful"
          "purplehaze"
        ];
      };
    };
  };

  # Fix for time changing between boot of Windows and Linux
  time.hardwareClockInLocalTime = true;

  stylix = {
    enable = true;
    image = ../../files/wallpapers/Elite_wallpaper_4k_8.jpg;
    base16Scheme = "${pkgs.base16-schemes}/share/themes/horizon-dark.yaml";
    polarity = "dark";

    fonts = {
      monospace = {
        package = pkgs.nerd-fonts.fira-mono;
        name = "FiraMono Nerd Font Mono";
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
  system.name = "gaming";
  networking.hostName = "gaming";
  system.stateVersion = "23.05";
}
