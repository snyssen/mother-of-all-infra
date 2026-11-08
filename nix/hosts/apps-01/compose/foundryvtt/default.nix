{ config, ... }:
let
  hostname = "dnd.${config.domains.main}";
in
{
  # The image runs as `node` (uid 1000) with no root step to fix ownership, so the
  # directory has to be writable by that uid from the start. On prod it was the deploy
  # user's, which happened to be 1000 too.
  systemd.tmpfiles.rules = [
    "d /var/lib/app-data/foundryvtt 0775 1000 1000 -"
  ];

  # All three carried over unchanged from the legacy vault. The account is the
  # foundryvtt.com login the entrypoint uses to download the release; the admin key
  # guards Foundry's setup screen.
  sops.secrets = {
    "compose-stacks/foundryvtt/account/username" = {
      sopsFile = ../../data/foundryvtt.yaml;
    };
    "compose-stacks/foundryvtt/account/password" = {
      sopsFile = ../../data/foundryvtt.yaml;
    };
    "compose-stacks/foundryvtt/admin_key" = {
      sopsFile = ../../data/foundryvtt.yaml;
    };
  };

  sops.templates."compose-foundryvtt.env".content = ''
    FOUNDRY_USERNAME=${config.sops.placeholder."compose-stacks/foundryvtt/account/username"}
    FOUNDRY_PASSWORD=${config.sops.placeholder."compose-stacks/foundryvtt/account/password"}
    FOUNDRY_ADMIN_KEY=${config.sops.placeholder."compose-stacks/foundryvtt/admin_key"}
    FOUNDRY_HOSTNAME=${hostname}
    FOUNDRY_LOCAL_HOSTNAME=${hostname}
  '';

  # Behind forwardAuth, as on prod: the access_control rule in
  # auth/authelia-configuration.nix lets in `foundry_player` with one factor.
  reverseProxy.dynamicConfig.foundryvtt = ''
    http:
      routers:
        foundryvtt:
          rule: "Host(`${hostname}`)"
          entryPoints:
            - websecure
          service: foundryvtt
          middlewares:
            - authelia
          tls:
            certResolver: le_main
      services:
        foundryvtt:
          loadBalancer:
            servers:
              - url: "http://foundryvtt:30000"
  '';

  compose-stacks.stacks.foundryvtt = {
    restartTriggers = [
      ../../data/foundryvtt.yaml
      config.sops.templates."compose-foundryvtt.env".content
    ];
    composeFile = "${./.}/docker-compose.yaml";
    environmentFile = config.sops.templates."compose-foundryvtt.env".path;
    dockerNetworks = [ "web" ];
    extraAfter = [ "reverse-proxy-dynamic-config.service" ];
  };
}
