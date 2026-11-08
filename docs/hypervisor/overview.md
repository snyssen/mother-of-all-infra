# Hypervisor Operations

This document covers day-to-day operational procedures for the hypervisor host: VM lifecycle management, btrfs storage health checks, disk expansion and replacement, and common troubleshooting steps.

The production hypervisor is `hypervisor-01`: the former prod box, reinstalled at the
Phase B cutover ([apps-migration-phase-b.md](apps-migration-phase-b.md)). Until that
cutover is over, the Phase A test box `hypervisor` exists too. The `just hypervisor-*`
recipes act on `hypervisor-01` unless given another host as their last argument; the
two playbook recipes take it as their required first argument.

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
| `just hypervisor-provision-vms hypervisor-01` | Re-run the Ansible libvirt provisioning playbook |

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

All VM definitions live in `ansible/hosts/host_vars/hypervisor-01/vars.yml`.  The `libvirt_provision` role is idempotent — re-running the playbook is safe.

> **For NixOS-based VMs:** See [nixos-vm-deployment.md](nixos-vm-deployment.md) for the complete two-playbook workflow (image build + provisioning) with SOPS key authorization and LUKS encryption.

### Adding a new VM

1. Append an entry to `libvirt_vms` in `ansible/hosts/host_vars/hypervisor-01/vars.yml`.  See [plan.md — VM definitions](plan.md#vm-definitions) for the full schema.

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

To pass a USB adapter through to Home Assistant, add `usb_devices` to the `haos` VM definition in `ansible/hosts/host_vars/hypervisor-01/vars.yml`.

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
   just hypervisor-provision-vms hypervisor-01
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
   just hypervisor-provision-vms hypervisor-01
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

### LUKS containers and partition labels

The Disko `btrfs-luks-raid1-pools` layout gives each pool disk one GPT partition holding
a LUKS container. At boot the initrd finds each container **by its GPT partition label**,
and opens it under a fixed mapper name. Both come from the disk's index in the pool's
`disks` list (index 0 is the first entry, the *primary*):

| Index in `disks` | GPT partition label | Mapper name |
|---|---|---|
| 0 | `disk-<pool>-luks-<pool>` | `crypt-<pool>-0` |
| 1 | `disk-0-before-<pool>-0-luks-<pool>` | `crypt-<pool>-1` |
| 2 | `disk-0-before-<pool>-1-luks-<pool>` | `crypt-<pool>-2` |
| *i* ≥ 1 | `disk-0-before-<pool>-<i-1>-luks-<pool>` | `crypt-<pool>-<i>` |

A disk prepared by hand must carry exactly that label, or it is never unlocked at boot.
To see what a host expects:

```sh
nix eval --json .#nixosConfigurations.<host>.config.boot.initrd.luks.devices \
  --apply 'd: builtins.mapAttrs (n: v: v.device) d'
```

and what the disks carry: `lsblk -o NAME,PARTLABEL,SIZE,MOUNTPOINTS` on the host.

A pool of **one** disk is formatted `single` (metadata `dup`): no redundancy. It is a
temporary state, grown into RAID1 with the procedure below.

### USB keyfile

All LUKS containers (OS disk, vmstore, bulk) use a keyfile stored on a VFAT USB stick.
The USB partition UUIDs are declared under `usbKeysIds` in the host's
`configuration.nix`. The keyfile is named after the host (`keyFilename` defaults to
`system.name`): `/key/hypervisor-01` on hypervisor-01. One stick can carry the files of
several hosts.

If the USB key is absent at boot, the initrd prompts for the LUKS passphrase on the
console.

---

## Adding a Disk to an Existing Pool

This grows a pool by one disk. It is also how a one-disk pool becomes RAID1. Every step
below runs on the hypervisor as root (`ssh root@hypervisor-01`), except the
configuration change, which is a commit and a deploy from your machine.

### 1. Identify the new disk and its index

```sh
ls -l /dev/disk/by-id/ | grep -v -- -part
```

Note the new disk's `by-id` name, and its index: the number of disks the pool already
lists. A second disk is index 1, a third index 2. Below, `NEW` is the disk, `POOL` the
pool name, `I` the index:

```sh
NEW=/dev/disk/by-id/ata-EXAMPLE_SERIAL
POOL=bulk
I=1
LABEL="disk-0-before-$POOL-$((I - 1))-luks-$POOL"
NAME="crypt-$POOL-$I"
echo "$NEW -> $LABEL -> $NAME"
```

### 2. Partition it, with the label boot looks for

**This erases the disk.** Check `$NEW` twice.

```sh
sgdisk --zap-all "$NEW"
sgdisk --new=1:0:0 --typecode=1:8309 --change-name=1:"$LABEL" "$NEW"
udevadm settle
ls -l "/dev/disk/by-partlabel/$LABEL"
```

### 3. Create the LUKS container

With the USB keyfile, plus the passphrase the other disks use as a fallback:

```sh
mkdir -p /key && mount -o ro /dev/disk/by-uuid/<a usbKeysIds entry> /key
cryptsetup luksFormat --batch-mode "/dev/disk/by-partlabel/$LABEL" "/key/$(hostname)"
cryptsetup luksAddKey --key-file "/key/$(hostname)" "/dev/disk/by-partlabel/$LABEL"
cryptsetup open --allow-discards --key-file "/key/$(hostname)" \
  "/dev/disk/by-partlabel/$LABEL" "$NAME"
umount /key
```

(`--allow-discards` only for an SSD pool.) `luksAddKey` prompts for the new passphrase.

### 4. Add the disk to the configuration

Append it to the pool's `disks` in `nix/hosts/<host>/configuration.nix`, at index `I`,
then deploy from your machine. That adds the container to the boot-time unlock list:

```sh
just nix-remote-install switch hypervisor-01
```

### 5. Add the device to the btrfs pool

```sh
btrfs device add "/dev/mapper/$NAME" "/mnt/$POOL"
btrfs filesystem show "/mnt/$POOL"
```

### 6. Convert or rebalance, in `screen`

From one disk to two (the pool shows `Data, single`), convert to RAID1:

```sh
screen -S balance                     # Ctrl-a d detaches, screen -r balance re-attaches
btrfs balance start -dconvert=raid1 -mconvert=raid1 "/mnt/$POOL"
```

Already RAID1, add `,soft` to rebalance only what needs it:
`btrfs balance start -dconvert=raid1,soft -mconvert=raid1,soft "/mnt/$POOL"`.

It rewrites the data and can take a day or more on a large HDD pool. The pool stays in
use throughout. Follow it from another shell with `btrfs balance status "/mnt/$POOL"`.

### 7. Prove it survives a reboot

```sh
reboot
# then, once back:
btrfs filesystem usage "/mnt/$POOL"     # Data and Metadata: RAID1
ls /dev/mapper/                          # the new crypt-<pool>-<i> is there
```

---

## Replacing a Failing Disk

Use this procedure when a disk shows I/O errors in `btrfs device stats` or SMART reports
pending/reallocated sectors. The pool stays available throughout, since RAID1 has at
least one good copy of every block.

### 1. Identify the failing device

```sh
just hypervisor-btrfs-stats bulk          # or vmstore
just hypervisor-btrfs-devices bulk        # note the failing device's devid
ssh root@hypervisor-01 smartctl -a /dev/disk/by-id/<failing-disk-id>
```

### 2. Prepare the replacement under the *same* index

The replacement takes the failing disk's place in the `disks` list, so it carries the
same partition label. Physically install it, then follow steps 1–3 of
[Adding a Disk](#adding-a-disk-to-an-existing-pool) with `I` set to the failing disk's
index, except that the container is opened under a temporary name (the failing one is
still open under the real one):

```sh
cryptsetup open --key-file "/key/$(hostname)" "/dev/disk/by-partlabel/$LABEL" "$NAME-new"
```

Two disks now carry the same partition label, which is fine until the reboot in step 5:
the old one is gone by then.

### 3. Replace the device in the btrfs pool

```sh
btrfs replace start <failing-devid> "/dev/mapper/$NAME-new" "/mnt/$POOL"
btrfs replace status "/mnt/$POOL"
```

### 4. Update the configuration

Put the new disk's `by-id` path in place of the old one in `disks`, and deploy:

```sh
just nix-remote-install switch hypervisor-01
```

### 5. Remove the old disk and verify

Shut down, pull the failing disk, boot. The new container now opens as `$NAME`:

```sh
just hypervisor-btrfs-stats bulk
just hypervisor-btrfs-scrub bulk
```

---

## Removing a Disk from a Pool

RAID1 cannot go below two devices. To shrink a two-disk pool to one, convert it first.

### 1. Convert, if this leaves a single disk

```sh
btrfs balance start -dconvert=single -mconvert=dup "/mnt/$POOL"
```

(The remaining disk must hold all the data on its own: check `btrfs filesystem usage`.)

### 2. Remove the device

```sh
btrfs device remove "/dev/mapper/crypt-$POOL-<i>" "/mnt/$POOL"
cryptsetup close "crypt-$POOL-<i>"
```

### 3. Fix the remaining disks' labels, then the configuration

Removing a disk shifts the index of every disk after it, and with it the partition label
boot expects. Before rebooting, relabel each disk that moved, so it carries the label of
its new index (table above):

```sh
sgdisk --change-name=1:"<new label>" /dev/disk/by-id/<disk>
```

Then remove the disk from `disks` and deploy with `boot`, not `switch`, since the mapper
names change at the next boot:

```sh
just nix-remote-install boot hypervisor-01
```

Shut down, pull the disk, boot, and check `btrfs filesystem show "/mnt/$POOL"`.

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
2. Its partition UUID matches `usbKeysIds` in `nix/hosts/hypervisor-01/configuration.nix`:
   ```sh
   ls /dev/disk/by-uuid/
   ```
3. The keyfile (named after the host, e.g. `hypervisor-01`) is present on the VFAT partition

### libvirtd fails to start a VM

```sh
# Check the daemon
ssh hypervisor-01 systemctl status libvirtd.service

# Check libvirt logs
ssh hypervisor-01 sudo journalctl -u libvirtd -n 50

# Verify VM XML is valid
ssh hypervisor-01 sudo virsh define /mnt/vmstore/<vm>/domain.xml
```

### VM disk image is corrupt

If a qcow2 image is suspect, check it with:

```sh
ssh hypervisor-01 sudo qemu-img check /mnt/vmstore/<vm>/<disk>.qcow2
```

A non-zero exit code means corruption.  Restore from backup or re-provision with Ansible (`just hypervisor-provision-vms hypervisor-01`).

### btrfs balance stuck or very slow

Balance speed depends on pool size and I/O load.  Monitor progress:

```sh
ssh hypervisor-01 sudo btrfs balance status /mnt/<poolname>
```

To pause and resume:

```sh
ssh hypervisor-01 sudo btrfs balance pause /mnt/<poolname>
ssh hypervisor-01 sudo btrfs balance resume /mnt/<poolname>
```
