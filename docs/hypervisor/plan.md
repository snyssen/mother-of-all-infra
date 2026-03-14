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

This can be narrowed per-export in the NixOS `services.nfs.server.exports` configuration.

### Network Bridge

Virtual machines need L2 access to the LAN. A bridge interface `br0` is created and the physical NIC is enslaved to it:

| Parameter | Value | Notes |
|-----------|-------|-------|
| Bridge name | `br0` | Used by VMs as their uplink |
| Physical NIC | `enp3s0` | Default; configurable in host config |

The bridge is configured in NixOS via `networking.bridges` and `networking.interfaces`. The physical interface name `enp3s0` is the expected default but can be overridden per-machine in the host's `configuration.nix` (or a dedicated hardware configuration file) if the actual interface name differs.

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
| `locale.nix` | Locale and timezone |
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

The **hypervisor** host will be added as `nix/hosts/hypervisor/` following the same structure, with a new Disko layout covering the multi-disk btrfs RAID1 configuration described above.

### Flake & Blueprint (`flake.nix`)

The flake uses [numtide/blueprint](https://github.com/numtide/blueprint) for scaffolding. Each host in `nix/hosts/` is automatically exposed as a `nixosConfiguration` output. Shared overlays and package overrides (e.g. `pkgs.unstable`) are declared in the flake and passed down to all hosts.
