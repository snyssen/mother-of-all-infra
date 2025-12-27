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

  # Not part of the default gandicloud.nix, even though it is required
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  #########################

  imports = [
    # Note: no need for disko, as disk is managed on VPS.
    # Thanks to Gandi.net, NixOS is also pre-installed so there is no need to use nixos-anywhere.
    # gandicloud.nix was copied from VPS after initial creation, and replaces the usual hardware-configuration.nix file.
    ./gandicloud.nix
    inputs.sops-nix.nixosModules.sops

    flake.modules.nixos.sops
    flake.modules.nixos.cache
    flake.modules.nixos.kbd-layout
    flake.modules.nixos.user
    flake.modules.nixos.locale
    flake.modules.nixos.nh

    # flake.modules.nixos.docker
    flake.modules.nixos.tailscale
    flake.modules.nixos.traefik
    flake.modules.nixos.crowdsec-firewall-bouncer
    flake.modules.nixos.prometheus-node-exporter
  ];

  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets."tailscale/authKey" = {
    sopsFile = ./data/secrets.yaml;
  };
  sops.secrets."crowdsec-firewall-bouncer/api_key" = {
    sopsFile = ./data/secrets.yaml;
  };
  sops.secrets."traefik/letsencrypt_dnsChallenge_apikey" = {
    sopsFile = ./data/secrets.yaml;
  };

  user.zsh.enable = true;
  tailscale.autoconnect = {
    enable = true;
    authKeyPath = config.sops.secrets."tailscale/authKey".path;
    enableSSH = true;
  };
  crowdsec-firewall-bouncer.apiKeyPath = config.sops.secrets."crowdsec-firewall-bouncer/api_key".path;
  traefik.letsencrypt.dnsChallenge.apiKeyPath = config.sops.secrets."traefik/letsencrypt_dnsChallenge_apikey"
  # TODO: configure below to only accept connection from localhost.
  # As soon as we have traefik on the machine, we should use it to only allow our own machine from scraping metrics!
  # Until now, I still want to monitor the host, even if it means the world can also do it...
  # prometheus-node-exporter.listenAddress = "ingress.taild023c5.ts.net";
  prometheus-node-exporter.openFirewall = true;
  # TODO: We also need to configure grafana alloy for sending logs. But Traefik setup is more urgent.

  environment.systemPackages = [
    pkgs.htop
  ];

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      80
      443
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
