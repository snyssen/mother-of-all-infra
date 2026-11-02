{ config, ... }:
{
  # Served on the bare domain, as on prod. No Authelia and no state.
  reverseProxy.dynamicConfig.personal-website = ''
    http:
      routers:
        personal-website:
          rule: "Host(`${config.domains.main}`)"
          entryPoints:
            - websecure
          service: personal-website
          middlewares:
            - traefik-compress
          tls:
            certResolver: le_main
      services:
        personal-website:
          loadBalancer:
            servers:
              - url: "http://personal-website:80"
  '';

  compose-stacks.stacks.personal-website = {
    composeFile = "${./.}/docker-compose.yaml";
    dockerNetworks = [ "web" ];
    extraAfter = [ "reverse-proxy-dynamic-config.service" ];
  };
}
