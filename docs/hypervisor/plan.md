# Hypervisor Plan

This document describes the planned disk layout, network configuration, and repository architecture for the hypervisor host.

## Disk Inventory

All disks are addressed by their stable device IDs (`/dev/disk/by-id/...`) rather than kernel-assigned names (e.g. `/dev/sda`) to avoid device enumeration issues across reboots or hardware changes.

### OS Disk

| Count | Size | Type | Purpose |
|-------|------|------|---------|
| 1 | 500 GB | NVMe | NixOS root filesystem (single disk, btrfs + LUKS) |

The OS disk uses the existing [`single-btrfs-luks`](../../nix/modules/nixos/disko/layouts/single-btrfs-luks.nix) Disko layout: a GPT table with an ESP boot partition and a LUKS-encrypted btrfs volume containing the usual subvolumes (`/`, `/home`, `/nix`).

### VM Store

| Count | Size | Type |
|-------|------|------|
| 2 | 1 TB | NVMe |
| 1 | 500 GB | NVMe |

These three NVMe drives are combined into a **btrfs RAID1** volume used to store virtual machine images and their associated state. RAID1 in btrfs means all data and metadata are mirrored across at least two devices, providing redundancy while still using the combined pool capacity.

### Bulk Store

| Count | Size | Type |
|-------|------|------|
| 1 | 4 TB | HDD |
| 2 | 2 TB | HDD |

These three HDDs are combined into a second **btrfs RAID1** volume for bulk data storage (e.g. backups, media). The same RAID1 mirroring semantics apply.

## Disk Encryption & Unattended Boot

All LUKS-encrypted disks (OS, VM store, bulk store) are configured to unlock automatically at boot using a **keyfile stored on a USB stick**, allowing the machine to reboot without manual passphrase entry.

The mechanism is the same as described in [Full Disk Encryption](../nix/Full%20Disk%20Encryption.md):

1. A random keyfile is created on a VFAT-formatted USB key.
2. The keyfile is added as a LUKS unlock key (`cryptsetup luksAddKey`).
3. The Disko / initrd configuration mounts the USB key early in boot and reads the keyfile, with `fallbackToPassword = true` so a passphrase can still be used if the USB key is absent.

The USB key UUID(s) are listed in the host's Disko configuration under `usbKeysIds`.

## Network Configuration

### LAN Subnet & NFS

Services exported via NFS default to allowing the entire local subnet:

```
192.168.1.0/24
```

NFS exports are managed by the `nfsExports` NixOS module (`nix/modules/nixos/nfs-exports.nix`).  It exposes a declarative list of exports, each with a configurable path, client CIDR, and mount options.  The module-wide `nfsExports.lanCidr` option (default `192.168.1.0/24`) is applied to every export that does not specify its own `clients` list, and can be narrowed per-export when needed.

The hypervisor exports two bulk-storage directories for VM use:

| Export path | Clients |
|-------------|---------|
| `/mnt/storage/apps-vm` | `192.168.1.0/24` |
| `/mnt/storage/homeassistant-vm` | `192.168.1.0/24` |

These directories must exist on the host filesystem before clients attempt to mount them.  See [docs/nix/modules/nfs-exports.md](../nix/modules/nfs-exports.md) for full module documentation, firewall details, and client mount instructions.

### Network Bridge

Virtual machines need L2 access to the LAN. A bridge interface `br0` is created and the physical NIC is enslaved to it:

| Parameter | Value | Notes |
|-----------|-------|-------|
| Bridge name | `br0` | Used by VMs as their uplink |
| Physical NIC | `enp5s0` | Default; configurable in `nix/hosts/hypervisor/network.nix` |

**Rationale:** By bridging the physical NIC, any VM with a NIC attached to `br0` appears as a first-class host on the LAN. It can obtain its own DHCP lease or static IP without NAT or port-forwarding on the hypervisor. The host's own LAN IP is assigned to `br0` (not to the physical NIC directly).

The bridge is configured in `nix/hosts/hypervisor/network.nix` using `networking.bridges` and `networking.interfaces` (which generate systemd-networkd units because `networking.useNetworkd = true`):

```nix
networking.bridges.br0.interfaces = [ "enp5s0" ];
networking.interfaces = {
  br0.useDHCP = true;       # host LAN IP lives here
  "enp5s0".useDHCP = false; # enslaved NIC has no IP
};
```

**To change the physical NIC:** edit the `lanNic` variable at the top of `nix/hosts/hypervisor/network.nix` to match the actual interface name (discover it with `ip link` on the host). Common alternatives: `"enp3s0"`, `"eth0"`.

## Virtualisation — libvirtd

The hypervisor runs [libvirtd](https://libvirt.org/) to manage QEMU/KVM virtual machines.  The NixOS module lives at `nix/modules/nixos/libvirtd.nix` and is imported from `nix/hosts/hypervisor/configuration.nix` with:

```nix
libvirtd.enable = true;
```

Key options exposed by the module (all have sensible defaults):

| Option | Default | Description |
|--------|---------|-------------|
| `libvirtd.users` | `[ "snyssen" ]` | Users added to the `libvirtd` and `kvm` groups |
| `libvirtd.vmstorePool.enable` | `true` | Define and autostart the `vmstore` pool |
| `libvirtd.vmstorePool.path` | `/mnt/vmstore` | Target directory for the `vmstore` pool |

A systemd oneshot service (`libvirt-setup-vmstore-pool`) runs after `libvirtd.service` at every boot to ensure the pool is defined, set to autostart, and started.  The service declares `RequiresMountsFor = /mnt/vmstore`, so systemd guarantees the btrfs RAID1 volume is mounted before any pool operations are attempted.

### Verifying the storage pool

After a successful `nixos-rebuild switch`, confirm that libvirtd is running and the pool is active:

```sh
# Check the daemon
systemctl status libvirtd.service

# List pools (should show vmstore as active)
virsh pool-list --all

# Show pool details
virsh pool-info vmstore
```

Expected output:

```
Name:           vmstore
UUID:           <uuid>
State:          running
Persistent:     yes
Autostart:      yes
Capacity:       ...
Allocation:     ...
Available:      ...
```

### Creating a VM disk image (volume)

Use `virsh vol-create-as` to allocate a new disk inside the `vmstore` pool:

```sh
# Create a 20 GiB qcow2 disk for a new VM
virsh vol-create-as vmstore my-vm.qcow2 20G --format qcow2
```

The resulting image is stored at `/mnt/vmstore/my-vm.qcow2`.

### Listing and deleting volumes

```sh
# List all volumes in the pool
virsh vol-list vmstore

# Get detailed info on a single volume
virsh vol-info my-vm.qcow2 --pool vmstore

# Delete a volume (removes the file)
virsh vol-delete my-vm.qcow2 --pool vmstore
```

### Defining and starting a VM

The simplest way to define a VM interactively is `virt-install`:

```sh
# Example: install Debian from an ISO into the previously created disk
virt-install \
  --name my-vm \
  --memory 2048 \
  --vcpus 2 \
  --disk vol=vmstore/my-vm.qcow2 \
  --cdrom /mnt/bulk/isos/debian.iso \
  --network bridge=br0 \
  --os-variant debiantesting \
  --graphics vnc
```

The `--network bridge=br0` argument connects the VM directly to the LAN bridge, giving it a first-class LAN IP (see [Network Bridge](#network-bridge) above).

### Managing VMs with virsh

```sh
# List all VMs (running + defined)
virsh list --all

# Start a VM
virsh start my-vm

# Gracefully shut down a VM
virsh shutdown my-vm

# Force-off a VM
virsh destroy my-vm

# Remove the VM definition (does NOT delete its disk)
virsh undefine my-vm
```

### Permissions

The pool directory (`/mnt/vmstore`) is owned and writable by `root`.  libvirtd spawns QEMU processes under the `qemu-libvirtd` system user.  Members of the `libvirtd` group (configured via `libvirtd.users`) can interact with the system libvirt socket (`/run/libvirt/libvirt.sock`) without `sudo`.

If a permission error occurs when starting a VM, verify group membership:

```sh
id $USER   # should list libvirtd and kvm
```

---

## Repository Architecture

### NixOS Modules (`nix/modules/nixos/`)

Reusable system-level modules. Each file/directory exposes NixOS options that hosts can enable and configure:

| Module | Purpose |
|--------|---------|
| `disko/` | Disk partitioning and encryption layouts (wraps [Disko](https://github.com/nix-community/disko)) |
| `disko/layouts/single-btrfs-luks.nix` | Single OS disk: ESP + LUKS + btrfs subvolumes |
| `disko/layouts/btrfs-luks-raid1-pools.nix` | OS disk (same as above) + any number of configurable btrfs RAID1 storage pools: per-disk LUKS + btrfs RAID1, storage media type selects whether TRIM/discard is enabled |
| `cache.nix` | Nix binary cache configuration |
| `docker.nix` | Docker / container runtime |
| `grub.nix` | GRUB bootloader |
| `libvirtd.nix` | libvirtd / QEMU-KVM hypervisor daemon + vmstore pool |
| `locale.nix` | Locale and timezone |
| `nfs-exports.nix` | NFS server with a declarative, per-export list of exported directories |
| `nvidia.nix` | NVIDIA GPU drivers |
| `sops.nix` | [SOPS](https://github.com/getsops/sops) secrets management |
| `tailscale.nix` | Tailscale VPN mesh |
| `traefik.nix` | Traefik reverse proxy |
| `user.nix` | User account creation |

### Home Manager Modules (`nix/modules/home/`)

User-level configuration managed by [Home Manager](https://github.com/nix-community/home-manager):

| Module | Purpose |
|--------|---------|
| `shell/` | Fish / Zsh shell environment |
| `git.nix` | Git configuration |
| `vscode.nix` | VS Code extensions and settings |
| `firefox.nix` | Firefox configuration |

### Hosts (`nix/hosts/`)

Each subdirectory is a standalone NixOS host. The typical structure is:

```
nix/hosts/<hostname>/
├── configuration.nix          # Main system config; imports modules and sets options
├── hardware-configuration.nix # Auto-generated hardware info (nixos-generate-config)
├── users/
│   └── <username>.nix         # Per-user Home Manager config for this host
└── data/
    └── secrets.yaml           # SOPS-encrypted secrets for this host
```

Current hosts:

| Host | Role |
|------|------|
| `sninful` | Primary desktop / daily driver |
| `purplehaze` | Framework laptop |
| `blackfog` | Secondary desktop |
| `gaming` | Gaming PC (multi-disk LUKS setup) |
| `ingress` | Remote VPS (Gandi Cloud) — reverse proxy / ingress |
| `hypervisor` | KVM hypervisor with btrfs RAID1 VM store |

The **hypervisor** host lives at `nix/hosts/hypervisor/` and follows the same structure as the other hosts.

### Flake & Blueprint (`flake.nix`)

The flake uses [numtide/blueprint](https://github.com/numtide/blueprint) for scaffolding. Each host in `nix/hosts/` is automatically exposed as a `nixosConfiguration` output. Shared overlays and package overrides (e.g. `pkgs.unstable`) are declared in the flake and passed down to all hosts.
