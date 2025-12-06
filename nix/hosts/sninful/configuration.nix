{
  pkgs,
  lib,
  inputs,
  flake,
  ...
}:
let
  syncthingData = import ../../data/syncthing.nix;
in
{

  #
  ## WORKAROUNDS
  #

  # nixpkgs.config.permittedInsecurePackages = [
  #   "libsoup-2.74.3"
  # ];

  # Fix touchpad not responding -> https://discourse.nixos.org/t/touchpad-not-recognizable/19198/10
  boot.blacklistedKernelModules = [ "elan_i2c" ];

  #########################

  imports = [
    inputs.disko.nixosModules.disko
    ./disk-config.nix
    ./hardware-configuration.nix
    inputs.stylix.nixosModules.stylix

    flake.modules.nixos.grub
    flake.modules.nixos.kbd-layout
    flake.modules.nixos.cosmic
    flake.modules.nixos.gnome
    flake.modules.nixos.user
    flake.modules.nixos.locale
    flake.modules.nixos.nh
    flake.modules.nixos.syncthing
    flake.modules.nixos.printing
    flake.modules.nixos.docker
    flake.modules.nixos.tailscale
  ];

  specialisation = {
    gnome.configuration = {
      gnome.enable = true;
      cosmic.enable = false;
    };
  };

  grub.timeout = 10;
  cosmic = {
    enable = lib.mkDefault true;
    autoLogin.enable = true;
  };
  user.zsh.enable = true;

  environment.systemPackages = [
    pkgs.htop
  ];

  syncthing = {
    enable = true;
    username = "snyssen";
    devices = syncthingData.devices;
    folders = {
      Notes = {
        path = "/home/snyssen/Notes";
        devices = [
          "sync.snyssen.be"
          "xps"
          "Pixel 8 Pro"
          "gaming"
        ];
      };
    };
  };

  stylix = {
    enable = true;
    image = ../../files/wallpapers/bear1.jpg;
    base16Scheme = "${pkgs.base16-schemes}/share/themes/atelier-forest.yaml";
    polarity = "dark";

    fonts = {
      monospace = {
        package = pkgs.nerd-fonts.fira-mono;
        name = "FiraMono Nerd Font Mono";
      };
    };
  };

  system.name = "sninful";
  system.stateVersion = "23.05";
}
