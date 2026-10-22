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

    # cAdvisor resolves a cgroup to a container name/labels through its *docker*
    # factory, and that factory needs a containerd client. Both of its defaults are
    # wrong for NixOS, and getting either wrong fails the same silent way: the docker
    # factory never registers, only the raw/systemd factories do, and every series comes
    # out as a bare cgroup — `id="/system.slice/docker-<hash>.scope"` with no `name`,
    # no `image` and no container_label_*. Dashboards filtering `name=~".+"` then show
    # nothing at all. The failure is visible only in cadvisor's own log:
    #
    #   Registration of the docker container factory failed: unable to create containerd
    #   client: ... dial unix /run/containerd/containerd.sock: no such file or directory
    #
    # NixOS runs dockerd without `--containerd=`, so dockerd starts its own embedded
    # containerd rather than using a system-wide one. Its socket therefore lives under
    # dockerd's exec-root, and its containers live in dockerd's own namespace — both
    # confirmed from `dockerd --help`: `--exec-root` defaults to /var/run/docker and
    # `--containerd-namespace` to "moby". cAdvisor's defaults
    # (/run/containerd/containerd.sock, namespace "k8s.io") describe a standalone
    # containerd that does not exist here.
    #
    # Deliberately NOT setting --containerd-namespace. That flag belongs to cAdvisor's
    # *containerd* factory; the docker factory hardcodes the "moby" namespace and only
    # reads the endpoint above (container/docker/factory.go: `containerd.Client(
    # *containerd.ArgContainerdEndpoint, "moby")`). Both factories accept the same
    # cgroup name pattern, and cAdvisor asks them in registration order — which is
    # random, because InitializePlugins iterates a Go map. Leaving the namespace at its
    # "k8s.io" default is what breaks the tie deterministically: the containerd factory
    # looks for the container there, does not find it, and declines, so the docker
    # factory always handles it. Setting it to "moby" lets containerd win the coin flip
    # instead, and you get containerd's metadata — the container *id* as `name`, and
    # `container_label_com_docker_engine_bundle_path` in place of the compose labels.
    # This is also why it works on the legacy Ubuntu box, where the default happens to
    # be right for the same reason.
    #
    # --docker_only drops the per-systemd-unit cgroup series as well. Nothing queries
    # those, and they are a large share of the scrape on a host running this many units.
    services.cadvisor = {
      enable = cfg.cadvisor.enable;
      listenAddress = cfg.cadvisor.listenAddress;
      port = cfg.cadvisor.port;
      extraOptions = [
        "--containerd=/run/docker/containerd/containerd.sock"
        "--docker_only"
      ];
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
