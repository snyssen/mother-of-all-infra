# Deploying NixOS VMs to the Hypervisor

This document describes the complete procedure for building and deploying NixOS-based virtual machines directly from Nix configurations onto the hypervisor using Disko and SOPS encryption. `apps-01` and `technitium-secondary` on `hypervisor-01` were deployed this way.

---

## Overview

The deployment workflow consists of two Ansible playbooks executed in sequence, each behind a `just` recipe:

1. **`libvirt-image-build.ansible.yml`** (`just hypervisor-build-vm-images <hypervisor>`) — Builds QEMU disk images locally from NixOS configurations with Disko, injecting a LUKS key and an SSH host key, then copies the image and the LUKS key to the hypervisor
2. **`libvirt-provision.ansible.yml`** (`just hypervisor-provision-vms <hypervisor>`) — Provisions the libvirt domain definitions and starts the VMs

The hypervisor is a required **first** argument of both recipes, so they never act on one by default; any further arguments are passed to `ansible-playbook` (e.g. `-e libvirt_vms_only=apps-01`).

The workflow also handles SOPS key authorization: every image build generates a fresh SSH host key for the VM, and with it a new age key, which must be put into `.sops.yaml` before the VM's secrets are re-encrypted.

---

## Prerequisites

### On your workstation

- **Nix flakes** environment with the repo devshell active (`nix develop`)
- **SOPS age key file** at `~/.config/sops/age/keys.txt` (or set `SOPS_AGE_KEY_FILE`)
- **Ansible** and inventory configured (see `ansible/README.md`)
- **Git** with an active working directory in the repo

### On the hypervisor

- libvirtd running and accessible via SSH
- `/mnt/vmstore/` pool mounted and writable
- `/var/lib/vm-keys/` directory for VM LUKS keys (created automatically by the playbooks)

### For the new VM

A NixOS host configuration must exist under `nix/hosts/<vm-name>/` with:

- `configuration.nix` — main system configuration, including the Disko layout (see [Step 1a](#1a-create-the-nixos-host-configuration))
- `hardware-configuration.nix` — hardware configuration (import `profiles/qemu-guest.nix`)

The playbook builds `nixosConfigurations.<vm-name>`, so the directory name must match the VM's `name` in the inventory (or set `disk_image.nixos_config`).

For SOPS secrets support, the host may also have encrypted files under `data/` — most hosts use a single `data/secrets.yaml`; `apps-01` uses one file per stack.

---

## Step 1: Prepare the VM Definition

### 1a. Create the NixOS host configuration

If creating a new host, start with `nix/hosts/<vm-name>/configuration.nix`. VMs use the `single-btrfs-luks-virtiofs-key` Disko layout, which unlocks the root volume with a key file shared from the hypervisor (see [How LUKS keys are injected](#how-luks-keys-are-injected) below). Example structure:

```nix
{
  inputs,
  flake,
  config,
  pkgs,
  ...
}:
{
  imports = [
    flake.modules.nixos.disko          # Include Disko module
    ./hardware-configuration.nix
    flake.modules.nixos.sops
    # ... other imports
  ];

  disko =
    let
      ly = "single-btrfs-luks-virtiofs-key";
    in
    {
      layout = ly;
      "${ly}" = {
        # mainDiskPath defaults to /dev/vda (QEMU virtio disk)
        autoResizeOnBoot.enable = true; # grow partition, LUKS and btrfs to the qcow2's size
      };
    };

  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  networking.hostName = "<vm-name>";
  # ... rest of system configuration
}
```

The image is built at the layout's `qcowOptions.diskImageSize` (default 32G); provisioning then grows the qcow2 to `disk_gb`, and `autoResizeOnBoot` grows the partition, the LUKS container and btrfs to match on the next boot.

> See `nix/hosts/technitium-secondary/` (small) or `nix/hosts/apps-01/` for complete examples.

### 1b. Add VM entry to inventory

Edit `ansible/hosts/host_vars/hypervisor-01/vars.yml` and add the VM to `libvirt_vms` with `disk_image.build: true`:

```yaml
libvirt_vms:
  - name: apps-01
    state: present
    vcpu: 12
    ram_mb: 49152
    mac_address: "52:54:00:00:00:01"  # must be unique
    disk_gb: 1000                       # qcow2 virtual size
    virtiofs_luks_key:
      enable: true                      # share the LUKS key directory over virtiofs
    disk_image:
      dest: "/mnt/vmstore/apps-01/disk.qcow2"
      build: true                       # include in the next image build
```

The playbook uses the VM name as the NixOS config name (or `disk_image.nixos_config` if set). Other optional `disk_image` keys: `build_memory_mb` (memory for the Disko build VM).

> **Important:** The `disk_image.build: true` flag is selective — only VMs with this flag set to `true` are included in the build and copy phases. Set it **only for the build**, and back to `false` once the VM is deployed (as `apps-01` and `technitium-secondary` are today). Future build runs then skip that VM entirely, and a rebuild can't happen by accident.

---

## Step 2: Run the Image Build Playbook

### 2a. Execute the build playbook

From the repo root:

```sh
just hypervisor-build-vm-images hypervisor-01
```

Or directly:

```sh
cd ansible
ansible-playbook playbooks/libvirt-image-build.ansible.yml -i hosts/prod.yml -e libvirt_hypervisor=hypervisor-01
```

The playbook will:

1. Generate a new ed25519 SSH host key for each VM being built and derive its age public key
2. Display the derived keys and ask you to update `.sops.yaml`
3. Wait for you to type `CONTINUE` before proceeding

### 2b. Update `.sops.yaml` with the VM keys

When prompted, the playbook displays the derived age key for each VM being built. Every build generates a **new** host key, so this applies to rebuilds as much as to new VMs:

- **New VM:** add an anchor for the key in `.sops.yaml`'s `keys` list and a `creation_rule` for `nix/hosts/<vm-name>/data/`.
- **Rebuilt VM:** **replace** the VM's existing key under its anchor (e.g. `&root_apps_01`). The rebuilt VM has a new age identity, and the old key no longer belongs to anything.

Example — the `apps-01` rule:

```yaml
  - path_regex: nix/hosts/apps-01/data/[^/]+\.(yaml|json|env|ini)$
    key_groups:
      - pgp:
        age:
          - *breakglass
          - *root_apps_01       # the VM's key, derived by the playbook
          - *snyssen_purplehaze
          - *snyssen_blackfog
```

### 2c. Confirm and proceed

Review `.sops.yaml` changes:

```sh
git diff .sops.yaml
```

Return to the playbook prompt and type `CONTINUE` to proceed. The playbook will:

1. Run `sops updatekeys` on `nix/hosts/<vm-name>/data/secrets.yaml`, **if that file exists**
2. Generate a random LUKS key per VM, and build each Disko image locally with that key and the SSH host key injected
3. Copy the image to its `disk_image.dest` and the LUKS key to `/var/lib/vm-keys/<vm-name>/luks.key` on the hypervisor
4. Clean up temporary build artifacts and the staged SSH keys

### 2d. Re-encrypt the VM's secrets

The automatic re-encryption in step 1 above only covers a single `data/secrets.yaml`. A VM whose secrets are split into several files — `apps-01` has one per stack and no `secrets.yaml` — is not re-encrypted by the playbook. Re-encrypt every file to the recipients now in `.sops.yaml`:

```sh
just sops-update-keys-all
```

This is not optional: without it, sops-nix on the VM cannot decrypt its secrets. Run it from a machine whose age key is a recipient of the files (one of the workstation keys or the breakglass key; the VM's own old key is gone).

### 2e. Commit the SOPS changes

After the playbook completes successfully, commit `.sops.yaml` and the re-encrypted secrets files, e.g. with a message like:

```text
chore(sops): authorize the new host key of apps-01
```

---

## Step 3: Provision and Start the VM

### 3a. Execute the provisioning playbook

```sh
just hypervisor-provision-vms hypervisor-01
```

To provision only some VMs, add `-e libvirt_vms_only=<vm>[,<vm>...]` (comma-separated, no JSON: `just` passes extra arguments to the shell unquoted):

```sh
just hypervisor-provision-vms hypervisor-01 -e libvirt_vms_only=apps-01
```

Or directly:

```sh
cd ansible
ansible-playbook playbooks/libvirt-provision.ansible.yml -i hosts/prod.yml -e libvirt_hypervisor=hypervisor-01
```

The playbook will (for each VM in `libvirt_vms` with `state: present`):

1. Create the `/mnt/vmstore/<name>/` directory
2. Make sure `/var/lib/vm-keys/<name>/luks.key` exists (generated only if missing — a built VM's key is already there)
3. Grow the qcow2 to `disk_gb` if it is smaller
4. Render libvirt domain XML (with the virtiofs key share if enabled)
5. Define the domain in libvirt (`virsh define`); if the XML changed for an existing domain, shut it down and redefine it
6. Set the domain to autostart
7. Start the domain

### 3b. Verify the VM is running

```sh
just hypervisor-vm-list
```

You should see your new VM running. Connect to it:

```sh
# Serial console (press Ctrl-] to exit)
just hypervisor-vm-console apps-01

# Or open VNC (LAN access is enabled on hypervisor-01)
virt-manager
```

### 3c. Disable image building for this VM

Once the VM is confirmed running, set `disk_image.build: false` in `ansible/hosts/host_vars/hypervisor-01/vars.yml`:

```yaml
- name: apps-01
  # ...
  disk_image:
    dest: "/mnt/vmstore/apps-01/disk.qcow2"
    build: false                        # deployment complete; prevent future rebuilds
```

This protects the VM from accidental image rebuilds if the build playbook is re-run. The provisioning playbook still manages domain definitions and VM lifecycle; only the image build skips it.

---

## VM Disk Encryption & LUKS Key Access

### How LUKS keys are injected

During the image build, the playbook generates a random 2 KiB LUKS key (`dd if=/dev/urandom`) for each VM. Disko receives it as a **pre-format file** placed at `/run/keys/luks.key` in the build VM, formats the LUKS container with it, and the playbook then copies the same key to the hypervisor at `/var/lib/vm-keys/<vm-name>/luks.key` (mode `0400`, directory `0700`, root only). The SSH host key is injected as a post-format file at `/etc/ssh/ssh_host_ed25519_key`.

When the VM has `virtiofs_luks_key.enable: true`, its domain XML shares `/var/lib/vm-keys/<vm-name>/` over virtiofs under the tag `keys` (`virtiofs_luks_key.tag`). The `single-btrfs-luks-virtiofs-key` layout then:

1. mounts that share **read-only at `/run/keys` in the initrd only**, just before `systemd-cryptsetup@cryptroot` runs;
2. unlocks the root volume with `/run/keys/luks.key`;
3. unmounts the share again before switching to the real root.

The key is therefore **not** visible in the running guest. The only later use is `autoResizeOnBoot`, which briefly mounts the share again to run `cryptsetup resize`, and unmounts it.

### Disaster recovery: Unlocking without virtiofs

The LUKS container is formatted with the key file only: there is no typeable passphrase. If the virtiofs share is unavailable, the initrd cannot unlock the disk. Restore the share (check the domain XML and that `/var/lib/vm-keys/<vm-name>/luks.key` exists) rather than trying to type a passphrase. Losing the key file means losing the VM's disk; a VM like `apps-01` is then rebuilt and restored from backups (see [Backups](backups.md)).

---

## SOPS Secrets Management

### Per-host secrets

Each VM can have encrypted SOPS secrets under `nix/hosts/<vm-name>/data/`. Most hosts use a single `secrets.yaml`; `apps-01` is split into one file per stack (`<stack>.yaml`, plus `common.yaml` for host-wide secrets) so that changing a secret only restarts the stack that owns it. The `.sops.yaml` rules glob the whole directory, so either layout works without extra configuration.

Re-encryption after a key change: the build playbook only runs `sops updatekeys` on `data/secrets.yaml`. For everything else, run `just sops-update-keys-all` (every SOPS file in the repo) or `just sops-update-keys <file>` (one file).

### Creating new secrets for a VM

After the VM's key is in `.sops.yaml`, create or edit secrets:

```sh
just sops-update nix/hosts/apps-01/data/common.yaml
```

New files are encrypted to every recipient of the matching `.sops.yaml` rule: the VM's age key, the workstation keys and the breakglass key.

### Using secrets in NixOS configs

Secrets are made available at runtime via the `sops-nix` module. See `nix/modules/nixos/sops.nix` and example host configs for integration patterns.

---

## Troubleshooting

### Build fails: "No VMs found with disk_image.build: true"

Ensure the VM entry in `vars.yml` has `disk_image.build: true` and a valid `dest` path, and that you passed the right hypervisor as the recipe's first argument.

### Build fails: SOPS key file not found

Set `SOPS_AGE_KEY_FILE` or ensure `~/.config/sops/age/keys.txt` exists and contains your age identity key.

### Build fails during Disko image build

Check the output for Nix evaluation or build errors. Common issues:

- Invalid NixOS config (`nix/hosts/<vm-name>/configuration.nix` syntax error)
- Missing hardware configuration
- Disko layout misconfiguration

Run a local build test:

```sh
nix build .#nixosConfigurations.apps-01.config.system.build.diskoImagesScript
```

### Build fails: "Refusing to overwrite image for VM ... still defined in libvirt"

The copy phase of the build playbook refuses to replace an existing image while the VM is still defined in libvirt. Either undefine it first:

```sh
just hypervisor-ssh
sudo virsh undefine apps-01 --nvram
```

Or force the overwrite (use with caution; stop the VM first):

```sh
just hypervisor-build-vm-images hypervisor-01 -e libvirt_image_build_force=true
```

> [!WARNING]
> Without `libvirt_image_build_force=true`, the copy never replaces a file that already exists: an existing image **or** an existing `/var/lib/vm-keys/<vm>/luks.key` is silently kept. Undefining the VM gets past the refusal above, but the old image and key stay in place. For a rebuild over an existing VM, use the force flag (see [Option B](#option-b-full-image-rebuild)).

### VM fails to boot: "Unable to open LUKS device"

The LUKS key virtiofs share may not be available, or the key on the hypervisor doesn't match the image. Check:

1. libvirt domain XML includes the virtiofs filesystem:

   ```sh
   just hypervisor-ssh
   sudo virsh dumpxml apps-01 | grep -A3 virtiofs
   ```

2. The key file exists on the hypervisor:

   ```sh
   sudo ls -la /var/lib/vm-keys/apps-01/luks.key
   ```

3. The initrd mounted the share: on the serial console, look for the `mount-luks-key-virtiofs` unit's "Mounting virtiofs key share (keys) at /run/keys..." line.
4. After a rebuild, the key was actually replaced (see the warning above).

### NixOS boot fails after successful build

If the VM starts but NixOS fails to boot, check the console:

```sh
just hypervisor-vm-console apps-01
```

Common causes:

- Incorrect `mainDiskPath` in the Disko config (the default `/dev/vda` is right for a QEMU virtio disk)
- Missing kernel modules or initrd configuration
- Network configuration incompatible with the libvirt bridge

---

## Advanced: Rebuilding an Existing VM

To rebuild an already-deployed VM (e.g., after config changes), you have two options:

### Option A: Non-destructive NixOS update (fastest)

If only the NixOS config changed, deploy it to the running VM from your workstation:

```sh
just nix-remote-install switch apps-01
```

### Option B: Full image rebuild

To rebuild the entire disk image (e.g., after changing the Disko layout). This **wipes the VM's disk**: for `apps-01`, follow the full disaster-recovery procedure in [Backups](backups.md), which also holds the services until the data is restored.

1. **Temporarily enable building** for the VM by setting `disk_image.build: true` in `vars.yml`
2. Stop the VM:

   ```sh
   just hypervisor-vm-stop apps-01
   ```

3. Run the build playbook, forcing the overwrite of the existing image and LUKS key:

   ```sh
   just hypervisor-build-vm-images hypervisor-01 -e libvirt_image_build_force=true
   ```

4. At the prompt, **replace** the VM's age key in `.sops.yaml` with the newly derived one (the rebuilt VM has a new host key), type `CONTINUE`, then run `just sops-update-keys-all` and commit
5. Re-run provisioning to start the VM on the new disk:

   ```sh
   just hypervisor-provision-vms hypervisor-01 -e libvirt_vms_only=apps-01
   ```

6. **Disable building** again by setting `disk_image.build: false` once the rebuild is complete

---

## Reference Commands

| Command | Purpose |
|---------|---------|
| `just hypervisor-build-vm-images hypervisor-01` | Build Disko images and copy to hypervisor |
| `just hypervisor-provision-vms hypervisor-01 [-e libvirt_vms_only=<vm>]` | Define and start VMs in libvirt |
| `just nix-remote-install switch <vm>` | Deploy a NixOS config change to a running VM |
| `just hypervisor-vm-list` | List all VMs and their state |
| `just hypervisor-vm-console <vm>` | Open serial console to a VM |
| `just hypervisor-vm-start <vm>` | Start a stopped VM |
| `just hypervisor-vm-stop <vm>` | Gracefully shut down a VM |
| `just sops-update <file>` | Edit encrypted SOPS file |
| `just sops-update-keys-all` | Re-encrypt every SOPS file to the recipients in `.sops.yaml` |
| `git diff .sops.yaml` | Review SOPS key changes before commit |
