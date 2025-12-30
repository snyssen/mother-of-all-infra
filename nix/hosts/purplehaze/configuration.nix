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
    inputs.disko.nixosModules.disko
    flake.modules.nixos.disko
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
    flake.modules.nixos.steam
    flake.modules.nixos.syncthing
    flake.modules.nixos.printing
    flake.modules.nixos.docker
    flake.modules.nixos.tailscale
  ];

  specialisation = {
    cosmic.configuration = {
      gnome.enable = false;
      cosmic.enable = true;
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
        usbKeysIds = [ "9FBA-884A" ];
        swap.enable = true;
      };
    };

  grub.timeout = 10;
  gnome = {
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
          "Pixel 8 Pro"
          "gaming"
        ];
      };
    };
  };

  stylix = {
    enable = true;
    image = ../../files/wallpapers/icy_pink_sunrise.jpg;
    base16Scheme = "${pkgs.base16-schemes}/share/themes/atelier-cave-light.yaml";
    polarity = "light";

    fonts = {
      monospace = {
        package = pkgs.nerd-fonts.fira-mono;
        name = "FiraMono Nerd Font Mono";
      };
    };
  };
  specialisation = {
    gnome-dark.configuration = {
      stylix = {
        image = lib.mkForce ../../files/wallpapers/purple_bubbles.jpg;
        base16Scheme = lib.mkForce "${pkgs.base16-schemes}/share/themes/stella.yaml";
        polarity = lib.mkForce "dark";
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
