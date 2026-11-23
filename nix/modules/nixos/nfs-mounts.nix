{ config, lib, ... }:
let
  cfg = config.nfsMounts;

  # Convert mount definitions to systemd.mounts and systemd.automounts entries
  mkMountUnit =
    name: mount:
    let
      # Normalize the remote path (ensure it starts with /)
      remotePath =
        if lib.hasPrefix "/" mount.remotePath then mount.remotePath else "/${mount.remotePath}";
      # Build the NFS source (server:path)
      server = mount.host or "hypervisor-01";
      source = "${server}:${remotePath}";
    in
    {
      what = source;
      where = mount.path;
      type = "nfs";
      mountConfig = {
        Options = lib.concatStringsSep "," mount.options;
        TimeoutSec = 30;
      };
      # If Tailscale dependency is set, order after tailscale+network; otherwise just network
      unitConfig = {
        After =
          if mount.dependsOn.tailscale or false then
            [
              "tailscaled.service"
              "network-online.target"
            ]
          else
            [ "network-online.target" ];
        Wants =
          if mount.dependsOn.tailscale or false then
            [
              "tailscaled.service"
              "network-online.target"
            ]
          else
            [ ];
      };
    };

  mkAutomountUnit = name: mount: {
    where = mount.path;
    automountConfig = {
      TimeoutIdleSec = mount.idleTimeout;
    };
    wantedBy = [ "multi-user.target" ];
    unitConfig = {
      After =
        if mount.dependsOn.tailscale or false then
          [
            "tailscaled.service"
            "network-online.target"
          ]
        else
          [ ];
      Wants =
        if mount.dependsOn.tailscale or false then
          [
            "tailscaled.service"
            "network-online.target"
          ]
        else
          [ ];
    };
  };

  # Convert attribute set of mounts to lists
  mountsList = lib.map (pair: mkMountUnit pair.name pair.value) (lib.attrsToList cfg.mounts);
  automountsList = lib.map (pair: mkAutomountUnit pair.name pair.value) (lib.attrsToList cfg.mounts);
in
{
  options.nfsMounts = {
    enable = lib.mkEnableOption "NFS client mounts";

    mounts = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            path = lib.mkOption {
              type = lib.types.str;
              description = "Mount point on the local machine (absolute path)";
              example = "/mnt/exports/media";
            };

            host = lib.mkOption {
              type = lib.types.str;
              default = "hypervisor-01";
              description = "Hostname or IP address of the NFS server";
              example = "192.168.1.100";
            };

            remotePath = lib.mkOption {
              type = lib.types.str;
              description = "Path of the NFS export on the server";
              example = "/mnt/storage/media";
            };

            options = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [
                "defaults"
                "hard"
              ];
              description = ''
                NFS mount options. Defaults include:
                - defaults: basic defaults
                - hard: hard mount (retries indefinitely)

                Leave rsize/wsize out unless measured otherwise: client and server then
                negotiate the largest size both support (up to 1 MiB), where a fixed
                8 KiB, as this module once set, throttles every large read and write.
                `intr` is not needed either: the kernel has ignored it since 2.6.25.
              '';
              example = [
                "hard"
                "vers=4.2"
              ];
            };

            idleTimeout = lib.mkOption {
              type = lib.types.ints.unsigned;
              default = 0;
              description = ''
                Seconds of inactivity after which the automount unmounts the share
                (systemd's TimeoutIdleSec). 0, the default, never unmounts it: the
                automount then only makes the first mount lazy, so boot does not wait on
                the NFS server.

                Set one only for an occasional share, such as a laptop's. On a server,
                containers reach the share through bind mounts that systemd does not
                count as use, so it looks idle while in use, and every unmount stops
                each unit that Requires= the mount.
              '';
              example = 600;
            };

            dependsOn = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  tailscale = lib.mkOption {
                    type = lib.types.bool;
                    default = false;
                    description = "Whether this mount depends on Tailscale being connected";
                  };
                };
              };
              default = { };
              description = "Service dependencies for this mount";
            };
          };
        }
      );
      default = { };
      description = "NFS mounts to configure";
      example = {
        media = {
          path = "/mnt/exports/media";
          host = "hypervisor-01";
          remotePath = "/mnt/storage/media";
          dependsOn.tailscale = false;
          options = [
            "defaults"
            "hard"
          ];
        };
        backups = {
          path = "/mnt/exports/backups";
          host = "server.tailscale.com";
          remotePath = "/backups";
          dependsOn.tailscale = true;
          options = [
            "defaults"
            "hard"
          ];
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    boot.supportedFilesystems = [ "nfs" ];

    # Create mount points if they don't exist
    system.activationScripts.nfsMountPoints = lib.stringAfter [ "var" ] (
      lib.concatMapStringsSep "\n" (pair: ''
        mkdir -p ${lib.escapeShellArg pair.value.path}
      '') (lib.attrsToList cfg.mounts)
    );

    systemd = {
      mounts = mountsList;
      automounts = automountsList;
    };
  };
}
