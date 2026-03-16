# NixOS NFS Exports Module

The `nfsExports` NixOS module (`nix/modules/nixos/nfs-exports.nix`) configures an NFS server with a declarative, per-export list of exported directories.  It is primarily intended for the hypervisor host, where VM guests mount bulk-storage directories over NFS, but it can be used on any NixOS host.

## Features

- Declarative list of NFS exports (paths, client CIDRs, and mount options).
- Module-wide default LAN CIDR applied to every export that does not specify its own client list.
- Automatic firewall rules for ports 111 (rpcbind) and 2049 (NFS) on both TCP and UDP.

## Module Options

### `nfsExports.enable`

- **Type**: `boolean`
- **Default**: `false`
- **Description**: Enables the NFS server and applies the configured exports.

---

### `nfsExports.lanCidr`

- **Type**: `string`
- **Default**: `"192.168.1.0/24"`
- **Description**: Default LAN CIDR used as the allowed client range for any export that does not define its own `clients` list.  Change this if your local subnet differs from `192.168.1.0/24`.

---

### `nfsExports.exports`

- **Type**: `list of submodules`
- **Default**: `[]`
- **Description**: List of directories to export via NFS.  Each entry is a submodule with the following options:

#### `nfsExports.exports[*].path`

- **Type**: `string`
- **Description**: Absolute path of the directory to export.
- **Example**: `"/mnt/storage/apps-vm"`

#### `nfsExports.exports[*].clients`

- **Type**: `list of strings`
- **Default**: `[]` *(uses `nfsExports.lanCidr`)*
- **Description**: CIDRs or hostnames that are allowed to mount this export.  When the list is empty the module-wide `lanCidr` is used.
- **Example**: `[ "192.168.1.0/24" "10.0.0.5" ]`

#### `nfsExports.exports[*].options`

- **Type**: `string`
- **Default**: `"rw,sync,no_subtree_check"`
- **Description**: NFS export options placed inside the parentheses for each client entry.  See `exports(5)` for the full list of options.
- **Example**: `"ro,sync,no_subtree_check"`

## Usage Example

```nix
# In nix/hosts/<hostname>/configuration.nix

imports = [
  flake.modules.nixos.nfs-exports
];

nfsExports = {
  enable = true;
  # lanCidr defaults to "192.168.1.0/24"; override if needed
  exports = [
    # Shared bulk-storage directory for the apps VM — read/write from the LAN
    { path = "/mnt/storage/apps-vm"; }

    # Home Assistant VM storage — read/write from the LAN
    { path = "/mnt/storage/homeassistant-vm"; }

    # Read-only export restricted to a single host
    {
      path    = "/mnt/storage/isos";
      clients = [ "192.168.1.42" ];
      options = "ro,sync,no_subtree_check";
    }
  ];
};
```

The generated `/etc/exports` content for the first two entries (with the default LAN CIDR) would be:

```
/mnt/storage/apps-vm            192.168.1.0/24(rw,sync,no_subtree_check)
/mnt/storage/homeassistant-vm   192.168.1.0/24(rw,sync,no_subtree_check)
```

## Firewall

When `nfsExports.enable = true`, the following firewall rules are applied automatically:

| Port | Protocol | Service |
|------|----------|---------|
| 111  | TCP + UDP | rpcbind / portmapper |
| 2049 | TCP + UDP | NFS |

No additional firewall configuration is required for NFSv3 or NFSv4 clients.

## Prerequisites

The exported directories **must exist on the host** before clients attempt to mount them.  Create them manually or via another NixOS option such as `systemd.tmpfiles.rules`:

```nix
systemd.tmpfiles.rules = [
  "d /mnt/storage/apps-vm          0755 root root -"
  "d /mnt/storage/homeassistant-vm 0755 root root -"
];
```

## Verifying the Configuration

After a successful `nixos-rebuild switch`, verify that the NFS server is running and the exports are active:

```sh
# Check the service
systemctl status nfs-server.service

# Show the active export table
exportfs -v

# From a client on the LAN, list available exports
showmount -e <hypervisor-ip>
```

Expected output of `exportfs -v`:

```
/mnt/storage/apps-vm
                192.168.1.0/24(rw,sync,wdelay,hide,no_subtree_check,sec=sys,rw,secure,root_squash,no_all_squash)
/mnt/storage/homeassistant-vm
                192.168.1.0/24(rw,sync,wdelay,hide,no_subtree_check,sec=sys,rw,secure,root_squash,no_all_squash)
```

## Mounting from a Client

On a Linux client within the allowed CIDR, mount an export with:

```sh
# NFSv4 mount (preferred)
mount -t nfs4 <hypervisor-ip>:/mnt/storage/apps-vm /mnt/apps-vm

# Or via /etc/fstab for a persistent mount
<hypervisor-ip>:/mnt/storage/apps-vm  /mnt/apps-vm  nfs4  defaults  0 0
```

On a NixOS client, use `fileSystems`:

```nix
fileSystems."/mnt/apps-vm" = {
  device  = "<hypervisor-ip>:/mnt/storage/apps-vm";
  fsType  = "nfs4";
  options = [ "defaults" ];
};
```

## Related Documentation

- [Hypervisor Plan](../../hypervisor/plan.md) — disk layout, network, and NFS conventions for the hypervisor host
- [NixOS NFS server options](https://search.nixos.org/options?query=services.nfs.server) — upstream NixOS options
