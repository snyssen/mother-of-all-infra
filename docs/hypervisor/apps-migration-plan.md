# apps VM Migration Plan

This document covers the architecture, decisions, and phased task plan for migrating the current bare-metal Ubuntu apps server (managed by Ansible) to a NixOS VM named **`apps`** running under the hypervisor host.

---

## Background

The current apps server (`snyssen.be`) is a bare-metal machine running Ubuntu, managed almost entirely through the `setup-deploy` Ansible playbook.
It provides ~33 Docker Compose stacks (productivity, media, social, gaming, networking) whose configuration, secrets, and data are spread across Ansible roles and the filesystem.

The hypervisor already runs VMs (e.g., `scrypted`, `haos`) using the patterns established in previous migrations (NixOS config, disko layouts, libvirt Ansible provisioning, SOPS secrets).
The goal of this migration is to bring the apps workload fully into that same paradigm.

A key constraint: the production apps server is running on the best available hardware.
The hypervisor is currently a test-bed running on secondary hardware.
The migration is therefore **two-phased**:

1. **Phase A (this plan):** Code-complete the `apps` VM config; test iteratively on the current hypervisor with partial data.
2. **Phase B (future):** Final backup → wipe production server → install hypervisor config on it → recreate all VMs → restore data. *(Tracked in a separate issue.)*

---

## Architecture Decisions

| Concern | Decision |
|---------|----------|
| Hostname | `apps` |
| Local app data (fast, OS disk) | `/var/lib/app-data` (btrfs root backed by vmstore SSD RAID-1 on hypervisor) |
| Bulk app data (large, HDD) | `/mnt/bulk` — NFS mount of `/mnt/bulk/apps` exported by the hypervisor |
| Compose file convention | `nix/hosts/apps/compose/${stack_name}/docker-compose.yaml` |
| Docker networks | `web`, `db`, `ldap`, `monitoring` bridge networks pre-created by a new `docker-networks` NixOS module |
| `lan` ipvlan network | **Not recreated.** Unifi moves to its own VM (Unifi OS Server); Syncthing drops LAN discovery (relies on Tailscale/global relay instead) |
| Monitoring | `prometheus-node-exporter` (NixOS module) + `grafana-alloy` (NixOS module) + `cAdvisor` (new NixOS module wrapping a container) |
| Backups | `services.restic.backups` (NixOS native); restores via `restic` CLI; optional read-only GUI (`backrest` container) as a separate concern |
| Secrets | SOPS-encrypted `nix/hosts/apps/data/secrets.yaml`; injected into compose stacks via `environmentFile` |
| VM provisioning | `libvirt_provision` Ansible role (existing pattern) |
| Iterative testing | Build an MVS (Minimum Viable System), then migrate stacks one-by-one on a test VM |
| DNS stacks | **Excluded** — DNS migration is tracked separately (see issue #153) |
| Unifi stack | **Excluded** — Moves to a dedicated Unifi OS Server VM |

---

## Current Stack Inventory

All stacks currently deployed by the `stacks_deploy` Ansible role (in deployment order).
Disposition column indicates what happens to each in this migration (`migrate` / `exclude` / `defer`).
No stacks are currently marked as deferred in Phase 0.

| Stack | Description | Disposition |
|-------|-------------|-------------|
| `databases` | Central PostgreSQL + MariaDB + Redis | ✅ Migrate |
| `monitoring` | Prometheus + Grafana (metrics) | ✅ Migrate |
| `backbone` | Traefik reverse proxy + authentik (auth) | ✅ Migrate |
| `unifi` | Unifi Network controller | ⛔ Exclude — separate Unifi OS VM |
| `crowdsec` | CrowdSec security engine | ✅ Migrate |
| `ntfy` | Push notification server | ✅ Migrate |
| `streaming` | Jellyfin + VPN (Gluetun) + *arr stack | ✅ Migrate |
| `immich` | Photo/video management | ✅ Migrate |
| `paperless` | Document management (OCR) | ✅ Migrate |
| `nextcloud` | Personal cloud (files, calendar, contacts) | ✅ Migrate |
| `actual-budget` | Personal finance / budgeting | ✅ Migrate |
| `recipes` | Recipe manager (Tandoor) | ✅ Migrate |
| `speedtest` | Speedtest (Librespeed) | ✅ Migrate |
| `dashboard` | Homepage dashboard | ✅ Migrate |
| `personal_website` | Personal website (static) | ✅ Migrate |
| `quartz` | Quartz digital garden (static) | ✅ Migrate (review: remove Syncthing dependency) |
| `s-pdf` | Stirling PDF tools | ✅ Migrate |
| `foundryvtt` | FoundryVTT TTRPG platform | ✅ Migrate |
| `minecraft` | Minecraft server | ✅ Migrate |
| `syncthing` | File sync — **drop `lan` network ref** | ✅ Migrate (drop ipvlan, use bridge) |
| `team_wiki` | Wiki.js team wiki | ✅ Migrate |
| `rallly` | Meeting scheduler | ✅ Migrate |
| `speedtest-tracker` | Speedtest tracker | ✅ Migrate |
| `sharkey` | Misskey fork (ActivityPub) | ✅ Migrate |
| `dawarich` | Location history tracker | ✅ Migrate |
| `semaphore` | Ansible Semaphore UI | ✅ Migrate |
| `backrest` | Restic backup browser GUI | ⚠️ Migrate as read-only browse UI (restores via CLI) |
| `skyrim_together` | Skyrim Together Reborn server | ✅ Migrate (on-demand only) |
| `matrix` | Matrix homeserver (Synapse) + bridges | ✅ Migrate |
| `attic` | Nix binary cache (Attic server) | ✅ Migrate |
| `mobilizon` | Federated events platform | ✅ Migrate |
| `scrypted` | NVR / camera bridge | ⛔ Exclude — already its own NixOS VM |

> **To clarify during Phase 0 inventory:** inter-stack dependencies (shared DBs, network references), stacks that may warrant their own VM, and exact secrets per stack.

---

## Data Mapping

| Current path | New path | Notes |
|---|---|---|
| `/home/snyssen/data/<stack>/` | `/var/lib/app-data/<stack>/` | On OS btrfs disk (vmstore SSD pool) |
| `/mnt/storage/<stack>/` | `/mnt/bulk/<stack>/` | NFS mount of `/mnt/bulk/apps` on hypervisor |

Compose files: Jinja2 variable `{{ docker_mounts_directory }}` → `/var/lib/app-data`, `/mnt/storage` → `/mnt/bulk`.

---

## NixOS Module Requirements

| Module | Status | Notes |
|--------|--------|-------|
| `disko/layouts/single-btrfs-luks-virtiofs-key` | ✅ Exists | Reuse as-is |
| `compose-stacks` | ✅ Exists | Reuse as-is |
| `nfs-mounts` | ✅ Exists | Reuse as-is for `/mnt/bulk` |
| `docker` | ✅ Exists | Reuse as-is |
| `sops` | ✅ Exists | Reuse as-is |
| `tailscale` | ✅ Exists | Reuse as-is |
| `grafana-alloy` | ✅ Exists | Reuse as-is |
| `prometheus-node-exporter` | ✅ Exists | Reuse as-is |
| `crowdsec-firewall-bouncer` | ✅ Exists | Reuse as-is |
| `docker-networks` | 🆕 Create | Pre-create named bridge networks (`web`, `db`, `ldap`, `monitoring`) as systemd oneshot units, so they exist before any compose stack starts |
| `cadvisor` | 🆕 Create | Run cAdvisor as a native NixOS service (or `virtualisation.oci-containers` entry) to expose Prometheus container metrics |

---

## Hypervisor Changes Required

### 1. NFS Export for `/mnt/bulk/apps`

Add to `nix/hosts/hypervisor/configuration.nix`:

```nix
nfsExports.exports = [
  { path = "/mnt/bulk/scrypted"; }  # existing
  { path = "/mnt/bulk/apps"; }       # new
];
```

### 2. VM Provisioning

Add `apps` VM entry in `ansible/hosts/host_vars/hypervisor/vars.yml`:

```yaml
- name: apps
  vcpu: 4        # adjust after Phase 0 capacity planning
  ram_mb: 8192   # adjust after Phase 0 capacity planning
  mac_address: "52:54:00:XX:XX:XX"  # assign unique MAC
  disk_gb: 128   # OS disk on vmstore SSD pool
  virtiofs_luks_key:
    enable: true
  iso_image:
    url: "https://channels.nixos.org/nixos-25.11/latest-nixos-minimal-x86_64-linux.iso"
    dest: "/mnt/vmstore/apps/installer.iso"
    enable_mount: false
```

---

## apps Host Configuration Outline

`nix/hosts/apps/configuration.nix` should import:

```nix
imports = [
  flake.modules.nixos.disko
  ./hardware-configuration.nix

  flake.modules.nixos.sops
  flake.modules.nixos.cache
  flake.modules.nixos.grub
  flake.modules.nixos.kbd-layout
  flake.modules.nixos.shell
  flake.modules.nixos.locale
  flake.modules.nixos.nh
  flake.modules.nixos.user

  flake.modules.nixos.tailscale
  flake.modules.nixos.crowdsec-firewall-bouncer
  flake.modules.nixos.prometheus-node-exporter
  flake.modules.nixos.grafana-alloy
  flake.modules.nixos.docker
  flake.modules.nixos.docker-networks   # new module
  flake.modules.nixos.cadvisor          # new module
  flake.modules.nixos.nfs-mounts
  flake.modules.nixos.compose-stacks
];

disko.layout = "single-btrfs-luks-virtiofs-key";

dockerNetworks.networks = [ "web" "db" "ldap" "monitoring" ];

nfsMounts.enable = true;
nfsMounts.mounts.bulk = {
  path = "/mnt/bulk";
  host = "hypervisor";
  remotePath = "/mnt/bulk/apps";
  dependsOn.tailscale = true;
};
```

---

## Per-Stack Migration Checklist (template)

For each stack, the migration consists of:

- [ ] Copy `docker-compose.yml` from Ansible role to `nix/hosts/apps/compose/<stack>/docker-compose.yaml`
- [ ] Replace Jinja2 variables: `{{ docker_mounts_directory }}/X` → `/var/lib/app-data/X`, `/mnt/storage/X` → `/mnt/bulk/X`
- [ ] Remove `lan` network references if present; add regular bridge networks as needed
- [ ] Extract secrets into `nix/hosts/apps/data/secrets.yaml` (SOPS-encrypted)
- [ ] Add `compose-stacks.stacks.<name>` entry in `configuration.nix`
- [ ] Add `extraAfter = [ "mnt-bulk.mount" ]` for stacks using `/mnt/bulk`
- [ ] Verify stack starts cleanly on test VM

---

## Testing Strategy

1. **MVS first:** Get the base NixOS config booting on the test hypervisor with correct disk layout, networking, NFS mount, and SOPS secrets — no stacks yet.
2. **Infrastructure stacks first:** Migrate `databases`, `monitoring`, `backbone`, `crowdsec` — these are dependencies of most other stacks.
3. **Incremental stack migration:** Add stacks one or a few at a time; verify after each batch.
4. **Partial data restore:** Restore a subset of data from the current apps server for realistic testing (e.g., a small Nextcloud dataset, test Postgres DB).
5. **No production traffic yet:** All testing happens on the test hypervisor; DNS is not changed until Phase B (production cutover).

---

## Related Issues

- #153 — Migrate DNS (excluded from this plan; handled separately)
- Phase B cutover will be tracked in a new epic once Phase A is complete
