{
  pkgs,
  lib,
  inputs,
  flake,
  config,
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
    inputs.sops-nix.nixosModules.sops

    flake.modules.nixos.sops
    flake.modules.nixos.cache
    flake.modules.nixos.grub
    flake.modules.nixos.kbd-layout
    flake.modules.nixos.user
    flake.modules.nixos.locale
    flake.modules.nixos.nh

    # flake.modules.nixos.docker
    flake.modules.nixos.tailscale
  ];

  sops.secrets."tailscale/authKey" = {
    sopsFile = ./data/secrets.yaml;
  };

  grub.timeout = 10;
  user.zsh.enable = true;
  tailscale.autoconnect = {
    enable = true;
    authKeyPath = config.sops.secrets."tailscale/authKey".path;
  };

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
