{
  lib,
  config,
  ...
}:
# A thin layer over services.syncthing: the settings every host here shares (devices and
# folders fully managed from Nix, the device list from nix/data/syncthing.nix), plus the
# few things a host may need to change. Anything else can still be set on
# services.syncthing directly.
let
  cfg = config.syncthing;

  # Every device but this host itself: the default for a folder's devices.
  otherDevices = lib.filter (name: name != cfg.deviceName) (lib.attrNames cfg.devices);
in
{
  options.syncthing = {
    username = lib.mkOption {
      default = "snyssen";
      type = lib.types.str;
    };
    deviceName = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      defaultText = lib.literalExpression "config.networking.hostName";
      description = ''
        This host's own name in `devices`. Only used to leave it out of the folders'
        default device list.
      '';
    };
    dataDir = lib.mkOption {
      default = "/home/${cfg.username}/Documents";
      type = lib.types.str;
    };
    configDir = lib.mkOption {
      default = "/home/${cfg.username}/Documents/.config/syncthing";
      type = lib.types.str;
    };
    identity.sopsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = lib.literalExpression "./data/secrets.yaml";
      description = ''
        sops file holding this device's certificate and key, as `syncthing/cert` and
        `syncthing/key` (the PEM contents of cert.pem and key.pem). A device's ID is
        derived from its certificate, so this keeps it fixed across rebuilds and lets it
        be known before the first deploy. When null, Syncthing keeps the identity it
        generated itself in configDir.
      '';
    };
    gui.address = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:8384";
      description = "Address the web GUI listens on.";
    };
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open the sync port (22000, TCP and QUIC) and the local discovery port
        (21027/udp) on every interface. Not the GUI.
      '';
    };
    openTailnetFirewall = lib.mkOption {
      type = lib.types.bool;
      default = config.services.tailscale.enable;
      defaultText = lib.literalExpression "config.services.tailscale.enable";
      description = ''
        Open the sync port (22000, TCP and QUIC) on the Tailscale interface only, so
        peers can connect to this device directly over the tailnet — not only the other
        way around, or through a public relay — while it stays closed on whatever other
        network it joins. Peers find it there through its tailnet address in
        nix/data/syncthing.nix.
      '';
    };
    devices = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            id = lib.mkOption {
              type = lib.types.str;
              example = "XXX-XXX-XXX";
            };
            # For a device that discovery alone may not find, e.g. one peers should
            # reach over the tailnet. Left out of the generated settings when unset,
            # which means `dynamic` (discovery and relays) to Syncthing.
            addresses = lib.mkOption {
              type = lib.types.nullOr (lib.types.listOf lib.types.str);
              default = null;
              example = [
                "tcp://host:22000"
                "dynamic"
              ];
            };
          };
        }
      );
      default = (import ../../data/syncthing.nix).devices;
      defaultText = lib.literalExpression "(import nix/data/syncthing.nix).devices";
    };
    folders = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            # What devices match folders by. Syncthing (and services.syncthing) uses the
            # attribute name when unset, so only needed for a folder created elsewhere
            # with a generated ID. Left out of the generated settings when unset.
            id = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "h5q7k-uenv3";
            };
            path = lib.mkOption {
              type = lib.types.str;
              example = "/mnt/folder-to-sync";
            };
            devices = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = otherDevices;
              defaultText = lib.literalMD "every device in `devices` except `deviceName`";
              example = ''
                [ "device-one", "device-two" ]
              '';
            };
          };
        }
      );
      default = { };
    };
  };

  config = lib.mkMerge [
    {
      services.syncthing = {
        enable = true;
        user = "${cfg.username}";
        inherit (cfg) dataDir configDir;
        guiAddress = cfg.gui.address;
        openDefaultPorts = cfg.openFirewall;
        overrideDevices = true;
        overrideFolders = true;
        settings = {
          devices = lib.mapAttrs (_: lib.filterAttrs (_: v: v != null)) cfg.devices;
          folders = lib.mapAttrs (_: lib.filterAttrs (_: v: v != null)) cfg.folders;
        };
      };
    }
    (lib.mkIf cfg.openTailnetFirewall {
      networking.firewall.interfaces.${config.services.tailscale.interfaceName} = {
        allowedTCPPorts = [ 22000 ];
        allowedUDPPorts = [ 22000 ];
      };
    })
    (lib.mkIf (cfg.identity.sopsFile != null) {
      sops.secrets = {
        "syncthing/cert" = {
          inherit (cfg.identity) sopsFile;
          owner = cfg.username;
        };
        "syncthing/key" = {
          inherit (cfg.identity) sopsFile;
          owner = cfg.username;
        };
      };
      services.syncthing = {
        cert = config.sops.secrets."syncthing/cert".path;
        key = config.sops.secrets."syncthing/key".path;
      };
    })
  ];
}
