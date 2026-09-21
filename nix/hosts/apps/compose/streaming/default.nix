{
  lib,
  config,
  pkgs,
  ...
}:
let
  composeFile = "${./.}/docker-compose.yaml";
in
{
  # Local (fast SSD) app-data dirs only — everything under /mnt/bulk is handled by
  # streaming-storage-dirs below instead, since ordinary tmpfiles rules run early in
  # boot (systemd-tmpfiles-setup.service), before the NFS mount backing /mnt/bulk is
  # necessarily up. Owners/modes carried over from the legacy Ansible role's file task
  # (33 = www-data-equivalent PUID used by these images; group 100 = this host's real
  # "users" gid, standing in for the legacy role's `ansible_user_gid`).
  systemd.tmpfiles.rules = [
    "d /var/lib/app-data/jellyfin/data 0750 33 100 -"
    "d /var/lib/app-data/jellyfin/config 0750 33 100 -"
    "d /var/lib/app-data/jellyfin/cache 0750 33 100 -"
    "d /var/lib/app-data/jellyfin/logs 0750 33 100 -"
    "d /var/lib/app-data/audiobookshelf/config 0750 33 100 -"
    "d /var/lib/app-data/audiobookshelf/metadata 0750 33 100 -"
    "d /var/lib/app-data/sonarr/config 0774 33 100 -"
    "d /var/lib/app-data/radarr/config 0774 33 100 -"
    "d /var/lib/app-data/lidarr/config 0774 33 100 -"
    "d /var/lib/app-data/prowlarr/config 0774 33 100 -"
    "d /var/lib/app-data/bazarr/config 0774 33 100 -"
    "d /var/lib/app-data/pinchflat/config 0774 33 100 -"
    "d /var/lib/app-data/lidatube/config 0774 33 100 -"
    "d /var/lib/app-data/lidify/config 0774 33 100 -"
    "d /var/lib/app-data/peertube/config 0750 999 999 -"
    "d /var/lib/app-data/peertube/redis 0750 999 999 -"
    "d /var/lib/app-data/gluetun 0700 0 0 -"
  ];

  sops.secrets = {
    "compose-stacks/streaming/vpn/wireguard_private_key" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-streaming.service" ];
    };
    "compose-stacks/streaming/vpn/control_server_api_key" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-streaming.service" ];
    };
    "compose-stacks/streaming/peertube/secret" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-streaming.service" ];
    };
    "compose-stacks/streaming/peertube/oidc/client_id" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-streaming.service" ];
    };
    "compose-stacks/streaming/peertube/oidc/client_secret" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-streaming.service" ];
    };
    "compose-stacks/streaming/peertube/oidc/client_secret_hash" = {
      sopsFile = ../../data/secrets.yaml;
      restartUnits = [ "compose-auth.service" ];
    };
  };

  # All six values (plus the Postgres passwords and smtp/* referenced below) are
  # carried over unchanged from the legacy Ansible Vault rather than rotated — same
  # rationale as ntfy: reusing the WireGuard key keeps the same VPN identity/forwarded
  # port with the provider, and reusing the OIDC client secret means Authelia's client
  # entry (see auth/authelia-configuration.nix) and PeerTube's plugin config agree
  # without needing to regenerate/re-hash anything here.
  sops.templates."compose-streaming.env".content = ''
    JELLYFIN_PublishedServerUrl=https://streaming.${config.domains.main}

    WIREGUARD_PRIVATE_KEY=${config.sops.placeholder."compose-stacks/streaming/vpn/wireguard_private_key"}
    HTTP_CONTROL_SERVER_AUTH_DEFAULT_ROLE={"auth":"apikey","apikey":"${config.sops.placeholder."compose-stacks/streaming/vpn/control_server_api_key"}"}

    PEERTUBE_DB_PASSWORD=${config.sops.placeholder."compose-stacks/databases/postgres/passwords/peertube"}
    PEERTUBE_WEBSERVER_HOSTNAME=peertube.${config.domains.main}
    PEERTUBE_SECRET=${config.sops.placeholder."compose-stacks/streaming/peertube/secret"}
    PEERTUBE_SMTP_HOSTNAME=${config.sops.placeholder."smtp/host"}
    PEERTUBE_SMTP_PORT=${config.sops.placeholder."smtp/port"}
    PEERTUBE_SMTP_USERNAME=${config.sops.placeholder."smtp/user"}
    PEERTUBE_SMTP_PASSWORD=${config.sops.placeholder."smtp/password"}
    PEERTUBE_SMTP_FROM=peertube@${config.domains.main}
    PEERTUBE_ADMIN_EMAIL=${config.sops.placeholder."smtp/to"}
    PEERTUBE_PLUGIN_OFFICIAL_AUTH_OPENID_CONNECT_DISCOVER_URL=https://auth.${config.domains.main}/.well-known/openid-configuration
    PEERTUBE_PLUGIN_OFFICIAL_AUTH_OPENID_CONNECT_CLIENT_ID=${config.sops.placeholder."compose-stacks/streaming/peertube/oidc/client_id"}
    PEERTUBE_PLUGIN_OFFICIAL_AUTH_OPENID_CONNECT_CLIENT_SECRET=${config.sops.placeholder."compose-stacks/streaming/peertube/oidc/client_secret"}

    POSTGRES_PASSWORD=${config.sops.placeholder."compose-stacks/databases/postgres/passwords/audiomuse"}
  '';

  # /mnt/bulk subpaths can't go through ordinary tmpfiles rules (see the comment
  # above) — this unit creates them after the NFS mount is actually up, mirroring the
  # same "prep, then let the stack start" shape as reverse-proxy-dynamic-config and
  # crowdsec-machine-bootstrap elsewhere in this migration. Owners/modes match the
  # legacy Ansible file task exactly (peertube's media dir alone uses uid/gid 999, its
  # own container's user).
  systemd.services.streaming-storage-dirs = {
    description = "Create /mnt/bulk directories the streaming stack expects";
    after = [ "mnt-bulk.mount" ];
    requires = [ "mnt-bulk.mount" ];
    before = [ "compose-streaming.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "streaming-storage-dirs" ''
        set -euo pipefail
        install -d -m 0774 -o 33 -g 100 \
          /mnt/bulk/streaming/media/movies \
          /mnt/bulk/streaming/media/tv \
          /mnt/bulk/streaming/media/music \
          /mnt/bulk/streaming/media/music_vi \
          /mnt/bulk/streaming/media/audiobooks \
          /mnt/bulk/streaming/media/audiobooks_vi \
          /mnt/bulk/streaming/media/podcasts \
          /mnt/bulk/streaming/media/podcasts_vi \
          /mnt/bulk/streaming/media/books
        install -d -m 0750 -o 33 -g 100 \
          /mnt/bulk/torrent \
          /mnt/bulk/streaming/torrent \
          /mnt/bulk/usenet \
          /mnt/bulk/streaming/usenet
        install -d -m 0750 -o 999 -g 999 \
          /mnt/bulk/streaming/peertube/data
      '';
    };
  };

  # Authelia-gated: the download clients and *arr apps (matching the legacy
  # `authelia@docker` middleware). Jellyfin/audiobookshelf/peertube/audiomuse have
  # their own auth and stay ungated, matching the legacy setup. lidatube/lidify were
  # also authelia-gated in the legacy setup (no auth of their own).
  #
  # torrent/usenet/sonarr/radarr/lidarr/prowlarr/bazarr/pinchflat all share the `vpn`
  # container's network namespace (network_mode: service:vpn in docker-compose.yaml),
  # so their services all route to the `vpn` hostname on their respective ports —
  # matching how the legacy Traefik labels were literally attached to the `vpn`
  # container.
  #
  # No jellyfin-discovery UDP entrypoint (legacy had one for LAN auto-discovery,
  # port 7359) — this migration already deliberately dropped the `lan` network and
  # LAN-broadcast discovery for other stacks (see the Architecture Decisions table in
  # the migration plan doc); a VM behind Traefik/NAT can't usefully answer LAN
  # broadcast discovery anyway. Clients need the server URL entered manually.
  reverseProxy.dynamicConfig.streaming = ''
    http:
      routers:
        jellyfin:
          rule: "Host(`streaming.${config.domains.main}`) && !Path(`/metrics`)"
          entryPoints:
            - websecure
          service: jellyfin
          middlewares:
            - jellyfin-headers
          tls:
            certResolver: le_main
        audiobookshelf:
          rule: "Host(`audiobooks.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: audiobookshelf
          tls:
            certResolver: le_main
        lidatube:
          rule: "Host(`lidatube.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: lidatube
          middlewares:
            - authelia
          tls:
            certResolver: le_main
        lidify:
          rule: "Host(`lidify.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: lidify
          middlewares:
            - authelia
          tls:
            certResolver: le_main
        peertube:
          rule: "Host(`peertube.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: peertube
          tls:
            certResolver: le_main
        audiomuse:
          rule: "Host(`audiomuse.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: audiomuse
          tls:
            certResolver: le_main
        torrent:
          rule: "Host(`torrent.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: torrent
          middlewares:
            - authelia
          tls:
            certResolver: le_main
        usenet:
          rule: "Host(`usenet.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: usenet
          middlewares:
            - authelia
          tls:
            certResolver: le_main
        pinchflat:
          rule: "Host(`yt.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: pinchflat
          middlewares:
            - authelia
          tls:
            certResolver: le_main
        sonarr:
          rule: "Host(`sonarr.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: sonarr
          middlewares:
            - authelia
          tls:
            certResolver: le_main
        radarr:
          rule: "Host(`radarr.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: radarr
          middlewares:
            - authelia
          tls:
            certResolver: le_main
        lidarr:
          rule: "Host(`lidarr.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: lidarr
          middlewares:
            - authelia
          tls:
            certResolver: le_main
        prowlarr:
          rule: "Host(`prowlarr.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: prowlarr
          middlewares:
            - authelia
          tls:
            certResolver: le_main
        bazarr:
          rule: "Host(`bazarr.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: bazarr
          middlewares:
            - authelia
          tls:
            certResolver: le_main
      services:
        jellyfin:
          loadBalancer:
            servers:
              - url: "http://jellyfin:8096"
        audiobookshelf:
          loadBalancer:
            servers:
              - url: "http://audiobookshelf:80"
        lidatube:
          loadBalancer:
            servers:
              - url: "http://lidatube:5000"
        lidify:
          loadBalancer:
            servers:
              - url: "http://lidify:5000"
        peertube:
          loadBalancer:
            servers:
              - url: "http://peertube:9000"
        audiomuse:
          loadBalancer:
            servers:
              - url: "http://audiomuse_web:8000"
        torrent:
          loadBalancer:
            servers:
              - url: "http://vpn:9091"
        usenet:
          loadBalancer:
            servers:
              - url: "http://vpn:8080"
        pinchflat:
          loadBalancer:
            servers:
              - url: "http://vpn:8945"
        sonarr:
          loadBalancer:
            servers:
              - url: "http://vpn:8989"
        radarr:
          loadBalancer:
            servers:
              - url: "http://vpn:7878"
        lidarr:
          loadBalancer:
            servers:
              - url: "http://vpn:8686"
        prowlarr:
          loadBalancer:
            servers:
              - url: "http://vpn:9696"
        bazarr:
          loadBalancer:
            servers:
              - url: "http://vpn:6767"
      middlewares:
        # Trimmed from the legacy label set: sslRedirect/sslHost/sslForceHost dropped
        # as both deprecated-then-removed in Traefik v3 and redundant (the `web`
        # entrypoint already redirects to `websecure` globally — see reverse-proxy's
        # own docker-compose.yaml). The rest (STS + basic hardening headers, plus the
        # noindex robots tag from Jellyfin's own Traefik docs) are still valid v3
        # headers middleware fields.
        jellyfin-headers:
          headers:
            customResponseHeaders:
              X-Robots-Tag: noindex,nofollow,nosnippet,noarchive,notranslate,noimageindex
            stsSeconds: 315360000
            stsIncludeSubdomains: true
            stsPreload: true
            forceSTSHeader: true
            frameDeny: true
            contentTypeNosniff: true
            browserXssFilter: true
            customFrameOptionsValue: "allow-from https://streaming.${config.domains.main}"
  '';

  compose-stacks.stacks.streaming = {
    inherit composeFile;
    environmentFile = config.sops.templates."compose-streaming.env".path;
    dockerNetworks = [
      "web"
      "monitoring"
      "ldap"
      "db"
    ];
    extraAfter = [
      "reverse-proxy-dynamic-config.service"
      "mnt-bulk.mount"
      "streaming-storage-dirs.service"
    ];
  };
}
