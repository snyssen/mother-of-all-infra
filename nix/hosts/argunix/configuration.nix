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
    "argunix/github-token" = {
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

  tailscale.serve = {
    enable = true;
    httpsPort = 443;
    target = "http://127.0.0.1:8080";
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

  services.argunix = {
    enable = true;
    listen = "127.0.0.1:8080";
    settings = {
      external_url = "https://argunix.taild023c5.ts.net";
      forges.github = {
        kind = "github";
        web_url = "https://github.com";
        token_path = config.sops.secrets."argunix/github-token".path;
        repos = {
          "snyssen/mother-of-all-infra" = { }; # default: build main + all PRs
          # "you/your-flake".watched_branches = [ "main" "release/*" ];
        };
      };
    };
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
