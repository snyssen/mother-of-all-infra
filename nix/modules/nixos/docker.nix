# TODO: add support for cadvisor
{
  lib,
  config,
  options,
  pkgs,
  ...
}:
let
  cfg = config.docker;
  composeStackServiceUnits =
    if options ? compose-stacks then
      map (name: "compose-${name}.service") (lib.attrNames config.compose-stacks.stacks)
    else
      [ ];
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
          before = composeStackServiceUnits;
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
  };
}
