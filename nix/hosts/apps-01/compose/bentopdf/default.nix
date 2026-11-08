{ config, ... }:
{
  # Same hostname and gate as the legacy Stirling stack: forwardAuth, lowered to
  # one_factor for any registered user by the access_control rule in
  # auth/authelia-configuration.nix. BentoPDF has no login of its own; the gate is
  # what keeps the public route to friends and family.
  reverseProxy.dynamicConfig.bentopdf = ''
    http:
      routers:
        bentopdf:
          rule: "Host(`pdf.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: bentopdf
          middlewares:
            - authelia
            - traefik-compress
          tls:
            certResolver: le_main
      services:
        bentopdf:
          loadBalancer:
            servers:
              - url: "http://bentopdf:8080"
  '';

  compose-stacks.stacks.bentopdf = {
    composeFile = "${./.}/docker-compose.yaml";
    dockerNetworks = [ "web" ];
    extraAfter = [ "reverse-proxy-dynamic-config.service" ];
  };
}
