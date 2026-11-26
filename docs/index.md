# Mother of All Infra

Documentation for a personal monorepo of self-hosted infrastructure. Nix configures every
host and the services on them; Terraform provisions the cloud machines; Ansible keeps a
narrow role for imperative work (building and provisioning VM images, the Technitium DNS
cluster, the bare-metal backup server).

The production apps server is **`apps-01`**, a NixOS VM on the hypervisor
**`hypervisor-01`**.

## Architecture

What exists and why.

- **[Network](architecture/network.md)** — LAN addressing, split-horizon DNS, the
  Technitium cluster and its failover
- **[Hypervisor](architecture/hypervisor.md)** — hypervisor-01's disks, pools, unattended
  boot, bridge and NFS, and the VMs it runs
- **[Secrets](architecture/secrets.md)** — SOPS and age: keys, recipients, where secrets
  live for Nix hosts and for Ansible
- **[Repository layout](architecture/repository.md)** — what lives where, the flake's
  blueprint structure, hosts and modules

## Operations

How to run it.

- **[Hypervisor operations](operations/hypervisor.md)** — VM lifecycle, btrfs scrub and
  checks, adding and replacing disks, troubleshooting
- **[VM deployment](operations/vm-deployment.md)** — building and provisioning NixOS VM
  images
- **[Setting up a new machine](operations/new-machine/index.md)** — installing a NixOS host
  with nixos-anywhere
- **[Full disk encryption](operations/disk-encryption.md)** — LUKS with USB keyfile unlock
- **[Backups](operations/backups.md)** — Backrest on apps-01, restores, disaster recovery,
  and last-resort access

## Services

What runs on apps-01.

- **[Services](services/index.md)** — every stack at a glance
- **[Monitoring](services/monitoring.md)** — monitoring as code: alerts, silences,
  dashboards
- **[Scanner to Paperless](services/scanner-to-paperless.md)** — scanning straight into
  Paperless

## Modules

Reference for reusable NixOS modules: [libvirtd](modules/libvirtd.md),
[NFS exports](modules/nfs-exports.md), [printing](modules/printing.md).

## Plans

[Work not carried out yet](plans/index.md), such as CrowdSec AppSec on the ingress
host.

## Archive

[Obsolete documents](archive/index.md) kept for history, chiefly the record of the
migration from the Ansible-managed server to apps-01.
