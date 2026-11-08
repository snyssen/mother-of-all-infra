{ config, pkgs, ... }:
let
  composeFile = "${./.}/docker-compose.yaml";
  sopsFile = ../../data/garage.yaml;
  secret = name: config.sops.placeholder."compose-stacks/garage/${name}";
in
{
  # Garage is only the Nix binary cache (s3.<domain> to push, cache.<domain> to
  # substitute), so nothing here is backed up or imported, as on prod: every object can
  # be rebuilt, and the cache refills from the next pushes.
  #
  # Until cutover nothing uses this instance: every consumer names snyssen.be
  # (modules/nixos/cache.nix, argunix's coordinator, nix.just), so it runs beside prod's
  # untouched.
  systemd.tmpfiles.rules = [
    "d /var/lib/app-data/garage/meta 0700 0 0 -"
  ];

  # All carried over unchanged from the legacy vault. The default key above all: it is
  # the key pushers already hold — argunix's s3_credentials in data/common.yaml carries
  # this same pair — so keeping it keeps them working.
  sops.secrets = {
    "compose-stacks/garage/rpc_secret".sopsFile = sopsFile;
    "compose-stacks/garage/admin_token".sopsFile = sopsFile;
    "compose-stacks/garage/metrics_token".sopsFile = sopsFile;
    "compose-stacks/garage/default_key/access_key_id".sopsFile = sopsFile;
    "compose-stacks/garage/default_key/secret_key".sopsFile = sopsFile;
  };

  # Prod's garage.toml, with the domain following domains.main. Root-only is enough:
  # both images run as root.
  sops.templates."garage.toml".content = ''
    metadata_dir = "/var/lib/garage/meta"
    data_dir = "/var/lib/garage/data"
    db_engine = "sqlite"

    replication_factor = 1

    rpc_bind_addr = "[::]:3901"
    rpc_public_addr = "garage:3901"
    rpc_secret = "${secret "rpc_secret"}"

    bootstrap_peers = []

    [s3_api]
    s3_region = "home"
    api_bind_addr = "[::]:3900"
    root_domain = ".s3.${config.domains.main}"

    [s3_web]
    bind_addr = "[::]:3902"
    root_domain = ".${config.domains.main}"

    [admin]
    api_bind_addr = "[::]:3903"
    admin_token = "${secret "admin_token"}"
    metrics_token = "${secret "metrics_token"}"
  '';

  sops.templates."compose-garage.env".content = ''
    GARAGE_CONFIG_PATH=${config.sops.templates."garage.toml".path}
    GARAGE_DEFAULT_ACCESS_KEY=${secret "default_key/access_key_id"}
    GARAGE_DEFAULT_SECRET_KEY=${secret "default_key/secret_key"}
  '';

  # The S3 API and the `cache` bucket's website endpoint are open, as on prod: S3
  # requests are signed with the access key, and the cache is meant to be read
  # anonymously by every substituter. Only the admin UI is Authelia-gated (sysadmins,
  # see auth/authelia-configuration.nix). None of them goes through the ingress host,
  # same as prod: reachable over LAN and tailnet only.
  reverseProxy.dynamicConfig.garage = ''
    http:
      routers:
        garage-s3-api:
          rule: "Host(`s3.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: garage-s3-api
          tls:
            certResolver: le_main
        garage-s3-web:
          rule: "Host(`cache.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: garage-s3-web
          tls:
            certResolver: le_main
        garage-ui:
          rule: "Host(`garage.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: garage-ui
          middlewares:
            - authelia
            - traefik-compress
          tls:
            certResolver: le_main
      services:
        garage-s3-api:
          loadBalancer:
            servers:
              - url: "http://garage:3900"
        garage-s3-web:
          loadBalancer:
            servers:
              - url: "http://garage:3902"
        garage-ui:
          loadBalancer:
            servers:
              - url: "http://garage-ui:3909"
  '';

  compose-stacks.stacks.garage = {
    restartTriggers = [
      sopsFile
      config.sops.templates."garage.toml".content
      config.sops.templates."compose-garage.env".content
    ];
    inherit composeFile;
    environmentFile = config.sops.templates."compose-garage.env".path;
    dockerNetworks = [ "web" ];
    extraAfter = [
      "mnt-bulk.mount"
      "reverse-proxy-dynamic-config.service"
      "garage-storage-dirs.service"
    ];
  };

  # Same shape as the other stacks' storage-dirs units: /mnt/bulk subpaths can't go
  # through ordinary tmpfiles rules, which run before the NFS mount is up.
  systemd.services.garage-storage-dirs = {
    description = "Create /mnt/bulk directories the garage stack expects";
    after = [ "mnt-bulk.mount" ];
    requires = [ "mnt-bulk.mount" ];
    before = [ "compose-garage.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "garage-storage-dirs" ''
        set -euo pipefail
        install -d -m 0700 -o 0 -g 0 /mnt/bulk/garage/data
      '';
    };
  };

  # Serves the `cache` bucket on cache.<domain>, which is how substituters read it.
  # --default-bucket creates the bucket but leaves website access off, and nothing in
  # the legacy role turns it on, so on prod it was done by hand. It lives in Garage's
  # metadata, which nothing backs up — so it is set here instead, on every start of the
  # stack. Idempotent. Retried because Garage takes
  # a moment to accept CLI calls after its container starts.
  systemd.services.garage-website = {
    description = "Enable website access on Garage's cache bucket";
    after = [ "compose-garage.service" ];
    requires = [ "compose-garage.service" ];
    partOf = [ "compose-garage.service" ];
    wantedBy = [ "compose-garage.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "garage-website" ''
        set -euo pipefail
        for _ in $(seq 1 30); do
          if ${pkgs.docker}/bin/docker compose --project-name garage -f ${composeFile} \
            exec -T garage /garage bucket website --allow cache; then
            exit 0
          fi
          sleep 2
        done
        echo "could not enable website access on the cache bucket" >&2
        exit 1
      '';
    };
  };
}
