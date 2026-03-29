{ config, lib, pkgs, ... }:
let
  cfg = config.docker-networks;

  # Build a single systemd oneshot service that creates a Docker bridge network
  # if it does not already exist.
  mkNetworkService = name: {
    description = "Create Docker bridge network '${name}'";
    # Require Docker daemon to be running.
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    # Run once at boot (or when the network is missing).
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.writeShellScript "create-docker-network-${name}" ''
        if ! ${config.virtualisation.docker.package}/bin/docker network inspect ${lib.escapeShellArg name} > /dev/null 2>&1; then
          ${config.virtualisation.docker.package}/bin/docker network create ${lib.escapeShellArg name}
        fi
      ''}";
    };
    wantedBy = [ "multi-user.target" ];
  };
in
{
  options.docker-networks = {
    networks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        List of Docker bridge network names to pre-create before any compose
        stack starts.  Each network is created as an idempotent systemd oneshot
        service named `docker-network-<name>.service`.

        Compose stacks that need one of these networks should add the
        corresponding unit to their `extraAfter` list via the `compose-stacks`
        module, e.g.:

        ```nix
        compose-stacks.stacks.myapp = {
          composeFile = ./compose/myapp/docker-compose.yaml;
          extraAfter  = [ "docker-network-web.service" ];
        };
        ```
      '';
      example = [
        "web"
        "db"
        "ldap"
        "monitoring"
      ];
    };
  };

  config = lib.mkIf (cfg.networks != [ ]) {
    systemd.services = lib.listToAttrs (
      map (name: {
        name = "docker-network-${name}";
        value = mkNetworkService name;
      }) cfg.networks
    );
  };
}
