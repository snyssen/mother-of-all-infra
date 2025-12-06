{
  pkgs,
  inputs,
  system,
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

  #########################

  imports = [
    inputs.disko.nixosModules.disko
    ./disk-config.nix
    ./hardware-configuration.nix
    inputs.stylix.nixosModules.stylix

    flake.modules.nixos.grub
    flake.modules.nixos.cosmic
    flake.modules.nixos.gnome
    flake.modules.nixos.user
    flake.modules.nixos.steam
    flake.modules.nixos.nvidia
    flake.modules.nixos.syncthing
    flake.modules.nixos.logitech
    flake.modules.nixos.node-exporter
    flake.modules.nixos.docker
    flake.modules.nixos.tailscale
  ];

  specialisation = {
    cosmic.configuration = {
      gnome.enable = false;
      cosmic.enable = true;
    };
  };

  grub.timeout = 10;
  nvidia.open = true;

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
          "xps"
        ];
      };
      Notes = {
        path = "/home/snyssen/Notes";
        devices = [
          "sync.snyssen.be"
          "xps"
          "Pixel 8 Pro"
          "sninful"
        ];
      };
    };
  };

  # # Fix for time changing between boot of Windows and Linux
  # time.hardwareClockInLocalTime = true;

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

  system.name = "gaming";
  system.stateVersion = "23.05";
}
