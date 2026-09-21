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
    flake.modules.nixos.crowdsec-firewall-bouncer
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
    ./compose/monitoring/default.nix
    ./compose/auth/default.nix
    ./compose/crowdsec/default.nix
    ./compose/ntfy/default.nix
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
    # Shared across any stack that sends mail, not specific to one stack.
    "smtp/host" = {
      sopsFile = ./data/secrets.yaml;
    };
    "smtp/port" = {
      sopsFile = ./data/secrets.yaml;
    };
    "smtp/user" = {
      sopsFile = ./data/secrets.yaml;
    };
    "smtp/password" = {
      sopsFile = ./data/secrets.yaml;
    };
    "smtp/from_domain" = {
      sopsFile = ./data/secrets.yaml;
    };
  };

  tailscale.autoconnect = {
    enable = true;
    authKeyPath = config.sops.secrets."tailscale/authKey".path;
    enableSSH = true;
  };

  # Points at this host's own new LAPI (compose/crowdsec), not the legacy shared one —
  # matches how `ingress`'s existing, working bouncer reaches its LAPI over HTTPS
  # rather than a local shortcut. Whether other hosts eventually repoint to this new
  # LAPI is a separate, later fleet-wide decision, not made here.
  crowdsec-firewall-bouncer = {
    apiUrl = "https://crowdsec.${config.domains.main}";
    apiKeyPath = config.sops.secrets."compose-stacks/crowdsec/firewall_bouncer/api_key".path;
  };

  grafana-alloy = {
    varlogs.enable = true;
    journald.enable = true;
    nodeMetrics.enable = true;
    cadvisorMetrics.enable = true;
    # TODO: drop the *.snyssen1.xyz entries once domains.main returns to snyssen.be
    # and the legacy *.snyssen.be entries once that box is decommissioned post-cutover.
    loki.endpoints = [
      "http://127.0.0.1:3100/loki/api/v1/push"
      "https://loki.snyssen.be/loki/api/v1/push"
    ];
    remoteWrite.endpoints = [
      "http://127.0.0.1:9090/api/v1/write"
      "https://prometheus.snyssen.be/api/v1/write"
    ];
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
        # Pinned rather than left to auto-allocation (confirmed the live value is
        # already 1000) — the crowdsec-web-ui container runs as uid 1000 (gosu node
        # in its entrypoint), and its sops secret/template are owned by snyssen so
        # Linux's raw-uid permission check lets that container read them without
        # making them world-readable. Auto-allocation is stable across rebuilds in
        # practice, but pinning makes this reproducible even from a from-scratch
        # install, not just "whatever it happened to end up as."
        uid = 1000;
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

  domains.main = "snyssen1.xyz";

  # Traefik routing for argunix now lives in ./compose/reverse-proxy/default.nix,
  # via the shared reverse-proxy.dynamicConfig mechanism, alongside the containerized
  # Traefik instance that replaces this host's previous native one.

  argunix.mode = "both";
  argunix.coordinator = {
    # Only reached through reverse-proxy now (see its argunix dynamic-config
    # fragment) via the docker-bridge firewall trust rule in docker.nix — no longer
    # needs its own port open to the WAN.
    api.openFirewall = false;
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
