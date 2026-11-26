# Hypervisor Architecture

This document describes the disks, network, virtualisation and VM provisioning of the production hypervisor, `hypervisor-01` (configuration in `nix/hosts/hypervisor-01/`). It runs the `apps-01` NixOS VM, which has carried production since the cutover finished on 2026-11-23, alongside the `haos` and `technitium-secondary` VMs.

For day-to-day procedures (VM lifecycle, scrubs, disk replacement) see [Hypervisor Operations](../operations/hypervisor.md); for building and deploying NixOS VMs see [Deploying NixOS VMs](../operations/vm-deployment.md).

For where the host configuration and modules sit in the repository, see [Repository layout](repository.md).

## Disk Inventory

All disks are addressed by their stable device IDs (`/dev/disk/by-id/...`) rather than kernel-assigned names (e.g. `/dev/sda`) to avoid device enumeration issues across reboots or hardware changes. The lists below mirror the `disko` block of `nix/hosts/hypervisor-01/configuration.nix`, which is authoritative.

### OS Disk

| Count | Disk | Type | Purpose |
|-------|------|------|---------|
| 1 | SPCC M.2 PCIe SSD (`nvme-SPCC_M.2_PCIe_SSD_…`) | NVMe | NixOS root filesystem (single disk, btrfs + LUKS, with a swap file) |

The OS disk is set up by the `btrfs-luks-raid1-pools` Disko layout (`nix/modules/nixos/disko/layouts/btrfs-luks-raid1-pools.nix`), whose OS part is the same as `single-btrfs-luks`: a GPT table with an ESP boot partition and a LUKS-encrypted btrfs volume containing the usual subvolumes (`/`, `/home`, `/nix`, and `/swap` since `swap.enable = true`).

### VM Store (`vmstore`, mounted at `/mnt/vmstore`)

| Index | Size | Disk | Type |
|-------|------|------|------|
| 0 | 1 TB | Kingston SNV3S1000G | NVMe |
| 1 | 1 TB | Micron 2300 | NVMe |
| 2 | 500 GB | WD (`WDS500G2B0B`) | SATA SSD |

These three SSDs are combined into a **btrfs RAID1** volume (~1.25 TB usable) used to store virtual machine images and their associated state. RAID1 in btrfs means all data and metadata are mirrored across two devices, providing redundancy while still using the combined pool capacity. The pool is declared with `storageMedia = "ssd"`, so its LUKS containers allow discards (TRIM).

### Bulk Store (`bulk`, mounted at `/mnt/bulk`)

| Index | Size | Disk | Type |
|-------|------|------|------|
| 0 | 16 TB | Seagate Exos (`ST16000NM000J`) | HDD |
| 1 | 12 TB | Seagate Exos X14 (`ST12000NM0538`) | HDD |
| 2 | 8 TB | Seagate IronWolf (`ST8000VN004`) | HDD |
| 3 | 2 TB | Seagate IronWolf (`ST2000VN004`) | HDD |
| 4 | 2 TB | WD Blue (`WD20EZRZ`) | HDD |

These five HDDs are combined into a second **btrfs RAID1** volume for bulk data storage (`apps-01`'s media and other large data, exported over NFS, see below). The same RAID1 mirroring semantics apply.

The index matters: it determines each disk's GPT partition label and LUKS mapper name, see [Storage Layout Reference](../operations/hypervisor.md#storage-layout-reference).

## Disk Encryption & Unattended Boot

All LUKS-encrypted disks (OS, VM store, bulk store) are configured to unlock automatically at boot using a **keyfile stored on a USB stick**, allowing the machine to reboot without manual passphrase entry.

The mechanism is the same as described in [Full Disk Encryption](../operations/disk-encryption.md):

1. A random keyfile is created on a VFAT-formatted USB key. It is named after the host (`keyFilename` defaults to `system.name`): `/key/hypervisor-01`.
2. The keyfile is added as a LUKS unlock key (`cryptsetup luksAddKey`).
3. The initrd mounts the USB key early in boot and reads the keyfile, retrying `usbMount.attempts` times (5 on hypervisor-01, as one stick is slow to appear). If no key is found, cryptsetup falls back to a passphrase prompt on the console.

The USB key UUIDs are listed in the host's Disko configuration under `usbKeysIds`; hypervisor-01 accepts any of three sticks.

The VMs' own disks are encrypted too, but unlock differently: each gets a LUKS key file kept on the hypervisor and passed in over virtiofs. See "VM Disk Encryption & LUKS Key Access" in [Deploying NixOS VMs](../operations/vm-deployment.md).

## Network Configuration

### LAN Address & NFS

The host's LAN address is static: `192.168.1.13/24` on `br0` (see the LAN addressing table in [Network](network.md)).

NFS exports are managed by the `nfsExports` NixOS module (`nix/modules/nixos/nfs-exports.nix`). It exposes a declarative list of exports, each with a configurable path, client CIDR, and mount options. The module-wide `nfsExports.lanCidr` option (default `192.168.1.0/24`) is applied to every export that does not specify its own `clients` list; hypervisor-01 sets it to the tailnet range, `100.64.0.0/10`.

The hypervisor exports one bulk-storage directory, for `apps-01`:

| Export path | Clients |
|-------------|---------|
| `/mnt/bulk/apps` | `100.64.0.0/10` (tailnet), `192.168.1.10/32` (`apps-01`'s LAN address) |

`apps-01` mounts it over the LAN, by the hypervisor's static IP, so the mount survives tailscaled or DNS being down. Only `apps-01`'s own address is allowed rather than the whole `/24`, since exports get `no_root_squash`.

The directory must exist on the host filesystem before clients attempt to mount it. See [the nfs-exports module](../modules/nfs-exports.md) for full module documentation, firewall details, and client mount instructions.

### Network Bridge

Virtual machines need L2 access to the LAN. A bridge interface `br0` is created and the physical NIC is enslaved to it:

| Parameter | Value | Notes |
|-----------|-------|-------|
| Bridge name | `br0` | Used by VMs as their uplink; holds the host's static IP |
| Physical NIC | `lan0` | Named by its MAC address, in `nix/hosts/hypervisor-01/network.nix` |

**Rationale:** By bridging the physical NIC, any VM with a NIC attached to `br0` appears as a first-class host on the LAN. It can obtain its own DHCP lease or static IP without NAT or port-forwarding on the hypervisor. The host's own LAN IP is assigned to `br0` (not to the physical NIC directly).

The bridge is configured in `nix/hosts/hypervisor-01/network.nix` using `networking.bridges` and `networking.interfaces` (which generate systemd-networkd units because `networking.useNetworkd = true`), plus a `.link` unit that names the NIC and a `.network` unit with the static address:

```nix
let
  lanNic = "lan0";
  macAddress = "74:56:3c:cc:a2:3b"; # `ip -br link`
in
{
  networking.bridges.br0.interfaces = [ lanNic ];
  networking.interfaces = {
    br0.useDHCP = false;          # static address, set in 20-br0
    "${lanNic}".useDHCP = false;  # enslaved NIC has no IP
  };
  systemd.network.links."10-${lanNic}" = {
    matchConfig.PermanentMACAddress = macAddress;
    linkConfig.Name = lanNic;
  };
  systemd.network.networks."20-br0".networkConfig.Address = "192.168.1.13/24"; # plus gateway and DNS
}
```

**Why the NIC is named by MAC:** the kernel's `enpXs0` name comes from the PCIe bus number, which shifts when a disk is added to or removed from an M.2 slot. Losing the NIC from the bridge cuts every VM off the LAN while the host itself stays reachable.

**To change the physical NIC:** edit the `macAddress` variable at the top of `nix/hosts/hypervisor-01/network.nix` to the new NIC's permanent MAC (discover it with `ip -br link` on the host). A changed `macAddress` only applies at the next boot.

## Virtualisation — libvirtd

The hypervisor runs [libvirtd](https://libvirt.org/) to manage QEMU/KVM virtual machines.  The NixOS module lives at `nix/modules/nixos/libvirtd.nix` (documented in [the libvirtd module](../modules/libvirtd.md)) and is enabled from `nix/hosts/hypervisor-01/configuration.nix` with:

```nix
libvirtd = {
  enable = true;
  vncLanAccess = true;
};
```

Key options exposed by the module:

| Option | Default | Description |
|--------|---------|-------------|
| `libvirtd.users` | `[ "snyssen" ]` | Users added to the `libvirtd` and `kvm` groups |
| `libvirtd.vncLanAccess` | `false` | Opens TCP 5900–5910 for VNC from the LAN (otherwise SSH tunnel only) |

The host also passes the CPU's Intel iGPU (QuickSync) through to `apps-01` for Jellyfin: IOMMU is on (`intel_iommu=on iommu=pt`), `i915` is blacklisted and `vfio-pci` claims the iGPU in the initrd.

> **Important:** Individual VM lifecycle (creation, disk provisioning, domain definition, autostart) is **fully managed by Ansible**, not NixOS/NixVirt.  The NixOS module only configures the libvirtd daemon, user group memberships, and system packages.  See [VM definitions](#vm-definitions) below.

### Verifying libvirtd is running

```sh
# Check the daemon
systemctl status libvirtd.service

# List all defined VMs
virsh list --all
```

---

## Ansible — libvirt VM provisioning

VM provisioning and lifecycle management is handled by the `libvirt_provision` Ansible role invoked from the `libvirt-provision` playbook. NixOS VMs additionally have their disk images built by the `libvirt-image-build` playbook first; see [Deploying NixOS VMs](../operations/vm-deployment.md).

### VM definitions

VMs are defined in `ansible/hosts/host_vars/hypervisor-01/vars.yml`.  Each entry in `libvirt_vms` describes one VM:

```yaml
libvirt_vms:
  - name: haos               # VM name / directory key
    state: present           # optional: present (default) or absent
    vcpu: 1                  # vCPUs
    ram_mb: 2048             # RAM in MiB
    mac_address: "52:54:00:12:34:56"  # static MAC for DHCP reservation
    disk_gb: 64              # optional: only enlarges, never shrinks
    disk_image:              # mutually exclusive with iso_image
      url: "https://..."     # download URL, used only when nothing is at dest
      dest: "/mnt/vmstore/haos/haos.qcow2"  # final path on host
      checksum: "sha256:..." # optional
      # extract: true        # optional; auto-detected from extension
      # build: true          # NixOS VMs only: build this image with libvirt-image-build
    # virtiofs_luks_key:     # NixOS VMs: share /var/lib/vm-keys/<name>/ over virtiofs
    #   enable: true
    #   tag: keys            # optional, default "keys"
    usb_devices:
      - vendor_id: "0x303a"
        product_id: "0x831a"
    # pci_devices:           # PCI passthrough (apps-01's iGPU)
    #   - domain: "0x0000"
    #     bus: "0x00"
    #     slot: "0x02"
    #     function: "0x0"
```

For ISO-based VMs use `iso_image` instead of `disk_image`:

```yaml
    iso_image:
      url: "https://..."
      dest: "/mnt/vmstore/testvm/installer.iso"
```

The VMs defined today are `haos` (Home Assistant OS appliance, with its Zigbee/Thread dongle passed through), `technitium-secondary` (NixOS, DNS secondary) and `apps-01` (NixOS, the app server, with the iGPU passed through).

The `state` field controls the VM lifecycle:

| Value | Behaviour |
|-------|-----------|
| `present` (default) | Provisions/updates the VM as described |
| `absent` | Destroys (force-off) the VM, undefines it from libvirt, and **permanently deletes** its entire directory under `libvirt_vmstore_root` (default: `/mnt/vmstore`) and its LUKS key directory under `libvirt_vm_keys_root` (default: `/var/lib/vm-keys`) |

> **Warning:** `state: absent` is destructive and irreversible. All disk images, keys and configuration files for the VM will be deleted.

### Running the playbook

```sh
just hypervisor-provision-vms hypervisor-01
```

The hypervisor is a required first argument, so the recipe never acts on one by default. Extra arguments are passed to `ansible-playbook`; to provision only some VMs, add `-e libvirt_vms_only=<vm>[,<vm>...]`.

Or directly:

```sh
cd ansible
ansible-playbook playbooks/libvirt-provision.ansible.yml -i hosts/prod.yml -e libvirt_hypervisor=hypervisor-01
```

### What the playbook does (per VM)

**When `state: present` (default):**

1. Creates `/mnt/vmstore/<name>/` directory
2. With `virtiofs_luks_key.enable`, creates `/var/lib/vm-keys/<name>/` and generates a `luks.key` there **only if none exists** (a built NixOS image brings its own key, copied there by the image build)
3. Downloads the disk/ISO image (skipped if already present)
4. Extracts archives (`.xz`, `.gz`, `.bz2`, `.zip`, `.tar.*`) automatically
5. Resizes the disk image to `disk_gb` if larger than current virtual size
6. Creates an empty qcow2 disk for ISO-based VMs (if absent)
7. Renders a Jinja2 libvirt domain XML template and saves it to `/mnt/vmstore/<name>/domain.xml`
8. If the XML changed and the domain exists: shuts the VM down (force-off after 3 minutes), undefines it, and redefines it with `virsh define`; a new domain is simply defined
9. Sets the domain to autostart
10. Starts the domain (idempotent — skips if already running)

> **Note:** a change to a VM's definition therefore restarts that VM on the next run.

**When `state: absent`:**

1. Checks whether the libvirt domain exists
2. If the domain is running, force-stops it (`virsh destroy`)
3. Undefines the domain from libvirt (`virsh undefine --nvram`)
4. Removes the entire `/mnt/vmstore/<name>/` directory and all disk files
5. Removes `/var/lib/vm-keys/<name>/`

### Removing a VM

To remove a VM, set `state: absent` in its entry in `ansible/hosts/host_vars/hypervisor-01/vars.yml`:

```yaml
libvirt_vms:
  - name: myvm
    state: absent
```

Then run the playbook:

```sh
just hypervisor-provision-vms hypervisor-01
```

> **Warning:** This operation is **irreversible**. The VM's disk directory (e.g. `/mnt/vmstore/myvm/`) will be permanently deleted. Back up any data before proceeding.

The role is idempotent: if the VM no longer exists when the playbook runs again, all `absent` tasks are safely skipped.

### Domain XML templates

Jinja2 templates are stored in `ansible/roles/libvirt_provision/templates/`:

| Template | Used for |
|----------|----------|
| `domain-disk-image.xml.j2` | qcow2 images: appliances (e.g. HAOS) and built NixOS VMs |
| `domain-iso.xml.j2` | ISO installer-based VMs |

### Role defaults

| Variable | Default | Description |
|----------|---------|-------------|
| `libvirt_vmstore_root` | `/mnt/vmstore` | Root path for VM disks/assets |
| `libvirt_vm_keys_root` | `/var/lib/vm-keys` | Root path for per-VM LUKS key files shared over virtiofs |
| `libvirt_default_bridge` | `br0` | Default network bridge |
| `libvirt_uri` | `qemu:///system` | libvirt connection URI |
| `libvirt_ovmf_loader` | `/run/libvirt/nix-ovmf/edk2-x86_64-code.fd` | OVMF UEFI firmware |

### Managing VMs manually

```sh
# List all VMs (running + defined)
virsh list --all

# Start a VM
virsh start haos

# Gracefully shut down a VM
virsh shutdown haos

# Force-off a VM
virsh destroy haos

# Remove the VM definition (does NOT delete its disk)
virsh undefine haos --nvram
```

The `just hypervisor-vm-*` recipes wrap these over SSH, see [Hypervisor Operations](../operations/hypervisor.md#quick-reference).

### Permissions

The pool directory (`/mnt/vmstore`) is owned and writable by `root`.  libvirtd spawns QEMU processes under the `qemu-libvirtd` system user.  Members of the `libvirtd` group (configured via `libvirtd.users`) can interact with the system libvirt socket (`/run/libvirt/libvirt.sock`) without `sudo`.
