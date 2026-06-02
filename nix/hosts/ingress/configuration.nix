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

  # Not part of the default gandicloud.nix, even though it is required
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  #########################

  imports = [
    # Note: no need for disko, as disk is managed on VPS.
    # Thanks to Gandi.net, NixOS is also pre-installed so there is no need to use nixos-anywhere.
    # gandicloud.nix was copied from VPS after initial creation, and replaces the usual hardware-configuration.nix file.
    ./gandicloud.nix

    flake.modules.nixos.sops
    flake.modules.nixos.cache
    flake.modules.nixos.kbd-layout
    flake.modules.nixos.shell
    flake.modules.nixos.locale
    flake.modules.nixos.nh

    # flake.modules.nixos.docker
    flake.modules.nixos.tailscale
    flake.modules.nixos.traefik
    flake.modules.nixos.crowdsec-firewall-bouncer
    flake.modules.nixos.prometheus-node-exporter
    flake.modules.nixos.grafana-alloy

    ./traefik-configuration.nix
  ];

  sops.secrets = {
    "users/snyssen/passwordHash" = {
      neededForUsers = true;
    };
    "tailscale/authKey" = { };
    "crowdsec-firewall-bouncer/api_key" = { };
  };

  users = {
    mutableUsers = false;
    users.snyssen = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
      ];
      hashedPasswordFile = config.sops.secrets."users/snyssen/passwordHash".path;
    };
  };

  tailscale = {
    autoconnect = {
      enable = true;
      authKeyPath = config.sops.secrets."tailscale/authKey".path;
      enableSSH = true;
      tags = [
        "server"
        "nm-exit-node"
      ];
    };
    advertiseExitNode = true;
    advertiseConnector = true;
  };
  crowdsec-firewall-bouncer.apiKeyPath = config.sops.secrets."crowdsec-firewall-bouncer/api_key".path;
  grafana-alloy = {
    varlogs.enable = true;
    journald.enable = true;
  };

  environment.systemPackages = [
    pkgs.btop
  ];

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      80
      443
      25565 # minecraft
    ];
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
}
