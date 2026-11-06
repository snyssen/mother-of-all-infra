{ config, pkgs, ... }:
let
  dataDir = "/mnt/bulk/syncthing";
in
{
  syncthing = {
    inherit dataDir;
    configDir = "/var/lib/app-data/syncthing/config";
    # Generated before the first deploy, so apps' ID could go into nix/data/syncthing.nix
    # ahead of time; a rebuild keeps it.
    identity.sopsFile = ./data/syncthing.yaml;
    # Not localhost: Traefik reaches the GUI from its container, through
    # host.docker.internal. The host firewall still only lets the Docker range in (see
    # modules/nixos/docker.nix), and the route below is behind Authelia.
    gui.address = "0.0.0.0:8384";
    # The sync and local discovery ports, opened by Syncthing itself rather than
    # forwarded by Traefik: they carry Syncthing's own mutually authenticated TLS, which
    # Traefik could only pass through, and its announcements then name the port peers
    # can actually reach. Listed in compose/reverse-proxy all the same.
    openFirewall = true;
    # Every folder, as on prod, but each with only the devices that carry it — plus
    # prod's own Syncthing on all of them until the cutover, so apps fills from it.
    # TODO: drop sync.snyssen.be (here and from nix/data/syncthing.nix) once prod is gone.
    folders = {
      "Aegis Backups" = {
        # Created on the phone, so a generated ID rather than its name.
        id = "h5q7k-uenv3";
        path = "${dataDir}/Aegis Backups";
        devices = [
          "sync.snyssen.be"
          "Pixel 8 Pro"
        ];
      };
      KSP = {
        path = "${dataDir}/KSP";
        devices = [
          "sync.snyssen.be"
          "blackfog"
          "gaming"
        ];
      };
      Notes = {
        path = "${dataDir}/Notes";
        devices = [
          "sync.snyssen.be"
          "Pixel 8 Pro"
          "blackfog"
          "purplehaze"
          "gaming"
        ];
      };
      PrismLauncher = {
        path = "${dataDir}/PrismLauncher";
        devices = [
          "sync.snyssen.be"
          "blackfog"
          "purplehaze"
          "gaming"
        ];
      };
      RetroArch = {
        path = "${dataDir}/retroarch";
        devices = [
          "sync.snyssen.be"
          "blackfog"
          "purplehaze"
          "gaming"
        ];
      };
    };
  };

  # Owned by the user and group Syncthing runs as. The group is services.syncthing's own
  # `syncthing`, not the username: no `snyssen` group exists (snyssen's is `users`).
  systemd.tmpfiles.rules = [
    "d ${config.syncthing.configDir} 0700 ${config.services.syncthing.user} ${config.services.syncthing.group} -"
  ];

  # The data lives on the NFS mount, so Syncthing must not start before it — ordered
  # after the automount only, as the compose stacks are. Never Requires= the mount (as
  # RequiresMountsFor= would): /mnt/bulk is an automount that systemd unmounts after 10s
  # idle (modules/nixos/nfs-mounts.nix), and Requires= turns that unmount into a stop of
  # Syncthing a few seconds after every start. Any access mounts it again.
  systemd.services.syncthing.after = [
    "mnt-bulk.automount"
    "syncthing-storage-dirs.service"
  ];

  # Same shape as the compose stacks' storage-dirs units: /mnt/bulk subpaths can't go
  # through ordinary tmpfiles rules, which run before the NFS mount is up.
  systemd.services.syncthing-storage-dirs = {
    description = "Create the /mnt/bulk directory syncthing expects";
    after = [ "mnt-bulk.mount" ];
    requires = [ "mnt-bulk.mount" ];
    before = [ "syncthing.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "syncthing-storage-dirs" ''
        set -euo pipefail
        install -d -m 0700 -o ${config.services.syncthing.user} -g ${config.services.syncthing.group} ${dataDir}
      '';
    };
  };

  # The GUI on sync.<domain>, as on prod but behind Authelia (sysadmin rule, see
  # auth/authelia-configuration.nix): no GUI password is set, so this is its only gate.
  reverseProxy.dynamicConfig.syncthing = ''
    http:
      routers:
        syncthing:
          rule: "Host(`sync.${config.domains.main}`)"
          entryPoints:
            - websecure
          service: syncthing
          middlewares:
            - authelia
          tls:
            certResolver: le_main
      services:
        syncthing:
          loadBalancer:
            servers:
              - url: "http://host.docker.internal:8384"
  '';
}
