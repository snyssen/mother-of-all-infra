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
  # all_squash + anonuid/anongid are automatically appended based on the
  # export's uid unless already present.
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
      # Append all_squash + anonuid/anongid if not already present
      options =
        if lib.hasInfix "all_squash" optionsWithFsid then
          optionsWithFsid
        else
          "${optionsWithFsid},all_squash,anonuid=${toString export.uid},anongid=${toString export.uid}";
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

              name = lib.mkOption {
                type = lib.types.str;
                default = "nfs-${builtins.baseNameOf config.path}";
                description = ''
                  Name of the dedicated system user and group created for this
                  export. All NFS client requests are squashed to this account
                  (all_squash), confining server-side writes to a single
                  unprivileged identity. Defaults to ''${nfs-<basename>} derived
                  from the export path.
                '';
                example = "nfs-scrypted";
              };

              uid = lib.mkOption {
                type = lib.types.int;
                description = ''
                  UID and GID assigned to the dedicated system user and group
                  created for this export. This value is used as anonuid and
                  anongid in the NFS export options and must therefore be a
                  stable value known at build time. Choose an unused UID in the
                  system-user range (typically 400–499 on NixOS).
                '';
                example = 400;
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
                  provided. The all_squash, anonuid, and anongid parameters are
                  automatically appended based on the export's uid unless
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
    assertions =
      let
        uids = lib.map (e: e.uid) cfg.exports;
        names = lib.map (e: e.name) cfg.exports;
        hasDuplicates = xs: lib.length xs != lib.length (lib.unique xs);
      in
      [
        {
          assertion = !hasDuplicates uids;
          message = "nfsExports: each export must have a unique uid; found duplicates: ${
            lib.concatStringsSep ", " (
              lib.map toString (lib.filter (u: lib.count (x: x == u) uids > 1) (lib.unique uids))
            )
          }";
        }
        {
          assertion = !hasDuplicates names;
          message = "nfsExports: each export must have a unique name; found duplicates: ${
            lib.concatStringsSep ", " (lib.filter (n: lib.count (x: x == n) names > 1) (lib.unique names))
          }";
        }
      ];

    services.nfs.server = {
      enable = true;
      exports = exportsContent;
    };

    # Create a dedicated system user and group for each export.
    # NFS clients are squashed to this account (all_squash), which confines
    # all server-side writes to a single unprivileged identity while still
    # allowing any client user to read/write via the mount.
    users.users = lib.listToAttrs (
      lib.map (
        export:
        lib.nameValuePair export.name {
          uid = export.uid;
          group = export.name;
          isSystemUser = true;
          description = "NFS squash user for ${export.path}";
        }
      ) cfg.exports
    );

    users.groups = lib.listToAttrs (
      lib.map (export: lib.nameValuePair export.name { gid = export.uid; }) cfg.exports
    );

    # Ensure every exported directory exists and is owned by the squash user.
    # Mode 0755 allows the owner (squash user) to write and everyone to read/execute.
    # Since all NFS writes are squashed to the owner, any client can create files.
    systemd.tmpfiles.rules = lib.map (
      export: "d ${export.path} 0755 ${export.name} ${export.name} -"
    ) cfg.exports;

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
