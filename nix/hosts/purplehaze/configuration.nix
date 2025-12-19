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

  # should be set by blueprint, except it's not: https://github.com/numtide/blueprint/issues/115
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [ inputs.nix-vscode-extensions.overlays.default ];

  #########################

  imports = [
    inputs.nixos-hardware.nixosModules.framework-12-13th-gen-intel
    inputs.disko.nixosModules.disko
    ./disk-config.nix
    ./hardware-configuration.nix
    inputs.stylix.nixosModules.stylix

    flake.modules.nixos.cache
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
    image = ../../files/wallpapers/icy_pink_sunrise.jpg;
    # monokai (dark) ?
    # atelier-cave-light (light) ?
    # moonlight (dark) ?
    # stella (dark) ?
    base16Scheme = "${pkgs.base16-schemes}/share/themes/atelier-cave-light.yaml";
    polarity = "light";

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
  system.name = "sninful";
  networking.hostName = "sninful";
  system.stateVersion = "23.05";
}
