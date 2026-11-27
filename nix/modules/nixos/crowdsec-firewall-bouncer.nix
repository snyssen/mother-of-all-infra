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
    # The bouncer exits on any LAPI error ("bouncer stream halted"), including the 403s
    # it gets while CrowdSec is restarting and has not yet registered the bouncer keys,
    # and the upstream unit never restarts it. Retry, slowly enough to stay clear of
    # the start rate limit while CrowdSec comes back.
    systemd.services.crowdsec-firewall-bouncer.serviceConfig = {
      Restart = "on-failure";
      RestartSec = "30s";
    };
  };
}
