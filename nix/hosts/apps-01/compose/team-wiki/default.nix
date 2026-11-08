{ config, ... }:
let
  composeFile = "${./.}/docker-compose.yaml";
in
{
  # The OIDC client, carried over unchanged from the legacy vault. Only Authelia reads
  # these (auth/authelia-configuration.nix): Wiki.js keeps its side of the client in its
  # own database, so the plaintext secret is kept here for reference and never rendered.
  sops.secrets = {
    "compose-stacks/team-wiki/oidc/client_id" = {
      sopsFile = ../../data/team-wiki.yaml;
    };
    "compose-stacks/team-wiki/oidc/client_secret_hash" = {
      sopsFile = ../../data/team-wiki.yaml;
    };
  };

  sops.templates."compose-team-wiki.env".content = ''
    TEAM_WIKI_DB_PASSWORD=${
      config.sops.placeholder."compose-stacks/databases/postgres/passwords/team_wiki"
    }
  '';

  # On the bare team domain, as on prod, with no forwardAuth: Wiki.js handles its own
  # permissions, and logs members in over OIDC through Authelia's team-domain portal.
  reverseProxy.dynamicConfig.team-wiki = ''
    http:
      routers:
        team-wiki:
          rule: "Host(`${config.domains.team}`)"
          entryPoints:
            - websecure
          service: team-wiki
          tls:
            certResolver: le_team
      services:
        team-wiki:
          loadBalancer:
            servers:
              - url: "http://team-wiki:3000"
  '';

  compose-stacks.stacks.team-wiki = {
    restartTriggers = [
      ../../data/databases.yaml
      config.sops.templates."compose-team-wiki.env".content
    ];
    inherit composeFile;
    environmentFile = config.sops.templates."compose-team-wiki.env".path;
    dockerNetworks = [
      "web"
      "db"
      "ldap"
    ];
    extraAfter = [ "reverse-proxy-dynamic-config.service" ];
  };
}
