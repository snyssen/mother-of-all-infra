{ config, lib, ... }:
let
  cfg = config.nfsExports;

  # Build the /etc/exports content from the configured list of exports.
  # Each export line takes the form:
  #   <path>  <cidr>(<options>) [<cidr>(<options>) ...]
  # If an export does not specify its own clients list the module-wide
  # lanCidr is used as the sole client.
  #
  # For NFSv4, each export must have a unique fsid. If not explicitly provided
  # in the options, one is automatically appended based on the export's index.
  # root_squash is automatically appended unless already present in the
  # export options. This maps root (uid 0) to nobody while preserving regular
  # user UIDs.
  exportsContent = lib.concatMapStringsSep "" (
    { index, export }:
    let
      clients = if export.clients != [ ] then export.clients else [ cfg.lanCidr ];
      # Append fsid to options if not already present
      optionsWithFsid =
        if lib.hasInfix "fsid=" export.options then
          export.options
        else
          "${export.options},fsid=${toString index}";
      # Append root_squash if not already present
      options =
        if lib.hasInfix "root_squash" optionsWithFsid then
          optionsWithFsid
        else
          "${optionsWithFsid},root_squash";
      clientsStr = lib.concatMapStringsSep " " (c: "${c}(${options})") clients;
    in
    "${export.path}  ${clientsStr}\n"
  ) (lib.imap1 (index: export: { inherit index export; }) cfg.exports);
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
        lib.types.submodule (
          { config, ... }:
          {
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
                  client entry. The fsid parameter is automatically appended
                  based on the export's index (1, 2, 3, ...) unless explicitly
                  provided. root_squash is automatically appended unless
                  already present. See exports(5) for the full list of options.
                '';
                example = "ro,sync,no_subtree_check";
              };
            };
          }
        )
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

    # Ensure every exported directory exists with appropriate permissions.
    # Mode 0777 allows any UID to read, write, and execute, ensuring clients
    # can create and manage files with their own UIDs.
    systemd.tmpfiles.rules = lib.map (export: "d ${export.path} 0777 root root -") cfg.exports;

    # Open the NFS port (2049) and the portmapper port (111) on both TCP and
    # UDP for NFSv4 clients.
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
