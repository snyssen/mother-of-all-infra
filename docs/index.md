# Mother of All Infra Documentation

Welcome to the documentation for Mother of All Infra, a personal monorepo for self-hosted infrastructure managed with Nix, Ansible, and Terraform.

## Documentation Map

### Hypervisor

Documentation for the self-hosted hypervisor:

- **[Plan](hypervisor/plan.md)** — Disk inventory, btrfs RAID1 profiles, USB keyfile boot, network bridge and NFS setup, and NixOS repository architecture overview
- **[Operations](hypervisor/overview.md)** — Day-to-day operations: VM lifecycle, btrfs scrub/check, disk expansion and replacement, and troubleshooting

### [Backups](backups.md)

Documentation for backup operations and restore procedures.

### Nix

Infrastructure-as-code configurations for NixOS and Home Manager:

- **[Network](nix/network.md)** — Overview of the network setup
- **[Full Disk Encryption](nix/Full%20Disk%20Encryption.md)** — Setting up and managing full disk encryption on NixOS hosts

### Ansible

Deployment and orchestration documentation:

#### [Application Stacks](ansible/stacks/README.md)

Detailed guides for container-based application stacks deployed via Ansible roles:

- **[Alloy](ansible/stacks/alloy.md)** — Grafana Alloy observability stack
- **[Backbone](ansible/stacks/backbone.md)** — Core backbone services
- **[Databases](ansible/stacks/databases.md)** — Database services configuration
- **[Dawarich](ansible/stacks/dawarich.md)** — Location tracking service
- **[Immich](ansible/stacks/immich.md)** — Self-hosted photo management
- **[Matrix](ansible/stacks/matrix.md)** — Matrix messaging server deployment
- **[Minecraft](ansible/stacks/minecraft.md)** — Minecraft server setup
- **[Monitoring](ansible/stacks/monitoring.md)** — Monitoring and observability stack
- **[Nextcloud](ansible/stacks/nextcloud.md)** — Nextcloud suite configuration
- **[ntfy](ansible/stacks/ntfy.md)** — Notification service setup
- **[Paperless](ansible/stacks/paperless.md)** — Document management system
- **[Speedtest Tracker](ansible/stacks/speedtest-tracker.md)** — Network speed monitoring
- **[Streaming](ansible/stacks/streaming.md)** — Media streaming services
- **[Syncthing](ansible/stacks/syncthing.md)** — File synchronization service

## Quick Links

- **Repository**: [GitHub - mother-of-all-infra](https://github.com/snyssen/mother-of-all-infra)
- **Main README**: See the project root for general project information
- **Ansible README**: [ansible/README.md](../ansible/README.md) for playbook and role details
- **Dev Guide**: Check `copilot-instructions.md` in `.github/` for developer workflows
