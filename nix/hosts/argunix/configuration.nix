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
    flake.modules.nixos.traefik
    # flake.modules.nixos.crowdsec-firewall-bouncer # TODO: generate API key and enable
    flake.modules.nixos.prometheus-node-exporter
    flake.modules.nixos.grafana-alloy
    flake.modules.nixos.nfs-mounts

    flake.inputs.argunix.nixosModules.default
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
    "traefik/dynu-api-key" = {
      sopsFile = ./data/secrets.yaml;
      owner = "traefik";
      group = "traefik";
      mode = "0400";
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

  nfsMounts.enable = false;
  nfsMounts.mounts.bulk = {
    path = "/mnt/bulk";
    host = "hypervisor";
    remotePath = "/mnt/bulk/argunix";
    dependsOn.tailscale = true;
  };

  traefik = {
    letsencrypt = {
      challengeType = "dns";
      dnsChallenge = {
        apiKeyPath = config.sops.secrets."traefik/dynu-api-key".path;
      };
    };
  };
  services.traefik.dynamicConfigOptions = {
    http.routers.traefik-dashboard = {
      entryPoints = [ "websecure" ];
      rule = "Host(`argunix-ingress.snyssen.be`)";
      service = "api@internal";
    };
    http.routers.argunix = {
      entryPoints = [ "websecure" ];
      rule = "Host(`argunix.snyssen.be`)";
      service = "argunix";
    };
    http.services.argunix.loadBalancer.servers = [
      { url = "http://127.0.0.1:8080"; }
    ];
  };

  services.argunix = {
    enable = true;
    listen = "0.0.0.0:8080";
    settings = {
      external_url = "https://argunix.snyssen.be";
      builder_enrollment = {
        listen = "[::]:45678";
        token_path = config.sops.secrets."argunix/builder_enrollment/token".path;
      };
      forges.github = {
        kind = "github";
        web_url = "https://github.com";
        token_path = config.sops.secrets."argunix/forges/github/token".path;
        repos = {
          "snyssen/mother-of-all-infra" = { }; # default: build main + all PRs
          # "you/your-flake".watched_branches = [ "main" "release/*" ];
          "snyssen/webb-launcher" = { };
          "snyssen/personal-website" = { };
          "snyssen/nix-dev-env" = { };
        };
      };
      binary_caches = [
        {
          push_url = "s3://cache?endpoint=https://s3.snyssen.be&region=home";
          public_url = "https://cache.snyssen.be";
          public_key = "cache.snyssen.be:YbGmg46EztCHAFVaMztDfW/tuSuqVjLlYeG67R3VhGY=";
          signing_key_path = config.sops.secrets."argunix/caches/cache_snyssen_be/signing_key".path;
        }
      ];
      eval.timeout_seconds = 3600;
    };
  };
  networking.firewall.allowedTCPPorts = [ 45678 ];
  systemd.services.argunix = {
    environment = {
      RUST_LOG = "argunix=debug,argunix_daemon=debug,warn";
      RUST_BACKTRACE = "1";
    };
    serviceConfig.EnvironmentFile =
      config.sops.secrets."argunix/caches/cache_snyssen_be/s3_credentials".path;
  };

  # TODO: make this part automatically defined
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
  };
  system.name = "argunix";
  networking.hostName = "argunix";
  system.stateVersion = "25.11";
}
