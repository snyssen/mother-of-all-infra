{ config, lib, ... }:
let
  cfg = config.nfsExports;

  # Build the /etc/exports content from the configured list of exports.
  # Each export line takes the form:
  #   <path>  <cidr>(<options>) [<cidr>(<options>) ...]
  # If an export does not specify its own clients list the module-wide
  # lanCidr is used as the sole client.
  exportsContent = lib.concatMapStrings (
    export:
    let
      clients = if export.clients != [ ] then export.clients else [ cfg.lanCidr ];
      clientsStr = lib.concatMapStringsSep " " (c: "${c}(${export.options})") clients;
    in
    "${export.path}  ${clientsStr}\n"
  ) cfg.exports;
in
{
  options.nfsExports = {
    enable = lib.mkEnableOption "NFS server with configurable exports";

    lanCidr = lib.mkOption {
      type = lib.types.str;
      default = "192.168.1.0/24";
      description = ''
        Default LAN CIDR used as the allowed client range for any export that
        does not specify its own ''${clients} list.
      '';
      example = "10.0.0.0/8";
    };

    exports = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            path = lib.mkOption {
              type = lib.types.str;
              description = "Absolute path of the directory to export via NFS.";
              example = "/mnt/storage/apps-vm";
            };

            clients = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = ''
                List of CIDRs or hostnames that are allowed to mount this
                export.  When empty (the default) the module-wide
                ''${nfsExports.lanCidr} is used.
              '';
              example = [
                "192.168.1.0/24"
                "10.0.0.5"
              ];
            };

            options = lib.mkOption {
              type = lib.types.str;
              default = "rw,sync,no_subtree_check";
              description = ''
                NFS export options placed inside the parentheses for each
                client entry.  See exports(5) for the full list of options.
              '';
              example = "ro,sync,no_subtree_check";
            };
          };
        }
      );
      default = [ ];
      description = "List of directories to export via NFS.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.nfs.server = {
      enable = true;
      exports = exportsContent;
    };

    # Ensure every exported directory exists on the host filesystem.
    # systemd-tmpfiles creates the directory if absent; it is a no-op when it
    # already exists, so this is safe for paths that live on external mounts.
    systemd.tmpfiles.rules = lib.map (export: "d ${export.path} 0755 root root -") cfg.exports;

    # Open the NFS port (2049) and the portmapper port (111) on both TCP and
    # UDP so that NFSv3 and NFSv4 clients on the LAN can reach the server.
    networking.firewall = {
      allowedTCPPorts = [
        111 # rpcbind / portmapper
        2049 # NFS
      ];
      allowedUDPPorts = [
        111 # rpcbind / portmapper
        2049 # NFS
      ];
    };
  };
}
