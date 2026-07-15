{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.tailscale;
in
{
  options.tailscale = {
    autoconnect = {
      enable = lib.mkEnableOption "automatically run 'tailscale up'";
      authKeyPath = lib.mkOption {
        description = ''
          Path to auth key file, REQUIRED if autoconnect is enabled. Should be provided using a SOPS secret,
          e.g `tailscale.autoconnect.authKeyPath = config.sops.secrets.my-tailscale-auth-key.path;`
        '';
      };
      enableSSH = lib.mkEnableOption "allow SSH connection";
      tags = lib.mkOption {
        default = [ "server" ];
        description = "Tailscale tags to advertise when connecting. 'tag:' prefix is automatically added and should not be part of the value.";
      };
    };
    useRoutingFeatures = lib.mkOption {
      type = lib.types.enum [
        "client"
        "server"
        "both"
      ];
      default = "both";
      description = ''
        See: https://search.nixos.org/options?channel=25.11&show=services.tailscale.useRoutingFeatures&query=services.tailscale
      '';
    };
    advertiseExitNode = lib.mkEnableOption "advertise this node as an exit node";
    advertiseConnector = lib.mkEnableOption "advertise this node as a connector node (for subnet routing)";

    certificate = {
      enable = lib.mkEnableOption "issue and renew a Tailscale certificate and PKCS#12 bundle";
      domain = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "FQDN to request via tailscale cert.";
      };
      outputDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/tailscale-certs";
        description = "Directory where cert/key/pfx files are written.";
      };
      outputName = lib.mkOption {
        type = lib.types.str;
        default = "tailscale";
        description = "Base filename for generated files (<name>.crt, <name>.key, <name>.pfx).";
      };
      renewOnCalendar = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "systemd timer OnCalendar expression for certificate renewal.";
      };
      randomizedDelaySec = lib.mkOption {
        type = lib.types.str;
        default = "15m";
        description = "Randomized delay applied by the renewal timer.";
      };
      restartUnits = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Systemd units to restart after certificate refresh (e.g. technitium-dns-server.service).";
      };
    };
  };

  config = lib.mkMerge [
    {
      services.tailscale = lib.mkMerge [
        {
          enable = true;
          openFirewall = true;
          useRoutingFeatures = cfg.useRoutingFeatures;
        }
        (lib.mkIf cfg.advertiseExitNode {
          extraUpFlags = [ "--advertise-exit-node" ];
        })
        (lib.mkIf cfg.advertiseConnector {
          extraUpFlags = [ "--advertise-connector" ];
        })
        (lib.mkIf cfg.autoconnect.enable {
          authKeyFile = cfg.autoconnect.authKeyPath;
          extraUpFlags =
            [ ]
            ++ lib.lists.optional cfg.autoconnect.enableSSH "--ssh"
            ++
              lib.lists.optional (cfg.autoconnect.tags != [ ])
                # e.g. for function below: tags = [ "server" "dns" ] -> "--advertise-tags=tag:server,tag:dns"
                "--advertise-tags=${lib.strings.concatMapStringsSep "," (x: "tag:" + x) cfg.autoconnect.tags}";
        })
      ];
    }
    (lib.mkIf cfg.autoconnect.enable {
      # There are often DNS issue on first boot, so this helps a lot
      systemd.services.tailscaled-autoconnect = {
        serviceConfig = {
          Restart = "on-failure";
          RestartSec = "5s";
        };
        unitConfig = {
          # Disable restart rate-limiting so the service retries indefinitely
          StartLimitIntervalSec = 0;
        };
      };
    })
    (lib.mkIf cfg.certificate.enable {
      assertions = [
        {
          assertion = cfg.certificate.domain != "";
          message = "tailscale.certificate.domain must be set when tailscale.certificate.enable is true.";
        }
      ];

      systemd.services.tailscale-certificate-refresh = {
        description = "Refresh Tailscale certificate and PKCS#12 bundle";
        wants = [
          "network-online.target"
          "tailscaled.service"
        ];
        after = [
          "network-online.target"
          "tailscaled.service"
        ];
        serviceConfig = {
          Type = "oneshot";
        };
        script = ''
          set -euo pipefail

          mkdir -p "${cfg.certificate.outputDir}"
          chmod 0755 "${cfg.certificate.outputDir}"

          ${pkgs.tailscale}/bin/tailscale cert \
            --cert-file "${cfg.certificate.outputDir}/${cfg.certificate.outputName}.crt" \
            --key-file "${cfg.certificate.outputDir}/${cfg.certificate.outputName}.key" \
            "${cfg.certificate.domain}"

          ${pkgs.openssl}/bin/openssl pkcs12 -export \
            -inkey "${cfg.certificate.outputDir}/${cfg.certificate.outputName}.key" \
            -in "${cfg.certificate.outputDir}/${cfg.certificate.outputName}.crt" \
            -out "${cfg.certificate.outputDir}/${cfg.certificate.outputName}.pfx" \
            -passout pass:

          chmod 0644 "${cfg.certificate.outputDir}/${cfg.certificate.outputName}.pfx"
          chmod 0644 "${cfg.certificate.outputDir}/${cfg.certificate.outputName}.crt"

          ${lib.concatMapStringsSep "\n" (unit: "systemctl restart ${unit}") cfg.certificate.restartUnits}
        '';
        wantedBy = [ "multi-user.target" ];
      };

      systemd.timers.tailscale-certificate-refresh = {
        description = "Periodic Tailscale certificate refresh";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.certificate.renewOnCalendar;
          Persistent = true;
          RandomizedDelaySec = cfg.certificate.randomizedDelaySec;
        };
      };
    })
  ];
}
