# Deploying NixOS VMs to the Hypervisor

This document describes the complete procedure for building and deploying NixOS-based virtual machines directly from Nix configurations onto the hypervisor using Disko and SOPS encryption.

---

## Overview

The deployment workflow consists of two main Ansible playbooks executed in sequence:

1. **`libvirt-image-build.ansible.yml`** — Builds QEMU disk images locally from NixOS configurations with Disko and injects LUKS keys, then copies them to the hypervisor
2. **`libvirt-provision.ansible.yml`** — Provisions the libvirt domain definitions and starts the VMs

The workflow also handles SOPS key authorization: each new VM gets its own age key derived from an SSH host key, which must be added to `.sops.yaml` before encryption rotation occurs.

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
- `/var/lib/vm-keys/` directory for VM LUKS keys (created automatically by the playbook)

### For the new VM

A NixOS host configuration must exist under `nix/hosts/<vm-name>/` with:
- `configuration.nix` — main system configuration
- `hardware-configuration.nix` — hardware/disk layout
- `disko.nix` or Disko configuration included in the main config (see [plan.md — Disk Encryption & Unattended Boot](plan.md#disk-encryption--unattended-boot))

For SOPS secrets support, the host may also have:
- `data/secrets.yaml` — encrypted SOPS secrets file (optional)

---

## Step 1: Prepare the VM Definition

### 1a. Create the NixOS host configuration

If creating a new host, start with `nix/hosts/<vm-name>/configuration.nix`. Example structure:

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
    # ... other imports
  ];

  disko = {
    layout = "btrfs-luks-main-secondary-subvols";
    "btrfs-luks-main-secondary-subvols" = {
      mainDiskPath = "/dev/vda";       # QEMU default virtio disk
      # ... Disko configuration
    };
  };

  networking.hostName = "<vm-name>";
  # ... rest of system configuration
}
```

> See [`nix/hosts/technitium-secondary/`](../../nix/hosts/technitium-secondary/) for a complete example.

### 1b. Add VM entry to inventory

Edit `ansible/hosts/host_vars/hypervisor/vars.yml` and add the VM to `libvirt_vms` with `disk_image.build: true`:

```yaml
libvirt_vms:
  - name: apps
    state: present
    vcpu: 4
    ram_mb: 8192
    mac_address: "52:54:00:00:00:01"  # must be unique
    disk_gb: 300                        # qcow2 virtual size
    virtiofs_luks_key:
      enable: true                      # for LUKS key injection via virtiofs
    disk_image:
      dest: "/mnt/vmstore/apps/disk.qcow2"
      build: true                       # triggers image build on next playbook run
```

The playbook auto-detects the NixOS config name from the VM name (or uses explicit `disk_image.nixos_config` if set).

> **Important:** The `disk_image.build: true` flag is selective — only VMs with this flag set to `true` are included in the build and copy phases. This protects already-deployed VMs from accidental overwriting. After you have successfully deployed the VM, change `build` to `false` or omit it entirely. Future playbook runs will then skip that VM entirely.

---

## Step 2: Run the Image Build Playbook

### 2a. Execute the build playbook

From the repo root:

```sh
just hypervisor-build-vm-images
```

Or directly:

```sh
cd ansible
ansible-playbook playbooks/libvirt-image-build.ansible.yml -i hosts/prod.yml
```

The playbook will:
1. Generate SSH host keys for each new VM and derive age public keys
2. Display the derived keys and ask you to update `.sops.yaml`
3. Wait for your confirmation before proceeding

### 2b. Update `.sops.yaml` with new VM keys

When prompted, the playbook displays derived age keys for each new VM. Add each key to `.sops.yaml` under the appropriate `creation_rule`:

**Important:** Only add keys for **new VMs** being deployed. If you're rebuilding an existing VM like `technitium-secondary`, **skip that VM's key** — the running host already has its secrets encrypted with the existing key, and updating it would break the deployment.

Example — adding only the `apps` key for a new VM:

```yaml
  - path_regex: nix/hosts/apps/data/[^/]+\.(yaml|json|env|ini)$
    key_groups:
      - pgp:
        age:
          - *root_apps          # newly derived key for apps
          - *snyssen_purplehaze # backup key for manual rotation
          - *snyssen_blackfog   # backup key for manual rotation
```

If you have an existing secrets file for the VM (e.g., `nix/hosts/apps/data/secrets.yaml`), the playbook will automatically re-encrypt it after you confirm.

### 2c. Confirm and proceed

Review `.sops.yaml` changes:

```sh
git diff .sops.yaml
```

Return to the playbook prompt and type `CONTINUE` to proceed. The playbook will:
1. Build Disko images locally with LUKS key injection
2. Copy images and keys to the hypervisor's `/mnt/vmstore/`
3. Clean up temporary build artifacts

### 2d. Commit the SOPS changes

After the playbook completes successfully:

```sh
git add .sops.yaml
git commit -m "sops: authorize new VM host keys for apps"
git push
```

---

## Step 3: Provision and Start the VM

### 3a. Execute the provisioning playbook

```sh
just hypervisor-provision-vms
```

Or directly:

```sh
cd ansible
ansible-playbook playbooks/libvirt-provision.ansible.yml -i hosts/prod.yml
```

The playbook will (for each VM in `libvirt_vms` with `state: present`):
1. Create the `/mnt/vmstore/<name>/` directory
2. Render libvirt domain XML (with LUKS key virtiofs mount if enabled)
3. Define the domain in libvirt (`virsh define`)
4. Set the domain to autostart
5. Start the domain

### 3b. Verify the VM is running

```sh
just hypervisor-vm-list
```

You should see your new VM running. Connect to it:

```sh
# Serial console (press Ctrl-] to exit)
just hypervisor-vm-console apps

# Or open VNC (if LAN access is enabled)
virt-manager
```

### 3c. Disable image building for this VM

Once the VM is confirmed running, set `disk_image.build: false` (or remove the flag) in `ansible/hosts/host_vars/hypervisor/vars.yml`:

```yaml
- name: apps
  # ...
  disk_image:
    dest: "/mnt/vmstore/apps/disk.qcow2"
    build: false                        # deployment complete; prevent future rebuilds
```

This protects the VM from accidental image rebuilds if the playbook is re-run. The provisioning playbook will still manage domain definitions and VM lifecycle, but the image build phase will skip it entirely.

---

## VM Disk Encryption & LUKS Key Access

### How LUKS keys are injected

During the image build phase, Disko generates a random LUKS key that is injected into the image at build time. This key is also copied to the hypervisor at `/var/lib/vm-keys/<vm-name>/luks.key`.

When the VM boots with `virtiofs_luks_key.enable: true`, the LUKS key directory is mounted as a virtiofs filesystem inside the guest at the configured mount point (default: `keys`). The VM can then automatically unlock its LUKS-encrypted root volume using the key from `/keys/luks.key`.

### Accessing the LUKS key from the guest

Inside the running VM:

```sh
ls -la /keys/
cat /keys/luks.key
```

The key is readable only to the root user (mode `0400` on the hypervisor).

### Disaster recovery: Unlocking without virtiofs

If the VM is booted with virtiofs unavailable (e.g. emergency mode), LUKS will prompt for a passphrase on the console. The passphrase is the LUKS key from the hypervisor, base64-encoded (by convention):

```sh
base64 /var/lib/vm-keys/<vm-name>/luks.key | head -c 40
```

---

## SOPS Secrets Management

### Per-host secrets

Each VM can have encrypted SOPS secrets at `nix/hosts/<vm-name>/data/secrets.yaml`. When you run the build playbook and add the VM's age key to `.sops.yaml`, the playbook automatically re-encrypts any existing secrets files using the new key.

### Creating new secrets for a VM

After the playbook runs and `.sops.yaml` is committed, create or edit secrets:

```sh
just sops-edit nix/hosts/apps/data/secrets.yaml
```

The editor will automatically use the VM's age key and your backup identity key for encryption.

### Using secrets in NixOS configs

Secrets are made available at runtime via the `sops-nix` module. See `nix/modules/nixos/sops.nix` and example host configs for integration patterns.

---

## Troubleshooting

### Build fails: "No VMs found with disk_image.build: true"

Ensure the VM entry in `vars.yml` has `disk_image.build: true` and a valid `dest` path.

### Build fails: SOPS key file not found

Set `SOPS_AGE_KEY_FILE` or ensure `~/.config/sops/age/keys.txt` exists and contains your age identity key.

### Build fails during Disko image build

Check the output for Nix evaluation or build errors. Common issues:
- Invalid NixOS config (`nix/hosts/<vm-name>/configuration.nix` syntax error)
- Missing hardware configuration
- Disko layout misconfiguration

Run a local build test:

```sh
nix build .#nixosConfigurations.apps.config.system.build.diskoImagesScript
```

### Provisioning fails: "Refusing to overwrite image for VM ... still defined in libvirt"

If you're re-running the playbook and the VM is already defined in libvirt, undefine it first:

```sh
just hypervisor-ssh
virsh undefine apps --nvram
```

Or force the overwrite (use with caution):

```sh
just hypervisor-build-vm-images -- -e libvirt_image_build_force=true
```

### VM fails to boot: "Unable to open LUKS device"

The LUKS key virtiofs mount may not be available. Check:

1. libvirt domain XML includes the virtiofs filesystem:
   ```sh
   just hypervisor-ssh
   virsh dumpxml apps | grep virtiofs
   ```

2. The key file exists on the hypervisor:
   ```sh
   ls -la /var/lib/vm-keys/apps/luks.key
   ```

3. The guest has virtiofs support (should be auto-mounted at `/keys` if enabled)

### NixOS boot fails after successful build

If the VM starts but NixOS fails to boot, check the console:

```sh
just hypervisor-vm-console apps
```

Common causes:
- Incorrect `mainDiskPath` in Disko config (should be `/dev/vda` for QEMU virtio)
- Missing kernel modules or initrd configuration
- Network configuration incompatible with the libvirt bridge

---

## Advanced: Rebuilding an Existing VM

To rebuild an already-deployed VM (e.g., after config changes), you have two options:

### Option A: Non-destructive NixOS update (fastest)

If only the NixOS config changed, rebuild on the running VM:

```sh
just hypervisor-ssh
ssh apps
sudo nixos-rebuild switch --flake /path/to/config
```

### Option B: Full image rebuild

To rebuild the entire disk image (e.g., after changing Disko layout or disk size):

1. **Temporarily enable building** for the VM by setting `disk_image.build: true` in `vars.yml`
2. **Do NOT** update the VM's age key in `.sops.yaml` — it's already running
3. Run the build playbook:
   ```sh
   just hypervisor-build-vm-images
   ```
4. Stop the VM:
   ```sh
   just hypervisor-vm-stop apps
   ```
5. Re-run provisioning to reload the updated disk:
   ```sh
   just hypervisor-provision-vms
   ```
6. **Disable building** again by setting `disk_image.build: false` once the rebuild is complete

---

## Reference Commands

| Command | Purpose |
|---------|---------|
| `just hypervisor-build-vm-images` | Build Disko images and copy to hypervisor |
| `just hypervisor-provision-vms` | Define and start VMs in libvirt |
| `just hypervisor-vm-list` | List all VMs and their state |
| `just hypervisor-vm-console <vm>` | Open serial console to a VM |
| `just hypervisor-vm-start <vm>` | Start a stopped VM |
| `just hypervisor-vm-stop <vm>` | Gracefully shut down a VM |
| `just sops-edit <file>` | Edit encrypted SOPS file |
| `git diff .sops.yaml` | Review SOPS key changes before commit |
