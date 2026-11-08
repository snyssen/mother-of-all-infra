{ config, ... }:
{
  # No Authelia and no state, same as prod. The image serves on WEBPORT (8080).
  reverseProxy.dynamicConfig.speedtest = ''
    http:
      routers:
        speedtest:
          rule: "Host(`speedtest.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: speedtest
          tls:
            certResolver: le_main
      services:
        speedtest:
          loadBalancer:
            servers:
              - url: "http://speedtest:8080"
  '';

  compose-stacks.stacks.speedtest = {
    composeFile = "${./.}/docker-compose.yaml";
    dockerNetworks = [ "web" ];
    extraAfter = [ "reverse-proxy-dynamic-config.service" ];
  };
}
