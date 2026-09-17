{
  lib,
  config,
  pkgs,
  ...
}:
let
  composeFile = "${./.}/docker-compose.yaml";

  cfg = config.reverseProxy;

  # One rendered file per contributed fragment, in a single Nix store directory.
  dynamicConfigSrc = pkgs.runCommand "reverse-proxy-dynamic-config" { } (
    lib.concatStrings (
      lib.mapAttrsToList (name: content: ''
        install -Dm444 ${pkgs.writeText "${name}.yml" content} $out/${name}.yml
      '') cfg.dynamicConfig
    )
  );
in
{
  # `reverseProxy.dynamicConfig` is declared here (this is the only host/stack that
  # needs it) rather than as a standalone nix/modules/nixos/*.nix module — but since
  # Nix's module system resolves option paths globally across every file imported into
  # this host, any other stack's own default.nix can still contribute a fragment via
  # `reverseProxy.dynamicConfig.<name> = "...";` without needing to import anything
  # extra, exactly like `argunix` does below for itself.
  options.reverseProxy = {
    dynamicConfig = lib.mkOption {
      type = lib.types.attrsOf lib.types.lines;
      default = { };
      description = ''
        Traefik dynamic (file provider) config fragments, keyed by name, one YAML
        document each. Fragments are rendered once into the Nix store, then copied
        (not symlinked) into `dynamicConfigDir` — a stable, ordinary directory that
        this stack's Traefik container bind-mounts and watches via its file provider.
        Copying instead of symlinking matters: Docker resolves a bind-mount source
        once at container creation, so a directory that gets re-symlinked on every
        activation (as `environment.etc` does) would leave the long-running Traefik
        container's mount stale after the first config change made after it started.
        Copying real file contents into a persistent directory means routing changes
        take effect via Traefik's own hot-reload, with no restart of the
        reverse-proxy container needed.
      '';
    };

    dynamicConfigDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/reverse-proxy/dynamic";
      readOnly = true;
      description = "Stable host directory that this stack's Traefik file provider watches.";
    };
  };

  config = {
    systemd.tmpfiles.rules = [
      "d /var/lib/app-data/reverse-proxy/certs 0700 root root -"
    ]
    ++ lib.optional (cfg.dynamicConfig != { }) "d ${cfg.dynamicConfigDir} 0755 root root -";

    sops.secrets = {
      "compose-stacks/reverse-proxy/acme/email" = {
        sopsFile = ../../data/secrets.yaml;
      };
      "compose-stacks/reverse-proxy/acme/ca_server" = {
        sopsFile = ../../data/secrets.yaml;
      };
      "compose-stacks/reverse-proxy/acme/dynu_api_key" = {
        sopsFile = ../../data/secrets.yaml;
        restartUnits = [ "compose-reverse-proxy.service" ];
      };
      "compose-stacks/reverse-proxy/acme/porkbun_api_key" = {
        sopsFile = ../../data/secrets.yaml;
        restartUnits = [ "compose-reverse-proxy.service" ];
      };
      "compose-stacks/reverse-proxy/acme/porkbun_secret_api_key" = {
        sopsFile = ../../data/secrets.yaml;
        restartUnits = [ "compose-reverse-proxy.service" ];
      };
    };

    sops.templates."compose-reverse-proxy.env".content = ''
      MAIN_DOMAIN=${config.domains.main}
      ACME_EMAIL=${config.sops.placeholder."compose-stacks/reverse-proxy/acme/email"}
      ACME_CA_SERVER=${config.sops.placeholder."compose-stacks/reverse-proxy/acme/ca_server"}
      DYNU_API_KEY=${config.sops.placeholder."compose-stacks/reverse-proxy/acme/dynu_api_key"}
      PORKBUN_API_KEY=${config.sops.placeholder."compose-stacks/reverse-proxy/acme/porkbun_api_key"}
      PORKBUN_SECRET_API_KEY=${
        config.sops.placeholder."compose-stacks/reverse-proxy/acme/porkbun_secret_api_key"
      }
    '';

    # argunix is a native process (not a container), reachable from inside the Traefik
    # container via host.docker.internal. Its direct debug port (8080) is retired here —
    # it's only reached through Traefik now, over its own hostname with TLS.
    # The dashboard has no Authelia protection yet (the `auth` stack doesn't exist yet) —
    # matching the exposure the existing native argunix-only Traefik already has today,
    # not a new gap. Revisit once `auth` is deployed.
    reverseProxy.dynamicConfig.argunix =
      let
        # argunix_domain = config.domains.main;
        argunix_domain = "snyssen.be"; # keep this separate as of now because this is the only live application amidst a test VM.
      in
      ''
        http:
          routers:
            argunix:
              rule: "Host(`argunix.${argunix_domain}`)"
              entryPoints:
                - websecure
              service: argunix
              tls:
                certResolver: le_main
            traefik-dashboard:
              rule: "Host(`argunix-ingress.${argunix_domain}`) || Host(`routing.${config.domains.main}`)"
              entryPoints:
                - websecure
              service: api@internal
              middlewares:
                - traefik-compress
              tls:
                certResolver: le_main
          services:
            argunix:
              loadBalancer:
                servers:
                  - url: "http://host.docker.internal:8080"
          middlewares:
            traefik-compress:
              compress: {}
      '';

    compose-stacks.stacks.reverse-proxy = {
      inherit composeFile;
      environmentFile = config.sops.templates."compose-reverse-proxy.env".path;
      dockerNetworks = [ "web" ];
      extraAfter = [ "reverse-proxy-dynamic-config.service" ];
    };

    systemd.services.reverse-proxy-dynamic-config = lib.mkIf (cfg.dynamicConfig != { }) {
      description = "Sync reverse-proxy's Traefik dynamic config into a stable path";
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [ dynamicConfigSrc ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "sync-reverse-proxy-dynamic-config" ''
          set -euo pipefail
          rm -f ${cfg.dynamicConfigDir}/*.yml
          cp -f ${dynamicConfigSrc}/*.yml ${cfg.dynamicConfigDir}/
        '';
      };
    };
  };
}
