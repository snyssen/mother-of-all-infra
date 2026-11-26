# NixOS NFS Exports Module

The `nfsExports` NixOS module (`nix/modules/nixos/nfs-exports.nix`) configures an NFS server from a declarative list of exported directories. It is used on hypervisor-01, which exports its HDD-backed bulk storage to the apps-01 VM, but it works on any NixOS host.

## Features

- Declarative list of NFS exports (path, allowed clients, export options).
- A module-wide default client range for exports that do not list their own clients.
- A unique `fsid` per export and `no_root_squash`, appended automatically unless the options already set them.
- Exported directories created via `systemd-tmpfiles`, mode `0777` and owner `root:root` by default (configurable per export).
- Firewall opened for ports 111 (rpcbind) and 2049 (NFS), TCP and UDP. That is enough for NFSv4; NFSv3 also needs mountd, statd and lockd, which the module does not open (see [Firewall](#firewall)).

## Module Options

### `nfsExports.enable`

- **Type**: `boolean`
- **Default**: `false`
- **Description**: Enables the NFS server (`services.nfs.server`) and applies the configured exports.

---

### `nfsExports.lanCidr`

- **Type**: `string`
- **Default**: `"192.168.1.0/24"`
- **Description**: Allowed client range for any export whose `clients` list is empty. Despite the name it can be any range; hypervisor-01 sets it to the tailnet, `100.64.0.0/10`.

---

### `nfsExports.exports`

- **Type**: `list of submodules`
- **Default**: `[]`
- **Description**: Directories to export. Each entry takes the options below.

#### `nfsExports.exports[*].path`

- **Type**: `string`
- **Description**: Absolute path of the directory to export.
- **Example**: `"/mnt/bulk/apps"`

#### `nfsExports.exports[*].clients`

- **Type**: `list of strings`
- **Default**: `[]` *(uses `nfsExports.lanCidr`)*
- **Description**: CIDRs or hostnames allowed to mount this export. Every client gets the same `options`.
- **Example**: `[ "100.64.0.0/10" "192.168.1.10/32" ]`

#### `nfsExports.exports[*].options`

- **Type**: `string`
- **Default**: `"rw,sync,no_subtree_check"`
- **Description**: Export options placed inside the parentheses for each client, see `exports(5)`. The module appends two options to them, described below.
- **Example**: `"ro,sync,no_subtree_check"`

The module appends `fsid=<n>`, where `<n>` is the export's 1-based position in the list, unless the options already contain `fsid=`; NFSv4 needs a unique `fsid` per export. Reordering the list therefore changes the `fsid`s. It also appends `no_root_squash` unless the options already contain any `squash` option (`root_squash`, `no_root_squash`, `all_squash`, `no_all_squash`), so clients can chown and manage permissions inside the export as root.

> [!WARNING]
> With `no_root_squash`, root on any allowed client is root on the exported directory. Keep `clients` as narrow as possible, or add `root_squash` to `options` when clients do not need it.

#### `nfsExports.exports[*].dirMode`

- **Type**: `string`
- **Default**: `"0777"`
- **Description**: Mode of the exported directory as created by `systemd-tmpfiles`. The permissive default lets any client UID read, write and set its own permissions inside the export.
- **Example**: `"0755"`

#### `nfsExports.exports[*].dirOwner`

- **Type**: `string`
- **Default**: `"root"`
- **Description**: Owner of the exported directory on the server.

#### `nfsExports.exports[*].dirGroup`

- **Type**: `string`
- **Default**: `"root"`
- **Description**: Group of the exported directory on the server.

## Usage Example

hypervisor-01 (`nix/hosts/hypervisor-01/configuration.nix`) exports one directory, allowed from the whole tailnet and from apps-01's LAN address:

```nix
imports = [
  flake.modules.nixos.nfs-exports
];

nfsExports = {
  enable = true;
  lanCidr = "100.64.0.0/10"; # Tailnet IP range
  exports = [
    {
      path = "/mnt/bulk/apps";
      # apps-01 mounts this over the LAN (by this host's static 192.168.1.13), so
      # the mount survives tailscaled or DNS being down. Only apps-01's own LAN
      # address is allowed, not the whole /24: exports get no_root_squash.
      clients = [
        "100.64.0.0/10"
        "192.168.1.10/32"
      ];
    }
  ];
};
```

This generates the following `/etc/exports` line:

```text
/mnt/bulk/apps  100.64.0.0/10(rw,sync,no_subtree_check,fsid=1,no_root_squash) 192.168.1.10/32(rw,sync,no_subtree_check,fsid=1,no_root_squash)
```

and the tmpfiles rule `d /mnt/bulk/apps 0777 root root -`.

## Firewall

When `nfsExports.enable = true`, the module opens these ports on every interface:

| Port | Protocol | Service |
| --- | --- | --- |
| 111 | TCP + UDP | rpcbind / portmapper |
| 2049 | TCP + UDP | NFS |

That is all an NFSv4 client needs. NFSv3 additionally uses mountd, statd and lockd, which listen on dynamic ports the module neither pins nor opens, so NFSv3 clients will not get through the firewall.

The firewall does not restrict sources: which hosts may mount is decided by each export's `clients` list.

## Exported directories

Each exported directory is created by `systemd-tmpfiles` with its `dirMode`, `dirOwner` and `dirGroup` (`0777 root:root` unless set). A `d` rule creates the directory when it is missing and adjusts mode and ownership of an existing one; it does not touch the contents. It works for directories on separately mounted pools such as `/mnt/bulk`, provided the mount is up when tmpfiles runs.

## Verifying the Configuration

After a switch, check that the NFS server is running and the exports are active:

```sh
# Check the service
systemctl status nfs-server.service

# Show the active export table, with the options the kernel applied
exportfs -v

# From an allowed client, list available exports
showmount -e <server-ip>
```

## Mounting from a Client

On NixOS clients, use the companion `nfsMounts` module (`nix/modules/nixos/nfs-mounts.nix`), which generates systemd mount and automount units. apps-01 mounts the hypervisor export like this:

```nix
nfsMounts.enable = true;
nfsMounts.mounts.bulk = {
  path = "/mnt/bulk";
  host = "192.168.1.13";       # hypervisor-01's static LAN IP, so DNS is not needed
  remotePath = "/mnt/bulk/apps";
};
```

On any other Linux client within the allowed range:

```sh
mount -t nfs4 <server-ip>:/mnt/bulk/apps /mnt/bulk
```

## Related Documentation

- [Hypervisor](../architecture/hypervisor.md): disk layout, network and storage of the hypervisor host
- [NixOS NFS server options](https://search.nixos.org/options?query=services.nfs.server): upstream NixOS options
