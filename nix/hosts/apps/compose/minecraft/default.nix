{ config, pkgs, ... }:
let
  composeFile = "${./.}/docker-compose.yaml";

  # TODO: restore prod's sizing at the Phase B cutover — 8G heap / 8.2g limit for both
  # servers. Shrunk here because the test VM has 8 GiB of RAM in total, shared with
  # every other stack. The limit leaves headroom above the heap for the JVM itself.
  memory = {
    main = {
      heap = "2G";
      limit = "2560m";
    };
    usw = {
      heap = "1G";
      limit = "1536m";
    };
  };
in
{
  # Carried over unchanged from the legacy vault, joined into the comma-separated form
  # the image's WHITELIST and OPS variables take (`just sops-from-vault --join ,`).
  sops.secrets = {
    "compose-stacks/minecraft/whitelist" = {
      sopsFile = ../../data/minecraft.yaml;
    };
    "compose-stacks/minecraft/ops" = {
      sopsFile = ../../data/minecraft.yaml;
    };
  };

  sops.templates."compose-minecraft.env".content = ''
    MAIN_DOMAIN=${config.domains.main}
    WHITELIST=${config.sops.placeholder."compose-stacks/minecraft/whitelist"}
    OPS=${config.sops.placeholder."compose-stacks/minecraft/ops"}
    MC_MAIN_MEMORY=${memory.main.heap}
    MC_MAIN_MEM_LIMIT=${memory.main.limit}
    MC_USW_MEMORY=${memory.usw.heap}
    MC_USW_MEM_LIMIT=${memory.usw.limit}
  '';

  # The two dynmap live maps, public as on prod, and the game itself: everything on the
  # `minecraft` entrypoint (declared in compose/reverse-proxy) goes to mc-router.
  reverseProxy.dynamicConfig.minecraft = ''
    tcp:
      routers:
        mc-router:
          rule: "HostSNI(`*`)"
          entryPoints:
            - minecraft
          service: mc-router
      services:
        mc-router:
          loadBalancer:
            servers:
              - address: "mc-router:25565"
    http:
      routers:
        dynmap:
          rule: "Host(`mc.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: dynmap
          tls:
            certResolver: le_main
        mc-usw-dynmap:
          rule: "Host(`mc-usw.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: mc-usw-dynmap
          tls:
            certResolver: le_main
      services:
        dynmap:
          loadBalancer:
            servers:
              - url: "http://minecraft:8123"
        mc-usw-dynmap:
          loadBalancer:
            servers:
              - url: "http://mc-usw:8123"
  '';

  compose-stacks.stacks.minecraft = {
    restartTriggers = [
      ../../data/minecraft.yaml
      config.sops.templates."compose-minecraft.env".content
    ];
    inherit composeFile;
    environmentFile = config.sops.templates."compose-minecraft.env".path;
    dockerNetworks = [
      "web"
      "monitoring"
    ];
    extraAfter = [
      "mnt-bulk.mount"
      "reverse-proxy-dynamic-config.service"
      "minecraft-storage-dirs.service"
    ];
  };

  # Same shape as paperless-storage-dirs: /mnt/bulk subpaths can't go through ordinary
  # tmpfiles rules, which run before the NFS mount is up. uid/gid 1000 is the image's
  # default runtime user (its UID/GID environment variables).
  systemd.services.minecraft-storage-dirs = {
    description = "Create /mnt/bulk directories the minecraft stack expects";
    after = [ "mnt-bulk.mount" ];
    requires = [ "mnt-bulk.mount" ];
    before = [ "compose-minecraft.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "minecraft-storage-dirs" ''
        set -euo pipefail
        install -d -m 0775 -o 1000 -g 1000 \
          /mnt/bulk/minecraft/data \
          /mnt/bulk/mc-usw/data
      '';
    };
  };
}
