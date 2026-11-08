{ config, pkgs, ... }:
let
  composeFile = "${./.}/docker-compose.yaml";

  # Non-secret, so a plain store file rather than a sops template. One `KEY=value` per
  # line in compose's `raw` env-file format: no quoting, no escapes, no interpolation —
  # which is the point, since the JSON carries both kinds of quote.
  contentEnvFile = pkgs.writeText "dashboard-content.env" ''
    SHORTCUTS=${builtins.toJSON (import ./shortcuts.nix)}
    SEARCH_URL_BASE=https://kagi.com/search?q=
  '';
in
{
  sops.secrets."compose-stacks/dashboard/openweather/api_key" = {
    sopsFile = ../../data/dashboard.yaml;
  };

  # Carried over unchanged from the legacy vault (vault_dashboard__open_weather_key).
  sops.templates."compose-dashboard.env".content = ''
    OPENWEATHER_API_KEY=${config.sops.placeholder."compose-stacks/dashboard/openweather/api_key"}
    DASHBOARD_CONTENT_ENV_FILE=${contentEnvFile}
  '';

  # No Authelia, same as prod: the page is a list of links and holds nothing itself.
  reverseProxy.dynamicConfig.dashboard = ''
    http:
      routers:
        dashboard:
          rule: "Host(`dash.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: dashboard
          middlewares:
            - traefik-compress
          tls:
            certResolver: le_main
      services:
        dashboard:
          loadBalancer:
            servers:
              - url: "http://dashboard:8080"
  '';

  compose-stacks.stacks.dashboard = {
    restartTriggers = [
      ../../data/dashboard.yaml
      # Includes contentEnvFile's store path, so a shortcut change restarts the stack.
      config.sops.templates."compose-dashboard.env".content
    ];
    inherit composeFile;
    environmentFile = config.sops.templates."compose-dashboard.env".path;
    dockerNetworks = [ "web" ];
    extraAfter = [ "reverse-proxy-dynamic-config.service" ];
  };
}
