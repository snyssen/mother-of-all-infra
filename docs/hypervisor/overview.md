# Hypervisor Operations

This document covers day-to-day operational procedures for the hypervisor host: VM lifecycle management, btrfs storage health checks, disk expansion and replacement, and common troubleshooting steps.

> **Architectural reference:** See [plan.md](plan.md) for the disk layout, network configuration, Disko/LUKS design decisions, and repository architecture overview.

---

## Quick Reference

All helpers below are available through the root `justfile`.  Run `just --list` to see them, or use the table as a cheat-sheet.

### VM helpers

| Command | Description |
|---------|-------------|
| `just hypervisor-ssh` | Open an interactive SSH session on the hypervisor |
| `just hypervisor-vm-list` | List all defined VMs (running and stopped) |
| `just hypervisor-vm-start <vm>` | Start a VM |
| `just hypervisor-vm-stop <vm>` | Gracefully shut down a VM |
| `just hypervisor-vm-reboot <vm>` | Reboot a VM |
| `just hypervisor-vm-destroy <vm>` | Force-off a VM (hard power cut) |
| `just hypervisor-vm-console <vm>` | Open a serial console to a VM |
| `just hypervisor-vm-info <vm>` | Show detailed VM info |
| `just hypervisor-provision-vms` | Re-run the Ansible libvirt provisioning playbook |

### btrfs / storage helpers

| Command | Description |
|---------|-------------|
| `just hypervisor-btrfs-scrub <pool>` | Start a btrfs scrub and wait for it to finish |
| `just hypervisor-btrfs-scrub-status <pool>` | Show status of the last scrub |
| `just hypervisor-btrfs-usage <pool>` | Show filesystem usage breakdown |
| `just hypervisor-btrfs-stats <pool>` | Show per-device I/O error counters |
| `just hypervisor-btrfs-devices <pool>` | Show device listing and filesystem UUID |

`<pool>` is the pool mount-point suffix (e.g. `vmstore` → `/mnt/vmstore`, `bulk` → `/mnt/bulk`).

---

## VM Lifecycle Management

### Using the just helpers

```sh
# See all defined VMs and their state
just hypervisor-vm-list

# Start the Home Assistant OS appliance
just hypervisor-vm-start haos

# Gracefully shut it down
just hypervisor-vm-stop haos

# If shutdown hangs, force-off the VM
just hypervisor-vm-destroy haos
```

### Using virsh directly

SSH into the hypervisor first (`just hypervisor-ssh`) and run `virsh` commands:

```sh
# List all VMs
virsh list --all

# Start / stop / reboot
virsh start haos
virsh shutdown haos
virsh reboot haos

# Force-off (equivalent to pulling the power)
virsh destroy haos

# Remove the VM definition without deleting its disk
virsh undefine haos --nvram

# Show detailed VM info
virsh dominfo haos
```

### Accessing a VM console

VMs are configured with a serial console, which lets you interact without a graphical session:

```sh
# From your workstation (press Ctrl-] to exit)
just hypervisor-vm-console haos

# Or directly after SSH-ing in
virsh console haos
```

VNC access is also enabled on the LAN (`libvirtd.vncLanAccess = true`).  Use `virt-manager` or any VNC client; the port for each VM is shown in `virsh dumpxml <vm> | grep vnc`.

---

## VM Provisioning via Ansible

All VM definitions live in `ansible/hosts/host_vars/hypervisor/vars.yml`.  The `libvirt_provision` role is idempotent — re-running the playbook is safe.

### Adding a new VM

1. Append an entry to `libvirt_vms` in `ansible/hosts/host_vars/hypervisor/vars.yml`.  See [plan.md — VM definitions](plan.md#vm-definitions) for the full schema.

   ```yaml
   libvirt_vms:
     - name: myvm
       vcpu: 2
       ram_mb: 2048
       mac_address: "52:54:00:ab:cd:ef"
       disk_gb: 32
       disk_image:
         url: "https://example.com/myvm.qcow2.xz"
         dest: "/mnt/vmstore/myvm/myvm.qcow2"
         checksum: "sha256:..."
   ```

### USB passthrough for Zigbee/Thread dongles

To pass a USB adapter through to Home Assistant, add `usb_devices` to the `haos` VM definition in `ansible/hosts/host_vars/hypervisor/vars.yml`.

Example:

```yaml
- name: haos
  # ...
  usb_devices:
    - vendor_id: "0x1a86"
      product_id: "0x7523"
```

#### How to find `vendor_id` and `product_id`

On the machine where the dongle is currently plugged in:

```sh
# List USB devices
lsusb
```

If `lsusb` is unavailable, install `usbutils` (or run it ad-hoc with Nix):

```sh
nix shell nixpkgs#usbutils -c lsusb
```

Find the dongle line, for example:

```text
Bus 001 Device 008: ID 1a86:7523 QinHeng Electronics CH340 serial converter
```

In this example:

- `vendor_id` = `0x1a86`
- `product_id` = `0x7523`

You can also query one exact device:

```sh
lsusb -d 1a86:7523
```

Or use `udevadm` (useful for scripted checks):

```sh
udevadm info --name=/dev/ttyUSB0 | grep -E 'ID_VENDOR_ID|ID_MODEL_ID'
```

You can also read IDs directly from sysfs for a USB serial adapter:

```sh
readlink -f /sys/class/tty/ttyUSB0/device/../idVendor
cat /sys/class/tty/ttyUSB0/device/../idVendor
cat /sys/class/tty/ttyUSB0/device/../idProduct
```

Expected output:

```text
E: ID_VENDOR_ID=1a86
E: ID_MODEL_ID=7523
```

Use those values in `vars.yml` with the `0x` prefix.

> Important: passthrough happens on the hypervisor host.  If you discovered IDs on your workstation, move the dongle to the hypervisor and verify with `lsusb` there as well (`just hypervisor-ssh`, then `lsusb`) before running provisioning.

1. Run the playbook:

   ```sh
   just hypervisor-provision-vms
   ```

### Removing a VM

> **Warning:** `state: absent` permanently deletes all disk images under `/mnt/vmstore/<name>/`.  Back up any data before proceeding.

1. Set `state: absent` on the target VM in `vars.yml`:

   ```yaml
   - name: myvm
     state: absent
   ```

2. Run the playbook:

   ```sh
   just hypervisor-provision-vms
   ```

The role will force-stop the domain, undefine it, and delete its storage directory.

---

## btrfs Storage Health

### Scrub

A scrub reads every block in the filesystem and verifies checksums, allowing btrfs to silently correct errors using the RAID1 mirror.  NixOS auto-scrub is enabled (`services.btrfs.autoScrub.enable = true`), but you can trigger one manually:

```sh
# Start a scrub and wait for completion (may take hours on large pools)
just hypervisor-btrfs-scrub vmstore
just hypervisor-btrfs-scrub bulk

# Check status without blocking
just hypervisor-btrfs-scrub-status vmstore
```

A healthy scrub result looks like:

```
Scrub started: ...
Status:         finished
Duration:       0:12:34
Total to scrub: 850.12GiB
Rate:           1.14GiB/s
Error summary:  no errors found
```

If the scrub reports errors, check device stats immediately (see next section).

### Device error counters

Each device in a btrfs pool keeps per-device I/O error counters.  Non-zero values indicate hardware problems:

```sh
just hypervisor-btrfs-stats vmstore
just hypervisor-btrfs-stats bulk
```

Example output — all counters must be zero on a healthy pool:

```
[/dev/mapper/crypt-vmstore-0].write_io_errs    0
[/dev/mapper/crypt-vmstore-0].read_io_errs     0
[/dev/mapper/crypt-vmstore-0].flush_io_errs    0
[/dev/mapper/crypt-vmstore-0].corruption_errs  0
[/dev/mapper/crypt-vmstore-0].generation_errs  0
```

### Filesystem usage

```sh
just hypervisor-btrfs-usage vmstore
just hypervisor-btrfs-usage bulk
```

Pay attention to `Data, RAID1` and `Metadata, RAID1` lines.  When overall usage is above ~75–80 % btrfs balance operations become more expensive.

### btrfs check (read-only integrity scan)

Run only when the filesystem is **unmounted** or in degraded/read-only mode (e.g. after an unclean shutdown):

```sh
# SSH in first
just hypervisor-ssh

# Read-only check — safe on a live mounted filesystem (no repair)
sudo btrfs check --readonly /dev/mapper/crypt-vmstore-0
```

> **Never** run `btrfs check --repair` on a mounted filesystem.  Unmount first or boot from a rescue environment.

---

## Storage Layout Reference

### LUKS mapper device names

The Disko `btrfs-luks-raid1-pools` layout names LUKS containers as `crypt-<poolname>-<index>`.  Index 0 is the primary disk (the first entry in the `disks` list).

| Pool | Mount point | LUKS devices |
|------|-------------|--------------|
| `vmstore` | `/mnt/vmstore` | `crypt-vmstore-0`, `crypt-vmstore-1` |
| `bulk` | `/mnt/bulk` | `crypt-bulk-0`, `crypt-bulk-1` |

To list all open LUKS devices on the hypervisor:

```sh
ssh hypervisor ls /dev/mapper/
```

### USB keyfile

All LUKS containers (OS disk, vmstore, bulk) use a keyfile stored on a VFAT USB stick.  The USB partition UUIDs are declared under `usbKeysIds` in `nix/hosts/hypervisor/configuration.nix`.  The keyfile filename defaults to the system name (`hypervisor`).

If the USB key is absent at boot, `fallbackToPassword = true` causes the initrd to prompt for the LUKS passphrase on the console.

---

## Adding a Disk to an Existing Pool

This procedure expands a pool by adding a third (or further) device.  btrfs RAID1 continues to mirror all data across **at least two** of the available devices after rebalancing.

> **Prerequisites:** The new disk must be physically installed and visible under `/dev/disk/by-id/`.

### 1. Identify the new disk

```sh
ssh hypervisor ls -la /dev/disk/by-id/ | grep -v part
```

Find the stable `by-id` path for the new disk (e.g. `ata-WDC_WD40EFZX-…`).

### 2. Add the disk to the Nix configuration

Edit `nix/hosts/hypervisor/configuration.nix` and append the new disk path to the target pool's `disks` list:

```nix
pools = {
  vmstore = {
    disks = [
      "/dev/disk/by-id/nvme-KINGSTON_SNV3S1000G_50026B7383A64113"
      "/dev/disk/by-id/ata-WDC_WDS500G2B0B-00YS70_204246801987"
      "/dev/disk/by-id/nvme-new-disk-id-here"    # <-- new disk
    ];
    storageMedia = "ssd";
  };
};
```

The new disk's LUKS container will be named `crypt-<poolname>-<N>` where `N` is its zero-based index in the list (e.g. index 2 → `crypt-vmstore-2`).

### 3. Set up LUKS on the new disk

SSH into the hypervisor and prepare the new disk manually.  Replace `sdX` with the actual device node, `<poolname>` with the pool name, and `<N>` with the disk's index:

```sh
# Partition the disk
sudo parted /dev/sdX -- mklabel gpt
sudo parted /dev/sdX -- mkpart "luks-<poolname>" 0% 100%

# Format the partition with LUKS, using the USB keyfile
sudo cryptsetup luksFormat /dev/sdX1 --key-file /key/hypervisor

# Add the LUKS passphrase as a fallback (use the same passphrase as existing disks)
sudo cryptsetup luksAddKey /dev/sdX1 --key-file /key/hypervisor

# Open the LUKS container with the name the Nix config expects
sudo cryptsetup open /dev/sdX1 crypt-<poolname>-<N> --key-file /key/hypervisor
```

> The USB keyfile is at `/key/hypervisor` only during initrd boot (when the stick is mounted).  If running on a live system, mount it first:
> ```sh
> sudo mkdir -p /key
> sudo mount -o ro -U <USB-UUID> /key
> ```
> The USB UUID is listed under `usbKeysIds` in `nix/hosts/hypervisor/configuration.nix`.

### 4. Add the device to the btrfs pool

```sh
sudo btrfs device add /dev/mapper/crypt-<poolname>-<N> /mnt/<poolname>
```

Verify it was added:

```sh
sudo btrfs filesystem show /mnt/<poolname>
```

### 5. Rebuild and switch the NixOS configuration

This applies the updated crypttab so the new LUKS container is opened automatically on future reboots:

```sh
just nix-remote-install switch hypervisor
```

### 6. Rebalance the pool

After adding a disk, run a balance to redistribute data so all devices participate in RAID1 mirroring:

```sh
# This can take a very long time on large pools; run inside tmux/screen
ssh hypervisor sudo btrfs balance start -dconvert=raid1 -mconvert=raid1 /mnt/<poolname>

# Monitor progress (in another terminal)
ssh hypervisor sudo btrfs balance status /mnt/<poolname>
```

---

## Replacing a Failing Disk

Use this procedure when a disk shows I/O errors in `btrfs device stats` or SMART reports pending/reallocated sectors.

> The pool remains fully available throughout the replacement because RAID1 has at least one good copy of every block.

### 1. Identify the failing device

```sh
just hypervisor-btrfs-stats vmstore   # or bulk
```

Note which LUKS mapper device has non-zero error counters (e.g. `/dev/mapper/crypt-vmstore-1`).

Confirm with SMART:

```sh
ssh hypervisor sudo smartctl -a /dev/disk/by-id/<failing-disk-id>
```

Get the btrfs device ID of the failing device:

```sh
just hypervisor-btrfs-devices vmstore
# Note the "devid" number next to /dev/mapper/crypt-vmstore-1
```

### 2. Install the replacement disk

Physically install the new disk.  Identify its `by-id` path:

```sh
ssh hypervisor ls -la /dev/disk/by-id/ | grep -v part
```

### 3. Set up LUKS on the replacement disk

Use the same LUKS container name as the disk being replaced (this allows btrfs replace to target it correctly):

```sh
# Partition
sudo parted /dev/sdX -- mklabel gpt
sudo parted /dev/sdX -- mkpart "luks-<poolname>" 0% 100%

# LUKS format with keyfile
sudo cryptsetup luksFormat /dev/sdX1 --key-file /key/hypervisor
sudo cryptsetup luksAddKey /dev/sdX1 --key-file /key/hypervisor

# Open with the same name as the failing container (it must be closed first)
sudo cryptsetup close crypt-<poolname>-<N>   # close failing disk
sudo cryptsetup open /dev/sdX1 crypt-<poolname>-<N> --key-file /key/hypervisor
```

### 4. Replace the device in the btrfs pool

```sh
# <src-devid> is the btrfs device ID from step 1
sudo btrfs replace start <src-devid> /dev/mapper/crypt-<poolname>-<N> /mnt/<poolname>

# Monitor progress
sudo btrfs replace status /mnt/<poolname>
```

The replace operation copies all data from the mirror and then removes the old device from the pool.

### 5. Update the Nix configuration

Replace the old disk path with the new one in `nix/hosts/hypervisor/configuration.nix`:

```nix
disks = [
  "/dev/disk/by-id/nvme-KINGSTON_SNV3S1000G_50026B7383A64113"
  "/dev/disk/by-id/ata-new-replacement-disk-id"   # updated
];
```

Rebuild and switch:

```sh
just nix-remote-install switch hypervisor
```

### 6. Verify

```sh
just hypervisor-btrfs-stats vmstore
just hypervisor-btrfs-scrub vmstore
```

All error counters should be zero and the scrub should finish clean.

---

## Removing a Disk from a Pool

> **Warning:** After removal the pool has fewer mirror copies.  Ensure at least 2 devices remain for RAID1.  A balance is required to redistribute data before removing a device.

### 1. Rebalance to exclude the device

Before removing, ensure no data is allocated exclusively on the target device by running a full rebalance:

```sh
ssh hypervisor sudo btrfs balance start -dconvert=raid1 -mconvert=raid1 /mnt/<poolname>
```

### 2. Remove the device

```sh
# <devid> is from `btrfs filesystem show`
ssh hypervisor sudo btrfs device remove <devid> /mnt/<poolname>

# Or by device path
ssh hypervisor sudo btrfs device remove /dev/mapper/crypt-<poolname>-<N> /mnt/<poolname>
```

### 3. Close and disable the LUKS container

```sh
ssh hypervisor sudo cryptsetup close crypt-<poolname>-<N>
```

### 4. Update the Nix configuration

Remove the disk path from the `disks` list in `nix/hosts/hypervisor/configuration.nix` and rebuild:

```sh
just nix-remote-install switch hypervisor
```

---

## Troubleshooting

### Pool fails to mount after reboot (degraded mode)

If a disk is missing at boot (e.g. SATA cable failure), btrfs may mount in degraded mode or refuse to mount entirely.  To mount in degraded mode:

```sh
sudo mount -o degraded /dev/mapper/crypt-<poolname>-0 /mnt/<poolname>
```

Then diagnose the missing device:

```sh
# Check which LUKS containers are open
ls /dev/mapper/

# Check system journal for I/O errors
journalctl -b -p err | grep -i btrfs
```

### USB keyfile not found at boot

If the machine halts waiting for the USB key (or prompts for a passphrase on the console), check:

1. The USB stick is inserted
2. Its partition UUID matches `usbKeysIds` in `nix/hosts/hypervisor/configuration.nix`:
   ```sh
   ls /dev/disk/by-uuid/
   ```
3. The keyfile (`hypervisor`) is present on the VFAT partition

### libvirtd fails to start a VM

```sh
# Check the daemon
ssh hypervisor systemctl status libvirtd.service

# Check libvirt logs
ssh hypervisor sudo journalctl -u libvirtd -n 50

# Verify VM XML is valid
ssh hypervisor sudo virsh define /mnt/vmstore/<vm>/domain.xml
```

### VM disk image is corrupt

If a qcow2 image is suspect, check it with:

```sh
ssh hypervisor sudo qemu-img check /mnt/vmstore/<vm>/<disk>.qcow2
```

A non-zero exit code means corruption.  Restore from backup or re-provision with Ansible (`just hypervisor-provision-vms`).

### btrfs balance stuck or very slow

Balance speed depends on pool size and I/O load.  Monitor progress:

```sh
ssh hypervisor sudo btrfs balance status /mnt/<poolname>
```

To pause and resume:

```sh
ssh hypervisor sudo btrfs balance pause /mnt/<poolname>
ssh hypervisor sudo btrfs balance resume /mnt/<poolname>
```
