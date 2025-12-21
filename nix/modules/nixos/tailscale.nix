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
    };
  };

  config = {
    services.tailscale = {
      enable = true;
      openFirewall = true;
      authKeyFile = lib.mkIf cfg.autoconnect.enable cfg.autoconnect.authKeyPath;
      extraUpFlags = lib.mkIf (cfg.autoconnect.enable && cfg.autoconnect.enableSSH) [ "--ssh" ];
    };
  };
}
