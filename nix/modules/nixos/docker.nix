{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.docker;
  cadvisorCfg = cfg.cadvisor;
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
      enable = lib.mkEnableOption "cAdvisor container metrics exporter";
      port = lib.mkOption {
        type = lib.types.port;
        default = 8080;
        description = "Host port to expose cAdvisor metrics on.";
      };
      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to open the cAdvisor metrics port in the firewall.";
      };
    };
  };

  config = lib.mkMerge [
    {
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
    }
    (lib.mkIf cadvisorCfg.enable {
      virtualisation.oci-containers.backend = "docker";
      virtualisation.oci-containers.containers.cadvisor = {
        image = "gcr.io/cadvisor/cadvisor:v0.55.1@sha256:3de2bd5203120b866d74a9b283b2ffb8ec382fbf9dc321814700c6ea6f44ec57";
        ports = [ "${toString cadvisorCfg.port}:8080" ];
        volumes = [
          "/:/rootfs:ro"
          "/var/run/docker.sock:/var/run/docker.sock:ro"
          "/sys:/sys:ro"
          "/var/lib/docker:/var/lib/docker:ro"
        ];
      };
      networking.firewall.allowedTCPPorts = lib.optionals cadvisorCfg.openFirewall [ cadvisorCfg.port ];
    })
  ];
}
