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
      systemd.services.tailscale-autoconnect = {
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
  ];
}
