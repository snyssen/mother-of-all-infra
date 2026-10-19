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
    flake.modules.nixos.backrest
    flake.modules.nixos.postgres-restore

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
    ./compose/streaming/default.nix
    ./compose/immich/default.nix
    ./compose/paperless/default.nix
    ./compose/nextcloud/default.nix
    ./backrest.nix
    # Transitional: delete this line along with the file at the Phase B cutover.
    ./prod-import.nix
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
    # Admin/notification recipient address — used by PeerTube (streaming stack) so
    # far, but shared/global like its smtp/* siblings above, not stack-specific.
    "smtp/to" = {
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
    # Enabled with the nextcloud stack, which logs to its container's stderr rather
    # than to files (see compose/nextcloud/extra-config.nix) — this is what retires the
    # promtail sidecar the legacy role ran. Host-wide rather than per-stack by nature,
    # so every other stack's container output now reaches Loki too, labelled by compose
    # project/service.
    containerlogs.enable = true;
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

  # Containers forward to these LAN-routed resolvers instead of inheriting the host's
  # resolv.conf, which lists only MagicDNS (100.100.100.100). Same two Technitium
  # servers either way — reaching them over the LAN just drops the dependency on
  # tailscaled being healthy. That dependency is a real boot race, not a theoretical
  # one: compose stacks start as soon as network-online.target is reached, which on a
  # cold boot is ~36s before tailscaled finishes connecting, and until then every
  # container lookup black-holes. It cost us Traefik's CrowdSec plugin (its startup
  # download timed out, which disables *all* plugins for the life of the process —
  # see the localPlugins note in compose/reverse-proxy/docker-compose.yaml) and
  # crowdsec itself, which exited fatally on "loki is not ready".
  #
  # Safe as a full replacement rather than a fallback for containers specifically:
  # these answer both public names and the internal zones, and the one thing they
  # can't serve — *.ts.net — is not resolved by anything in any compose stack.
  # Container-name lookups are unaffected; they're handled by Docker's own embedded
  # resolver at 127.0.0.11, which is what consults this list for everything else.
  virtualisation.docker.daemon.settings.dns = [
    "192.168.1.2"
    "192.168.1.3"
  ];

  # The host side of the same boot window. Appended rather than prepended
  # (name_servers_append, not name_servers) so MagicDNS stays first once tailscaled
  # is up: unlike the containers, the host does need *.ts.net to resolve — the bulk
  # NFS mount targets `hypervisor` by its tailnet name. Before tailscaled registers
  # its resolver these are all resolv.conf has, so early-boot lookups work rather
  # than hanging; afterwards they sit behind MagicDNS as a genuine fallback. Note
  # glibc only ever consults the first three nameservers (MAXNS), so once MagicDNS
  # has added both its v4 and v6 entries, .3 here is a spare that never gets queried
  # — it is listed for the pre-tailscaled window, where both are reachable.
  networking.resolvconf.extraConfig = ''
    name_servers_append="192.168.1.2 192.168.1.3"
  '';

  # Intel iGPU (QuickSync) passthrough for Jellyfin hardware transcoding — see the
  # passthrough plan for the hypervisor/libvirt side (PCI hostdev). Both userspace
  # VAAPI drivers are installed so this one config works unmodified on either the
  # current test hardware (Haswell HD 4600, needs the legacy i965 driver — iHD doesn't
  # support it) or the eventual production chip (i5-13400, covered by iHD); libva
  # auto-probes the right one for whatever GPU is actually present.
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-vaapi-driver
      libvdpau-va-gl
    ];
  };

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

  environment.systemPackages = [
    pkgs.btop
  ];

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
