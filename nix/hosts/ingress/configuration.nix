{
  pkgs,
  lib,
  inputs,
  flake,
  ...
}:
{

  #
  ## WORKAROUNDS
  #

  # should be set by blueprint, except it's not: https://github.com/numtide/blueprint/issues/115
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [ inputs.nix-vscode-extensions.overlays.default ];

  #########################

  imports = [
    inputs.disko.nixosModules.disko
    ./disk-config.nix
    ./hardware-configuration.nix
    inputs.stylix.nixosModules.stylix

    flake.modules.nixos.cache
    flake.modules.nixos.grub
    flake.modules.nixos.kbd-layout
    flake.modules.nixos.user
    flake.modules.nixos.locale
    flake.modules.nixos.nh

    # flake.modules.nixos.docker
    flake.modules.nixos.tailscale
  ];

  grub.timeout = 10;
  user.zsh.enable = true;

  environment.systemPackages = [
    pkgs.htop
  ];

  networking.firewall = {
    enable = true;
  };

  # TODO: make this part automatically defined
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
  };
  system.name = "ingress";
  networking.hostName = "ingress";
  system.stateVersion = "23.05";
}
