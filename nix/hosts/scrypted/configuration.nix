{
  inputs,
  flake,
  config,
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

    flake.modules.nixos.sops
    flake.modules.nixos.cache
    flake.modules.nixos.grub
    flake.modules.nixos.kbd-layout
    flake.modules.nixos.shell
    flake.modules.nixos.locale
    flake.modules.nixos.nh

    flake.modules.nixos.tailscale
    flake.modules.nixos.nfs-mounts
    flake.modules.nixos.docker
    flake.modules.nixos.compose-stacks
  ];

  disko.layout = "single-btrfs-luks-virtiofs-key";

  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets = {
    "tailscale/authKey" = {
      sopsFile = ./data/secrets.yaml;
    };
    "users/snyssen/passwordHash" = {
      sopsFile = ./data/secrets.yaml;
      neededForUsers = true; # ensure this secret is available before creating the user account that depends on it
    };
  };

  networking = {
    useNetworkd = true;
    firewall.enable = true;
  };
  tailscale.autoconnect = {
    enable = true;
    authKeyPath = config.sops.secrets."tailscale/authKey".path;
    enableSSH = true;
  };

  # NFS mount for Scrypted bulk storage via systemd.mounts + systemd.automounts.
  # This provides lazy mounting and explicit Tailscale dependency support.
  nfsMounts.enable = true;
  nfsMounts.mounts = {
    bulk = {
      path = "/mnt/bulk";
      host = "hypervisor";
      remotePath = "/mnt/bulk/scrypted";
      dependsOn.tailscale = true;
      # options = [ "hard" ];
    };
  };

  # Create necessary directories for Scrypted NVR storage and set permissions.
  systemd.tmpfiles.rules = [
    "d /mnt/bulk/scrypted/nvr 0755 scrypted scrypted -"
  ];
  compose-stacks.stacks = {
    whoami = {
      composeFile = ./compose/whoami.yml;
    };
    scrypted = {
      composeFile = ./compose/scrypted/docker-compose.yaml;
    };
  };

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "no";
  };

  users = {
    mutableUsers = false;
    groups = {
      scrypted = { };
    };
    users = {
      scrypted = {
        isSystemUser = true;
        group = "scrypted";
      };
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

  # TODO: make this part automatically defined
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
  };
  system.name = "scrypted";
  networking.hostName = "scrypted";
  system.stateVersion = "25.11";
}
