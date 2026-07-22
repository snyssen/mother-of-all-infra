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
        default = true;
        description = "Whether to open the firewall for cAdvisor.";
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
  };
}
