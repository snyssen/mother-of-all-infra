{
  inputs,
  flake,
  config,
  pkgs,
  ...
}:
{

  #
  ## WORKAROUNDS
  #

  #########################

  imports = [
    flake.modules.nixos.disko
    ./hardware-configuration.nix
    ./network.nix

    flake.modules.nixos.sops
    flake.modules.nixos.cache
    flake.modules.nixos.grub
    flake.modules.nixos.kbd-layout
    flake.modules.nixos.shell
    flake.modules.nixos.locale
    flake.modules.nixos.nh

    flake.modules.nixos.tailscale
    flake.modules.nixos.prometheus-node-exporter
    flake.modules.nixos.grafana-alloy
  ];

  # TODO: This layout won't work actually because this host's disk is very small, so we need to add an external disk and move the nix store there
  disko =
    let
      ly = "btrfs-luks-main-secondary-subvols";
    in
    {
      layout = ly;
      "${ly}" = {
        mainDiskPath = "/dev/mmcblk0";
        main.mountNix = false;
        usbKeysIds = [
          "94E8-6B03" # SanDisk 16GB (micro SD card with adapter)
          "8B34-7D3C" # Philips 8GB
          "9FBA-884A" # Generic Flash Disk (no casing)
        ];
        swap.enable = true;
        swap.size = "4G";
        secondaryDisks = [
          {
            name = "data";
            diskPath = "/dev/sda";
            mountpoints = {
              "nix" = "/nix";
              "varlib" = "/var/lib";
            };
            storageMedia = "ssd";
          }
        ];
      };
    };

  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets = {
    "tailscale/authKey" = {
      sopsFile = ./data/secrets.yaml;
    };
    "users/snyssen/passwordHash" = {
      sopsFile = ./data/secrets.yaml;
      neededForUsers = true;
    };
  };

  # Prevent systemd-resolved from binding local port 53 (127.0.0.53),
  # which conflicts with Technitium binding on 0.0.0.0:53.
  services.resolved.extraConfig = ''
    DNSStubListener=no
  '';

  tailscale.autoconnect = {
    enable = true;
    authKeyPath = config.sops.secrets."tailscale/authKey".path;
    enableSSH = true;
  };

  tailscale.certificate = {
    enable = true;
    domain = "technitium-primary.taild023c5.ts.net";
    outputDir = "/var/lib/technitium-dns-server/certs";
    outputName = "technitium-cluster";
    renewOnCalendar = "daily";
    randomizedDelaySec = "15m";
    restartUnits = [ "technitium-dns-server.service" ];
  };

  grafana-alloy = {
    varlogs.enable = true;
    journald.enable = true;
  };

  # Primary Technitium DNS Server instance.
  # Handles all DNS writes; the secondary instance replicates from this one.
  # Web UI available on port 5380 (HTTP) and 53443 (HTTPS).
  # NOTE: DHCP is intentionally disabled here — it will only run on the NUC in production.
  services.technitium-dns-server = {
    enable = true;
    openFirewall = true;
  };

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "no";
  };

  shell.default = "fish";

  users = {
    mutableUsers = false;
    users = {
      snyssen = {
        isNormalUser = true;
        extraGroups = [
          "networkmanager"
          "wheel"
        ];
        hashedPasswordFile = config.sops.secrets."users/snyssen/passwordHash".path;
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG68A6FS8yzwzaOUsoKHL9bc+2gB1P5OQriFjEWzG/LH snyssen@blackfog"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIERQS+yhsr8HU1xoTnIOlJLWD9sJnKbiNQglBH/xaGM7 snyssen@purplehaze"
        ];
      };
    };
  };

  # Add Ansible deps (as target)
  environment.systemPackages = [
    # pkgs.ansible
    # (pkgs.python3.withPackages(ps: [ ps.ansible ps.pip ps.requests ]))
    pkgs.python3
  ];

  # TODO: make this part automatically defined
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
  };
  system.name = "technitium-primary";
  networking.hostName = "technitium-primary";
  system.stateVersion = "25.11";
}
