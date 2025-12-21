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
  };

  config = {
    services.tailscale = lib.mkMerge [
      {
        enable = true;
        openFirewall = true;
      }
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
  };
}
