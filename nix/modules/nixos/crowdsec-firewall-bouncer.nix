{ config, lib, ... }:
let
  cfg = config.crowdsec-firewall-bouncer;
in
{
  options.crowdsec-firewall-bouncer = {
    apiUrl = lib.mkOption {
      default = "https://crowdsec.snyssen.be";
    };
    apiKeyPath = lib.mkOption {
      description = ''
        Path to API key file. Should be provided using a SOPS secret,
        e.g `crowdsec-firewall-bouncer.apiKeyPath = config.sops.secrets.my-crowdsec-api-key.path;`
      '';
    };
  };

  config = {
    services.crowdsec-firewall-bouncer = {
      enable = true;
      registerBouncer.enable = false;
      settings.api_url = cfg.apiUrl;
      secrets.apiKeyPath = cfg.apiKeyPath;
    };
  };
}
