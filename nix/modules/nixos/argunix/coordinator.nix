{
  config,
  lib,
  pkgs,
  flake,
  ...
}:
let
  cfg = config.argunix.coordinator;
in
{
  imports = [
    flake.inputs.argunix.nixosModules.default
  ];

  options = {
    argunix.coordinator = {
      enable = lib.mkEnableOption "Argunix coordinator configuration";
      api = {
        listenIp = lib.mkOption {
          type = lib.types.str;
          default = "0.0.0.0";
        };
        listenPort = lib.mkOption {
          type = lib.types.int;
          default = 8080;
        };
        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default =
            config.argunix.coordinator.api.listenIp == "0.0.0.0"
            || config.argunix.coordinator.api.listenIp == "[::]";
        };
        externalUrl = lib.mkOption {
          type = lib.types.str;
          default = "https://argunix.snyssen.be";
        };
      };
      builderEnrollment = {
        listenIp = lib.mkOption {
          type = lib.types.str;
          default = "0.0.0.0";
        };
        listenPort = lib.mkOption {
          type = lib.types.int;
          default = 45678;
        };
        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default =
            config.argunix.coordinator.builderEnrollment.listenIp == "0.0.0.0"
            || config.argunix.coordinator.builderEnrollment.listenIp == "[::]";
        };
        tokenFile = lib.mkOption {
          type = lib.types.path;
          default = "/run/secrets/argunix/builder_enrollment/token";
        };
      };
      forges = {
        github = {
          enable = lib.mkEnableOption "GitHub integration" // {
            default = true;
          };
          tokenFile = lib.mkOption {
            type = lib.types.path;
            default = "/run/secrets/argunix/forges/github/token";
          };
          repos = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  pr_allowlist = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ "renovate[bot]" ];
                  };
                  watched_branches = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ "main" ];
                  };
                };
              }
            );
          };
        };
      };
      caches = {
        cache_snyssen_be = {
          enable = lib.mkEnableOption "Self-hosted S3 cache" // {
            default = true;
          };
          push_url = lib.mkOption {
            type = lib.types.str;
            default = "s3://cache?endpoint=https://s3.snyssen.be&region=home";
          };
          public_url = lib.mkOption {
            type = lib.types.str;
            default = "https://cache.snyssen.be";
          };
          public_key = lib.mkOption {
            type = lib.types.str;
            default = "cache.snyssen.be:YbGmg46EztCHAFVaMztDfW/tuSuqVjLlYeG67R3VhGY=";
          };
          signing_key_file = lib.mkOption {
            type = lib.types.path;
            default = "/run/secrets/argunix/caches/cache_snyssen_be/signing_key";
          };
        };
      };
      environmentFile = {
        enable =
          lib.mkEnableOption "Environment file for Argunix service, mainly used to provide s3 credentials"
          // {
            default = true;
          };
        path = lib.mkOption {
          type = lib.types.path;
          default = "/run/secrets/argunix/caches/cache_snyssen_be/s3_credentials";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.argunix = {
      enable = true;
      listen = "${cfg.api.listenIp}:${toString cfg.api.listenPort}";
      settings = {
        external_url = cfg.api.externalUrl;
        builder_enrollment = {
          listen = "${cfg.builderEnrollment.listenIp}:${toString cfg.builderEnrollment.listenPort}";
          token_path = cfg.builderEnrollment.tokenFile;
        };
        forges.github = lib.mkIf cfg.forges.github.enable {
          kind = "github";
          web_url = "https://github.com";
          token_path = cfg.forges.github.tokenFile;
          repos = cfg.forges.github.repos;
        };
        binary_caches =
          [ ]
          ++ lib.lists.optional cfg.caches.cache_snyssen_be.enable {
            push_url = cfg.caches.cache_snyssen_be.push_url;
            public_url = cfg.caches.cache_snyssen_be.public_url;
            public_key = cfg.caches.cache_snyssen_be.public_key;
            signing_key_path = cfg.caches.cache_snyssen_be.signing_key_file;
          };
        eval.timeout_seconds = 900;
      };
    };

    networking.firewall.allowedTCPPorts =
      [ ]
      ++ lib.lists.optional cfg.api.openFirewall cfg.api.listenPort
      ++ lib.lists.optional cfg.builderEnrollment.openFirewall cfg.builderEnrollment.listenPort;

    systemd.services.argunix = {
      environment = {
        RUST_LOG = "argunix=debug,argunix_daemon=debug,warn";
        RUST_BACKTRACE = "1";
      };
      serviceConfig.EnvironmentFile = lib.mkIf cfg.caches.cache_snyssen_be.enable cfg.environmentFile.path;
    };
  };
}
