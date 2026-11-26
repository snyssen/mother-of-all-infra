# Ansible

Everything that runs on NixOS is configured by Nix (`nix/`). Ansible only does the
imperative work that stays awkward there:

| Playbook | Targets | What it does | Run it with |
| --- | --- | --- | --- |
| `libvirt-image-build` | localhost → hypervisor | Builds NixOS disk images for VMs with `disk_image.build: true`, generates their host keys and authorizes them in SOPS, copies image and LUKS key to the hypervisor | `just hypervisor-build-vm-images <hypervisor>` |
| `libvirt-provision` | hypervisor | Defines and starts the VMs listed in `libvirt_vms` | `just hypervisor-provision-vms <hypervisor>` |
| `technitium-setup` | `technitium` | Admin password, clustering, zones, split-horizon records, DHCP of the Technitium DNS pair | `just ansible-playbook technitium-setup` |
| `backup-server-setup` | `backup` | The bare-metal backup server: restic REST server, storage pool, node exporter, Alloy, CrowdSec bouncer (until it moves to NixOS, issue #52) | `just ansible-playbook backup-server-setup` |

The VM workflow is documented in [docs/operations/vm-deployment.md](../docs/operations/vm-deployment.md),
the VM definitions themselves are in `hosts/host_vars/hypervisor-01/vars.yml`.

## Running

- `just setup` once (installs the Galaxy collections and roles from `requirements.yml`).
- `just ansible-playbook <playbook> [flags]` runs from this directory against
  `hosts/prod.yml` (the default inventory set in `ansible.cfg`; it is the only one).
  It refuses to run unless you are on an up-to-date, clean `main`. Pass
  `--check --diff` for a dry run.
- `just apl` lists the playbooks.

## Secrets

There is no Ansible Vault. Secrets sit next to the plain variables as SOPS files,
`hosts/host_vars/<host>/secrets.sops.yaml`, whose keys are the variable names themselves
(`ansible_user`, `ansible_become_pass`, …). The `community.sops` vars plugin, enabled in
`ansible.cfg`, decrypts them while loading the inventory with your own age key
(`~/.config/sops/age/keys.txt`, or `SOPS_AGE_KEY_FILE`).

Who can decrypt what is set per host in the repository's `.sops.yaml`, one rule per host.
To give someone access to, say, only the DNS servers, add their age key to the technitium
rule and run `just sops-update-keys-all`; they can then run `technitium-setup` and nothing
else.

- Edit a file: `just sops-update ansible/hosts/host_vars/<host>/secrets.sops.yaml`
- Add a generated value: `just sops-gen-secret <file> <variable>`
- Add a value from stdin: `... | just sops-set-stdin <file> <variable>`

A side effect worth knowing: `host_group_vars` also loads these files as plain YAML, so a
`sops` metadata variable shows up in each host's vars. `community.sops` runs after it, so
the decrypted values always win.
