{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.docker;
in
{
  options.docker = {
    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "snyssen" ];
    };
    networks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Docker bridge networks to pre-create before compose stacks start.";
    };
    cadvisor = {
      enable = lib.mkEnableOption "cAdvisor service for Docker monitoring.";
      listenAddress = lib.mkOption {
        type = lib.types.str;
        default = "0.0.0.0";
        description = "Address to listen on for cAdvisor.";
      };
      port = lib.mkOption {
        type = lib.types.int;
        default = 9200;
        description = "Port to expose cAdvisor on.";
      };
      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to open cAdvisor's port to the WAN. Not needed for containers on
          this host's own docker networks to reach it — see the docker-bridge
          firewall trust rule below — only for external scraping.
        '';
      };
    };
  };

  config = {
    virtualisation.docker = {
      enable = true;
      extraPackages = with pkgs; [
        docker-buildx
      ];
    };
    users.extraGroups.docker.members = cfg.users;
    systemd.services = lib.listToAttrs (
      map (network: {
        name = "docker-network-${network}";
        value = {
          description = "Ensure docker network '${network}' exists";
          after = [ "docker.service" ];
          requires = [ "docker.service" ];
          wantedBy = [ "multi-user.target" ];
          script = ''
            ${pkgs.docker}/bin/docker network create --driver bridge ${lib.escapeShellArg network} || true
          '';
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
        };
      }) cfg.networks
    );

    services.cadvisor = {
      enable = cfg.cadvisor.enable;
      listenAddress = cfg.cadvisor.listenAddress;
      port = cfg.cadvisor.port;
    };
    networking.firewall.allowedTCPPorts = lib.optionals (
      cfg.cadvisor.enable && cfg.cadvisor.openFirewall
    ) [ cfg.cadvisor.port ];

    # Let containers on this host's docker networks reach host-native services
    # (cadvisor, node-exporter, argunix, ...) without opening those services' ports
    # to the WAN. Docker's default address pool for auto-assigned bridge network
    # subnets stays within 172.16.0.0/12 (no --subnet is passed when creating the
    # networks above), so trusting that range for INPUT covers every docker network
    # on this host without needing to know their actual, non-deterministic subnets.
    # Inserted (not appended) so it's evaluated before nixos-fw's own reject rules.
    networking.firewall.extraCommands = lib.mkIf (cfg.networks != [ ]) ''
      iptables -I nixos-fw -s 172.16.0.0/12 -j nixos-fw-accept
    '';
    networking.firewall.extraStopCommands = lib.mkIf (cfg.networks != [ ]) ''
      iptables -D nixos-fw -s 172.16.0.0/12 -j nixos-fw-accept || true
    '';
  };
}
