{ config, pkgs, ... }:
let
  composeFile = "${./.}/docker-compose.yaml";
  host = "social.${config.domains.main}";
in
{
  # uid 999 is the redis image's own user. Same mode as the legacy role created it with.
  systemd.tmpfiles.rules = [
    "d /var/lib/app-data/sharkey/redis 0740 999 999 -"
  ];

  # Only the settings prod actually set; everything else is upstream's default. The
  # annotated original is ansible/roles/container_sharkey/templates/config/default.yml.
  # Readable by uid 991, Sharkey's user inside its image, and nobody else.
  sops.templates."sharkey-default.yml" = {
    uid = 991;
    gid = 991;
    mode = "0400";
    content = ''
      # The instance's identity: every local actor, note and key is published under
      # this URL, and the rest of the fediverse knows them by it. Upstream's warning:
      # once the instance has started, never change it. Hence `autostart = false`
      # below until the cutover, when domains.main is snyssen.be again.
      url: https://${host}/
      port: 3000

      db:
        host: postgres
        port: 5432
        db: sharkey
        user: sharkey
        pass: "${config.sops.placeholder."compose-stacks/databases/postgres/passwords/sharkey"}"
      dbReplications: false

      redis:
        host: sharkey_redis
        port: 6379

      # Also fixed for the life of the instance, per upstream.
      id: aidx

      proxyBypassHosts:
        - api.deepl.com
        - api-free.deepl.com
        - www.recaptcha.net
        - hcaptcha.com
        - challenges.cloudflare.com
      proxyRemoteFiles: true
      signToActivityPubGet: true
      attachLdSignatureForRelays: true

      # Exceptions to upstream's refusal to fetch from private addresses. Prod's list
      # (internal_networks_cidr), translated to this host's ranges as in auth's
      # `internal` network: LAN, the whole Docker pool, and the tailnet.
      allowedPrivateNetworks:
        - "192.168.1.0/24"
        - "172.16.0.0/12"
        - "100.64.0.0/10"
    '';
  };

  sops.templates."compose-sharkey.env".content = ''
    SHARKEY_CONFIG_PATH=${config.sops.templates."sharkey-default.yml".path}
  '';

  # Public, no forwardAuth: other servers deliver to it, and accounts are Sharkey's own.
  reverseProxy.dynamicConfig.sharkey = ''
    http:
      routers:
        sharkey:
          rule: "Host(`${host}`)"
          entryPoints:
            - websecure
          service: sharkey
          tls:
            certResolver: le_main
      services:
        sharkey:
          loadBalancer:
            servers:
              - url: "http://sharkey:3000"
  '';

  compose-stacks.stacks.sharkey = {
    restartTriggers = [
      ../../data/databases.yaml
      config.sops.templates."sharkey-default.yml".content
    ];
    inherit composeFile;
    environmentFile = config.sops.templates."compose-sharkey.env".path;
    dockerNetworks = [
      "web"
      "db"
    ];
    # Down until the Phase B cutover. The url above is the instance's permanent
    # identity, and the test domain is not it: started on apps today, Sharkey would
    # either initialise a new instance under the test domain or, on imported data,
    # serve prod's accounts under a name the rest of the fediverse doesn't know.
    # prod-import and postgres-restore leave a stopped stack stopped, so both can run
    # beforehand. Flip back to true along with domains.main.
    autostart = false;
    extraAfter = [
      "mnt-bulk.mount"
      "reverse-proxy-dynamic-config.service"
      "sharkey-storage-dirs.service"
    ];
  };

  # Same shape as paperless-storage-dirs: /mnt/bulk subpaths can't go through ordinary
  # tmpfiles rules, which run before the NFS mount is up. Owner and mode as the legacy
  # role set them.
  systemd.services.sharkey-storage-dirs = {
    description = "Create /mnt/bulk directories the sharkey stack expects";
    after = [ "mnt-bulk.mount" ];
    requires = [ "mnt-bulk.mount" ];
    before = [ "compose-sharkey.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "sharkey-storage-dirs" ''
        set -euo pipefail
        install -d -m 0740 -o 991 -g 991 /mnt/bulk/sharkey/files
      '';
    };
  };
}
