{
  lib,
  config,
  options,
  pkgs,
  ...
}:
let
  cfg = config.compose-stacks;
  dockerNetworkUnits =
    if options ? docker then
      map (network: "docker-network-${network}.service") config.docker.networks
    else
      [ ];
in
{
  options.compose-stacks = {
    stacks = lib.mkOption {
      default = { };
      description = "Docker Compose stacks to deploy and manage as systemd services. Each attribute key is used as the stack name.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            composeFile = lib.mkOption {
              type = lib.types.path;
              description = "Path to the docker-compose.yml file. The file is copied into the Nix store at evaluation time; a change in its content produces a new store path and triggers an automatic service restart on nixos-rebuild switch.";
            };
            environmentFile = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = "Optional path to a runtime environment file (e.g. a SOPS-managed secret) whose variables are injected into the service environment. Compose files should reference secrets as \${ENV_VAR} rather than embedding values directly.";
            };
            extraAfter = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Extra systemd units this service must start after (e.g. NFS mount units such as mnt-data.mount).";
            };
          };
        }
      );
    };
  };

  config = lib.mkIf (cfg.stacks != { }) {
    systemd.services = lib.mapAttrs' (
      name: stack:
      lib.nameValuePair "compose-${name}" {
        description = "Docker Compose stack: ${name}";
        after = [
          "docker.service"
          "network-online.target"
        ]
        ++ dockerNetworkUnits
        ++ stack.extraAfter;
        requires = [
          "docker.service"
          "network-online.target"
        ] ++ dockerNetworkUnits;
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.docker}/bin/docker compose --project-name ${lib.escapeShellArg name} -f ${lib.escapeShellArg "${stack.composeFile}"} up -d --remove-orphans";
          ExecStop = "${pkgs.docker}/bin/docker compose --project-name ${lib.escapeShellArg name} -f ${lib.escapeShellArg "${stack.composeFile}"} down";
        }
        // lib.optionalAttrs (stack.environmentFile != null) {
          EnvironmentFile = stack.environmentFile;
        };
      }
    ) cfg.stacks;

    # Convenience CLI wrapper per stack: `compose-<name> logs -f`, `compose-<name> down`, etc.
    # --project-name is pinned so commands work regardless of working directory.
    environment.systemPackages = lib.mapAttrsToList (
      name: stack:
      pkgs.writeShellScriptBin "compose-${name}" ''
        exec ${pkgs.docker}/bin/docker compose \
          --project-name ${lib.escapeShellArg name} \
          -f ${lib.escapeShellArg "${stack.composeFile}"} \
          "$@"
      ''
    ) cfg.stacks;
  };
}
