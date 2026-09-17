{
  inputs,
  flake,
  config,
  pkgs,
  ...
}:
{
  imports = [
    flake.modules.nixos.disko
    ./hardware-configuration.nix

    flake.modules.nixos.sops
    flake.modules.nixos.cache
    flake.modules.nixos.grub
    flake.modules.nixos.kbd-layout
    flake.modules.nixos.shell
    flake.modules.nixos.locale
    flake.modules.nixos.nh

    flake.modules.nixos.tailscale
    # flake.modules.nixos.crowdsec-firewall-bouncer # TODO: generate API key and enable
    flake.modules.nixos.prometheus-node-exporter
    flake.modules.nixos.grafana-alloy
    flake.modules.nixos.docker
    flake.modules.nixos.nfs-mounts
    flake.modules.nixos.compose-stacks
    flake.modules.nixos.domains

    flake.modules.nixos.argunix

    ###################################
    # Application stacks dependencies #
    ###################################
    ./compose/databases/default.nix
    ./compose/reverse-proxy/default.nix
  ];

  disko =
    let
      ly = "single-btrfs-luks-virtiofs-key";
    in
    {
      layout = ly;
      "${ly}" = {
        autoResizeOnBoot.enable = true;
      };
    };

  sops.secrets = {
    "tailscale/authKey" = {
      sopsFile = ./data/secrets.yaml;
    };
    "users/snyssen/passwordHash" = {
      sopsFile = ./data/secrets.yaml;
      neededForUsers = true;
    };
    "argunix/builder_enrollment/token" = {
      sopsFile = ./data/secrets.yaml;
      owner = "argunix";
      group = "argunix";
      mode = "0400";
    };
    "argunix/forges/github/token" = {
      sopsFile = ./data/secrets.yaml;
      owner = "argunix";
      group = "argunix";
      mode = "0400";
    };
    "argunix/caches/cache_snyssen_be/signing_key" = {
      sopsFile = ./data/secrets.yaml;
      owner = "argunix";
      group = "argunix";
      mode = "0400";
    };
    "argunix/caches/cache_snyssen_be/s3_credentials" = {
      sopsFile = ./data/secrets.yaml;
      owner = "argunix";
      group = "argunix";
      mode = "0400";
    };
    "argunix/caches/attic/token" = {
      sopsFile = ./data/secrets.yaml;
      owner = "argunix";
      group = "argunix";
      mode = "0400";
    };
  };

  tailscale.autoconnect = {
    enable = true;
    authKeyPath = config.sops.secrets."tailscale/authKey".path;
    enableSSH = true;
  };

  grafana-alloy = {
    varlogs.enable = true;
    journald.enable = true;
  };

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "no";
  };

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
        ];
      };
    };
  };

  ###########
  # Storage #
  ###########
  # App data is stored in two main directories:
  # - /mnt/bulk: NFS mount to hypervisor for bulk storage - Slow but large, HDD-backed
  # - /var/lib/app-data: Local storage for app data - Fast but small, SSD-backed - lives on the VM disk image (stored in /mnt/vmstore in hypervisor)
  nfsMounts.enable = true;
  nfsMounts.mounts.bulk = {
    path = "/mnt/bulk";
    host = "hypervisor";
    remotePath = "/mnt/bulk/apps";
    dependsOn.tailscale = true;
  };
  systemd.tmpfiles.rules = [
    "d /var/lib/app-data 0755 snyssen snyssen -"
  ];

  docker.networks = [
    "web"
    "db"
    "ldap"
    "monitoring"
  ];
  docker.cadvisor.enable = true;

  domains.main = "snyssen.be";

  # Traefik routing for argunix now lives in ./compose/reverse-proxy/default.nix,
  # via the shared reverse-proxy.dynamicConfig mechanism, alongside the containerized
  # Traefik instance that replaces this host's previous native one.

  argunix.mode = "both";
  argunix.coordinator = {
    builderEnrollment.tokenFile = config.sops.secrets."argunix/builder_enrollment/token".path;
    forges.github = {
      tokenFile = config.sops.secrets."argunix/forges/github/token".path;
      repos = {
        # They all defaults to:
        #  - build main + all PRs
        #  - allowlist PRs: renovate[bot]
        "snyssen/mother-of-all-infra" = { };
        "snyssen/webb-launcher" = { };
        "snyssen/personal-website" = { };
        "snyssen/nix-dev-env" = { };
      };
    };
    caches.cache_snyssen_be.signing_key_file =
      config.sops.secrets."argunix/caches/cache_snyssen_be/signing_key".path;
    environmentFile.path = config.sops.secrets."argunix/caches/cache_snyssen_be/s3_credentials".path;
  };
  argunix.builder.enrollmentTokenFile = config.sops.secrets."argunix/builder_enrollment/token".path;

  # TODO: make this part automatically defined
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
  };
  system.name = "apps";
  networking.hostName = "apps";
  system.stateVersion = "25.11";
}
