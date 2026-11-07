{ config, ... }:
let
  composeFile = "${./.}/docker-compose.yaml";
in
{
  # The controller runs as PUID 1000 (and chowns /config to it on every start); MongoDB
  # as the image's own mongodb user, 999.
  systemd.tmpfiles.rules = [
    "d /var/lib/app-data/unifi 0755 0 0 -"
    "d /var/lib/app-data/unifi/config 0750 1000 1000 -"
    "d /var/lib/app-data/unifi/mongodb 0700 999 999 -"
  ];

  # New, not carried over from the legacy vault: prod's MongoDB isn't imported (the
  # controller comes back from a .unf restore instead), so nothing depends on its
  # passwords. Both only take effect on the first start, against an empty database.
  sops.secrets = {
    "compose-stacks/unifi/mongo/password" = {
      sopsFile = ../../data/unifi.yaml;
    };
    "compose-stacks/unifi/mongo/root_password" = {
      sopsFile = ../../data/unifi.yaml;
    };
  };

  sops.templates."compose-unifi.env".content = ''
    MONGO_PASS=${config.sops.placeholder."compose-stacks/unifi/mongo/password"}
    MONGO_INITDB_ROOT_PASSWORD=${config.sops.placeholder."compose-stacks/unifi/mongo/root_password"}
  '';

  # As prod's labels: the web UI and the guest portal over HTTPS, LAN/tailnet only, and
  # the device ports on their own entrypoints (declared in compose/reverse-proxy).
  #
  # The controller only serves HTTPS, with a self-signed certificate it generates itself,
  # hence the transport skipping verification; that hop never leaves the `web` network.
  #
  # Devices reach the controller at the Inform Host set in its settings (restored with
  # its backup), on 8080. L2 discovery can't work through Docker's NAT, here as on prod:
  # new devices are pointed at it by the `unifi` DNS name or set-inform.
  reverseProxy.dynamicConfig.unifi = ''
    http:
      routers:
        unifi:
          rule: "Host(`unifi.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: unifi
          middlewares:
            - lan-whitelist
          tls:
            certResolver: le_main
        unifi-guest:
          rule: "Host(`unifi-guest.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: unifi-guest
          middlewares:
            - lan-whitelist
          tls:
            certResolver: le_main
      services:
        unifi:
          loadBalancer:
            serversTransport: unifi-self-signed
            servers:
              - url: "https://unifi-network-application:8443"
        unifi-guest:
          loadBalancer:
            serversTransport: unifi-self-signed
            servers:
              - url: "https://unifi-network-application:8843"
      serversTransports:
        unifi-self-signed:
          insecureSkipVerify: true
    tcp:
      routers:
        unifi-inform:
          rule: "HostSNI(`*`)"
          entryPoints:
            - unifi-inform
          service: unifi-inform
      services:
        unifi-inform:
          loadBalancer:
            servers:
              - address: "unifi-network-application:8080"
    udp:
      routers:
        unifi-stun:
          entryPoints:
            - unifi-stun
          service: unifi-stun
        unifi-discovery:
          entryPoints:
            - unifi-discovery
          service: unifi-discovery
      services:
        unifi-stun:
          loadBalancer:
            servers:
              - address: "unifi-network-application:3478"
        unifi-discovery:
          loadBalancer:
            servers:
              - address: "unifi-network-application:10001"
  '';

  compose-stacks.stacks.unifi = {
    restartTriggers = [
      ../../data/unifi.yaml
      config.sops.templates."compose-unifi.env".content
    ];
    inherit composeFile;
    environmentFile = config.sops.templates."compose-unifi.env".path;
    dockerNetworks = [ "web" ];
    extraAfter = [ "reverse-proxy-dynamic-config.service" ];
  };
}
