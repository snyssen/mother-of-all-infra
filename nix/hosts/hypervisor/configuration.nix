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
  nixpkgs.overlays = [
    inputs.nix-vscode-extensions.overlays.default
    (final: _: {
      unstable = import inputs.nixpkgs-unstable {
        inherit (final.stdenv.hostPlatform) system;
        inherit (final) config;
      };
    })
  ];

  #########################

  imports = [
    flake.modules.nixos.disko
    ./hardware-configuration.nix

    flake.modules.nixos.sops
    flake.modules.nixos.cache
    flake.modules.nixos.grub
    flake.modules.nixos.kbd-layout
    flake.modules.nixos.user
    flake.modules.nixos.shell
    flake.modules.nixos.locale
    flake.modules.nixos.nh

    flake.modules.nixos.tailscale
  ];

  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  # TODO: once the hypervisor SSH host key is known, add its age-encoded public key to .sops.yaml,
  # create nix/hosts/hypervisor/data/secrets.yaml with a tailscale/authKey secret, then enable:
  # sops.secrets."tailscale/authKey" = {
  #   sopsFile = ./data/secrets.yaml;
  # };
  # tailscale.autoconnect = {
  #   enable = true;
  #   authKeyPath = config.sops.secrets."tailscale/authKey".path;
  #   enableSSH = true;
  # };

  disko =
    let
      ly = "single-btrfs-luks";
    in
    {
      layout = ly;
      "${ly}" = {
        mainDiskPath = "/dev/nvme0n1";
        # TODO: set to the actual UUID(s) of the USB key(s) used for LUKS unlock
        # (see /dev/disk/by-uuid on the installed system)
        usbKeysIds = [ ];
        swap.enable = true;
      };
    };

  grub.timeout = 10;

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
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
  system.name = "hypervisor";
  networking.hostName = "hypervisor";
  system.stateVersion = "25.11";
}
