{ config, pkgs, ... }:
let
  composeFile = "${./.}/docker-compose.yaml";
in
{
  sops.secrets = {
    "compose-stacks/recipes/secret_key" = {
      sopsFile = ../../data/recipes.yaml;
    };
    "compose-stacks/recipes/oidc/client_id" = {
      sopsFile = ../../data/recipes.yaml;
    };
    "compose-stacks/recipes/oidc/client_secret" = {
      sopsFile = ../../data/recipes.yaml;
    };
    # Hashed, for Authelia's own client config — same plaintext/hash split as every
    # other OIDC client on this host.
    "compose-stacks/recipes/oidc/client_secret_hash" = {
      sopsFile = ../../data/recipes.yaml;
    };
  };

  # Same split as paperless: the secret key and the OIDC client are carried over
  # unchanged from the legacy vault (the key signs sessions and tokens, and the client
  # id is what the imported socialaccount rows point at), while the database password
  # is the central cluster's own, which provisions the `recipes` role from it.
  sops.templates."compose-recipes.env".content = ''
    RECIPES_SECRET_KEY=${config.sops.placeholder."compose-stacks/recipes/secret_key"}
    RECIPES_HOST=recipes.${config.domains.main}
    RECIPES_OIDC_CLIENT_ID=${config.sops.placeholder."compose-stacks/recipes/oidc/client_id"}
    RECIPES_OIDC_CLIENT_SECRET=${config.sops.placeholder."compose-stacks/recipes/oidc/client_secret"}
    RECIPES_OIDC_SERVER_URL=https://auth.${config.domains.main}/.well-known/openid-configuration
    RECIPES_DB_PASSWORD=${config.sops.placeholder."compose-stacks/databases/postgres/passwords/recipes"}
  '';

  # Authelia-gated the same way as paperless, and for the same reason: the middleware
  # exists only so the access_control rules in auth/authelia-configuration.nix can keep
  # Django's /admin to sysadmins, then bypass the rest of the host for Tandoor's own
  # OIDC login. Port 80 is the image's bundled nginx, which serves static and media
  # files itself and proxies the rest to gunicorn on 8080.
  reverseProxy.dynamicConfig.recipes = ''
    http:
      routers:
        recipes:
          rule: "Host(`recipes.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: recipes
          middlewares:
            - authelia
          tls:
            certResolver: le_main
      services:
        recipes:
          loadBalancer:
            servers:
              - url: "http://recipes:80"
  '';

  compose-stacks.stacks.recipes = {
    restartTriggers = [
      ../../data/recipes.yaml
      ../../data/databases.yaml
      config.sops.templates."compose-recipes.env".content
    ];
    inherit composeFile;
    environmentFile = config.sops.templates."compose-recipes.env".path;
    dockerNetworks = [
      "web"
      "db"
    ];
    extraAfter = [
      "mnt-bulk.mount"
      "reverse-proxy-dynamic-config.service"
      "recipes-storage-dirs.service"
    ];
  };

  # Same shape as paperless-storage-dirs: /mnt/bulk subpaths can't go through ordinary
  # tmpfiles rules, which run before the NFS mount is up. root-owned because Tandoor
  # runs as root in its container.
  systemd.services.recipes-storage-dirs = {
    description = "Create /mnt/bulk directories the recipes stack expects";
    after = [ "mnt-bulk.mount" ];
    requires = [ "mnt-bulk.mount" ];
    before = [ "compose-recipes.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "recipes-storage-dirs" ''
        set -euo pipefail
        install -d -m 0755 -o 0 -g 0 /mnt/bulk/recipes/mediafiles
      '';
    };
  };
}
