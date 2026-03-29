# Apps VM Migration Plan

This document tracks the migration of the `snyssen.be` bare-metal Ubuntu host (currently
managed by Ansible) to a NixOS virtual machine named `apps`, running under the `hypervisor`
host.

## Status

> **Current phase:** Phase 0 — Planning & inventory

## Table of Contents

1. [Scope & Goals](#scope--goals)
2. [Out of Scope](#out-of-scope)
3. [Assumptions](#assumptions)
4. [Architecture](#architecture)
5. [Data Layout](#data-layout)
6. [Secrets Handling](#secrets-handling)
7. [Testing Strategy](#testing-strategy)
8. [VM Specifications](#vm-specifications)
9. [Stack Inventory](#stack-inventory)
10. [Task Checklist](#task-checklist)

---

## Scope & Goals

- Move the `apps` host OS configuration from Ansible to NixOS (declarative, reproducible).
- Reuse existing Nix modules: `disko`, `compose-stacks`, `nfs-mounts`, `docker`, `sops`,
  `tailscale`, `grafana-alloy`, `prometheus-node-exporter`, `crowdsec-firewall-bouncer`.
- Deploy all compose stacks via the `compose-stacks` Nix module instead of the
  `stacks_deploy` Ansible role.
- Establish a two-tier data layout on the VM that mirrors the current organisation.
- All compose stack files must be named `docker-compose.yaml` (for Renovate auto-detection)
  and stored under `nix/hosts/apps/compose/<stack_name>/docker-compose.yaml`.

## Out of Scope

- **DNS migration** — DNS will move to a dedicated VM; the containerised AdGuard setup is
  NOT migrated here.
- **Unifi migration** — Unifi needs its own dedicated VM (the container image is deprecated
  in favour of Unifi OS Server); tracked separately.
- **Full production cutover** — Phase A focuses on code completeness and test deployment;
  the production hardware swap is Phase B (separate epic).
- **Scrypted** — already has its own Nix host (`nix/hosts/scrypted/`); not touched.

---

## Assumptions

| # | Assumption |
|---|-----------|
| A1 | The `apps` VM disk is backed by the hypervisor's `vmstore` btrfs RAID-1 SSD pool. |
| A2 | LUKS unlock uses a virtiofs key share (same pattern as `scrypted`). |
| A3 | The VM NIC attaches to `br0` (LAN bridge) for direct LAN access. |
| A4 | Tailscale provides internal connectivity and SSH access post-deploy. |
| A5 | `/mnt/bulk/apps` NFS export on hypervisor exists before the VM is deployed. |
| A6 | All secrets are managed with SOPS (age key per host). |
| A7 | Monitoring uses native NixOS modules (node-exporter + grafana-alloy); cAdvisor runs as a compose stack. |
| A8 | Docker bridge networks (`web`, `db`, `ldap`, `monitoring`) are pre-created by the `docker-networks` NixOS module. |
| A9 | The legacy `lan` ipvlan network is NOT created on the VM. |

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  hypervisor (KVM host)                              │
│                                                     │
│  ┌──────────────────────────┐                       │
│  │  apps VM (NixOS)         │                       │
│  │                          │                       │
│  │  OS disk (vmstore SSD)   │  /var/lib/app-data    │
│  │  ├─ btrfs + LUKS         │  (local app data)     │
│  │  └─ virtiofs key unlock  │                       │
│  │                          │                       │
│  │  /mnt/bulk  (NFS)  ──────┼──► /mnt/bulk/apps     │
│  │                          │    (hypervisor HDD)   │
│  │  Docker stacks           │                       │
│  │  └─ compose-stacks mod.  │                       │
│  │                          │                       │
│  │  Monitoring              │                       │
│  │  ├─ node-exporter        │                       │
│  │  ├─ grafana-alloy        │                       │
│  │  └─ cAdvisor (compose)   │                       │
│  └──────────────────────────┘                       │
│                                                     │
│  NFS export: /mnt/bulk/apps                         │
│  btrfs bulk pool (HDD RAID-1)                       │
└─────────────────────────────────────────────────────┘
```

### Hypervisor responsibilities

- Provision and host the `apps` VM via `libvirt_provision` Ansible role.
- Export `/mnt/bulk/apps` via NFS (extend `nfsExports.exports` in
  `nix/hosts/hypervisor/configuration.nix`).
- Provide virtiofs key share for LUKS unlock.

### Apps VM responsibilities

- All compose stacks (except DNS and Unifi).
- Serve application traffic via Traefik (managed by the `backbone` stack or the ingress VM).
- Expose monitoring metrics to Prometheus.
- Backup data to remote restic repository using `services.restic.backups`.

---

## Data Layout

| Tier | Mount point | Backed by | Replaces (Ansible) | Notes |
|------|-----------|-----------|--------------------|-------|
| Local (fast) | `/var/lib/app-data` | VM OS disk (vmstore SSD RAID-1) | `/home/snyssen/data` | Databases, caches, config |
| Bulk (large) | `/mnt/bulk` | NFS → hypervisor `/mnt/bulk/apps` | `/mnt/storage` | Media, archives, large blobs |

### Per-stack data path mapping

> **TODO (Phase 0):** Fill in actual paths from current host inventory.

| Stack | Local path (`/var/lib/app-data/…`) | Bulk path (`/mnt/bulk/…`) |
|-------|------------------------------------|--------------------------|
| databases | `databases/` | — |
| monitoring | `monitoring/` | — |
| backbone | `backbone/` | — |
| immich | `immich/` | `immich/` |
| nextcloud | `nextcloud/` | `nextcloud/` |
| paperless | `paperless/` | `paperless/` |
| streaming | `streaming/` | `streaming/` (media library) |
| _…_ | _…_ | _…_ |

---

## Secrets Handling

All secrets are encrypted with SOPS (age key per host) and stored in
`nix/hosts/apps/data/secrets.yaml`.

### Secret categories

| Category | SOPS key path | Used by |
|----------|--------------|---------|
| User password hash | `users/snyssen/passwordHash` | NixOS user account |
| Tailscale auth key | `tailscale/authKey` | `tailscale` module |
| CrowdSec API key | `crowdsec-firewall-bouncer/api_key` | `crowdsec-firewall-bouncer` module |
| Restic repo password | `restic/repositoryPassword` | `services.restic.backups` |
| Per-stack secrets | `stacks/<name>/…` | `compose-stacks` `environmentFile` |

### Per-stack secrets

> **TODO (Phase 0 / per-stack):** Document required secrets per stack from the current
> Ansible vault / role defaults.

| Stack | Secret keys (SOPS path) |
|-------|------------------------|
| databases | `stacks/databases/postgresPassword`, `stacks/databases/mariadbRootPassword`, … |
| nextcloud | `stacks/nextcloud/adminPassword`, `stacks/nextcloud/dbPassword`, … |
| immich | `stacks/immich/dbPassword` |
| matrix | `stacks/matrix/registrationSecret`, … |
| _…_ | _…_ |

---

## Testing Strategy

Migration uses an **iterative, test-before-cutover** approach:

1. **Phase A — MVS deploy on test hypervisor**
   - Build a Minimum Viable System (MVS) for the `apps` VM.
   - Deploy to the current (test) hypervisor with minimal or partial data.
   - Verify base system: Tailscale, NFS mount, monitoring, Docker networking.
   - Iteratively migrate stacks one by one, testing each on the test VM.

2. **Phase B — Production cutover** *(separate epic)*
   - Final full backup of the current `snyssen.be` host.
   - Wipe production hardware and install `hypervisor` NixOS config.
   - Recreate all VMs (including `apps`) on the new hypervisor.
   - Restore data from backups.
   - DNS/Traefik cutover.
   - Decommission old Ansible-managed host.

### Not waiting for code completeness

We do **not** wait for all stacks to be migrated before testing. The MVS (Phase 2 checklist
items) is the gate for first test deployment. Stacks are added iteratively afterwards.

---

## VM Specifications

> **TODO (Phase 0):** Finalise resource allocation based on workload analysis.

| Parameter | Planned value | Notes |
|-----------|--------------|-------|
| Hostname | `apps` | |
| vCPUs | TBD | Benchmark current Ubuntu host load |
| RAM | TBD | |
| OS disk | TBD GB | Backed by vmstore SSD RAID-1 pool |
| NIC | `br0` | LAN bridge; VM gets own LAN IP |
| Tailscale tags | `["server"]` | TBD — expand as needed |

---

## Stack Inventory

> **TODO (Phase 0):** Complete inventory — dependencies, data paths, required secrets,
> migration status.

The current Ansible `stacks_deploy` role deploys the following stacks. Each row tracks
migration progress.

### Docker network requirements

All stacks below use one or more of the pre-created bridge networks:

| Network | Driver | Purpose |
|---------|--------|---------|
| `web` | bridge | Traefik ingress |
| `db` | bridge | Database access |
| `ldap` | bridge | LDAP/directory access |
| `monitoring` | bridge | Prometheus scraping |

The legacy `lan` ipvlan network is **not** recreated on the VM (Unifi is out of scope).

### Stack list

| Stack | Networks | Local data | Bulk data | Secrets | NFS needed | Status |
|-------|----------|-----------|-----------|---------|------------|--------|
| databases | db | ✅ | — | ✅ | No | 🔲 TODO |
| monitoring | monitoring | ✅ | — | — | No | 🔲 TODO |
| backbone | web | ✅ | — | ✅ | No | 🔲 TODO |
| crowdsec | web | ✅ | — | ✅ | No | 🔲 TODO |
| ddns | — | — | — | ✅ | No | 🔲 TODO |
| ntfy | web | ✅ | — | ✅ | No | 🔲 TODO |
| streaming | web | ✅ | ✅ | ✅ | Yes | 🔲 TODO |
| immich | web, db | ✅ | ✅ | ✅ | Yes | 🔲 TODO |
| paperless | web, db | ✅ | ✅ | ✅ | Yes | 🔲 TODO |
| nextcloud | web, db | ✅ | ✅ | ✅ | Yes | 🔲 TODO |
| actual-budget | web | ✅ | — | — | No | 🔲 TODO |
| recipes | web, db | ✅ | — | ✅ | No | 🔲 TODO |
| speedtest | web | ✅ | — | — | No | 🔲 TODO |
| dashboard | web | ✅ | — | ✅ | No | 🔲 TODO |
| personal_website | web | — | — | — | No | 🔲 TODO |
| quartz | web | — | — | — | No | 🔲 TODO |
| s-pdf | web | — | — | — | No | 🔲 TODO |
| foundryvtt | web | ✅ | — | ✅ | No | 🔲 TODO |
| minecraft | — | ✅ | — | ✅ | No | 🔲 TODO |
| syncthing | web | ✅ | ✅ | — | Yes | 🔲 TODO |
| team_wiki | web, db | ✅ | — | ✅ | No | 🔲 TODO |
| rallly | web, db | ✅ | — | ✅ | No | 🔲 TODO |
| speedtest-tracker | web, db | ✅ | — | ✅ | No | 🔲 TODO |
| sharkey | web, db | ✅ | ✅ | ✅ | Yes | 🔲 TODO |
| dawarich | web, db | ✅ | — | ✅ | No | 🔲 TODO |
| semaphore | web, db | ✅ | — | ✅ | No | 🔲 TODO |
| backrest | web | ✅ | — | — | No | 🔲 TODO |
| skyrim_together | — | ✅ | — | — | No | 🔲 TODO |
| matrix | web, db | ✅ | ✅ | ✅ | Yes | 🔲 TODO |
| attic | web, db | ✅ | — | ✅ | No | 🔲 TODO |
| mobilizon | web, db | ✅ | — | ✅ | No | 🔲 TODO |
| unifi | — | — | — | — | — | ❌ OUT OF SCOPE (separate VM) |

---

## Task Checklist

### Phase 0 — Planning & inventory

- [ ] **0.1** Complete stack inventory table above (data paths, secrets, dependencies)
- [ ] **0.2** Finalise VM resource allocation (vCPUs, RAM, disk size)
- [ ] **0.3** Decide which stacks stay on `apps` vs move to separate VMs
- [ ] **0.4** Document per-stack secrets (fill in secrets table above)
- [ ] **0.5** Identify and document inter-stack dependencies (shared DBs, shared volumes)

### Phase 1 — Hypervisor-side changes

- [ ] **1.1** Add NFS export `/mnt/bulk/apps` to `nix/hosts/hypervisor/configuration.nix`
- [ ] **1.2** Add `apps` VM definition to the `libvirt_provision` Ansible inventory/config
      - VM disk backed by `vmstore` SSD pool
      - NIC attached to `br0`
      - virtiofs key share for LUKS unlock

### Phase 2 — Apps VM MVS (Minimum Viable System) ✅ Scaffold created

- [x] **2.1** Create `nix/hosts/apps/configuration.nix` — base system skeleton
- [x] **2.2** Configure networking & Tailscale
- [x] **2.3** Configure storage: `/var/lib/app-data` + NFS `/mnt/bulk`
- [x] **2.4** Configure security: `crowdsec-firewall-bouncer`
- [x] **2.5** Configure monitoring: `prometheus-node-exporter` + `grafana-alloy`
- [x] **2.6** Configure Docker + `docker-networks` module (web/db/ldap/monitoring)
- [ ] **2.7** Create `nix/hosts/apps/data/secrets.yaml` (SOPS-encrypted with real secrets)
- [ ] **2.8** Generate `nix/hosts/apps/hardware-configuration.nix` on first boot
- [ ] **2.9** Test that `nixos-rebuild build` succeeds for the `apps` host

### Phase 3 — Docker network module

- [x] **3.1** Create `nix/modules/nixos/docker-networks.nix`
      — declarative module to pre-create named Docker bridge networks as systemd oneshot services

### Phase 4 — Backup configuration

- [ ] **4.1** Configure `services.restic.backups` for `/var/lib/app-data` and critical NFS paths
- [ ] **4.2** Configure SOPS secrets for restic repository password and credentials
- [ ] **4.3** Add pre-backup database dump hooks (PostgreSQL, MariaDB)
- [ ] **4.4** (Optional) Add `backrest` compose stack for backup browsing

### Phase 5 — Compose stacks migration (per-stack)

For each stack, the work is:
1. Create `nix/hosts/apps/compose/<stack>/docker-compose.yaml` (adapted from Ansible role)
2. Add `compose-stacks.stacks.<stack>` entry in `configuration.nix`
3. Wire SOPS secrets via `environmentFile`
4. Adjust volume paths: `{{ docker_mounts_directory }}/…` → `/var/lib/app-data/…`,
   `/mnt/storage/…` → `/mnt/bulk/…`
5. Add `extraAfter` for NFS-dependent stacks

Recommended migration order (infrastructure first):

- [ ] **5.1** databases
- [ ] **5.2** monitoring (cAdvisor)
- [ ] **5.3** backbone
- [ ] **5.4** crowdsec
- [ ] **5.5** ddns
- [ ] **5.6** ntfy
- [ ] **5.7** speedtest / speedtest-tracker
- [ ] **5.8** dashboard
- [ ] **5.9** actual-budget
- [ ] **5.10** s-pdf
- [ ] **5.11** semaphore
- [ ] **5.12** recipes
- [ ] **5.13** team_wiki / rallly
- [ ] **5.14** personal_website / quartz
- [ ] **5.15** foundryvtt / minecraft / skyrim_together
- [ ] **5.16** syncthing
- [ ] **5.17** immich
- [ ] **5.18** paperless
- [ ] **5.19** nextcloud
- [ ] **5.20** streaming
- [ ] **5.21** sharkey
- [ ] **5.22** matrix
- [ ] **5.23** dawarich
- [ ] **5.24** mobilizon
- [ ] **5.25** attic
- [ ] **5.26** backrest

### Phase 6 — Production cutover *(separate epic)*

- [ ] **6.1** Final full backup of current `snyssen.be` host
- [ ] **6.2** Wipe production hardware and install `hypervisor` NixOS config
- [ ] **6.3** Recreate all VMs on new hypervisor (including `apps`)
- [ ] **6.4** Restore data from backups to `/var/lib/app-data` and `/mnt/bulk`
- [ ] **6.5** DNS/Traefik cutover (update ingress Traefik config)
- [ ] **6.6** Verify all stacks running correctly
- [ ] **6.7** Decommission old Ansible-managed host (or repurpose)

### Phase 7 — Cleanup

- [ ] **7.1** Archive or remove obsolete Ansible roles (`stacks_deploy`, `setup_storage`,
      `setup_common` portions now handled by Nix)
- [ ] **7.2** Update documentation (README, `docs/index.md`, module docs)
- [ ] **7.3** Remove `snyssen.be` from Ansible inventory

---

## References

- [Hypervisor plan](./plan.md)
- [Hypervisor overview](./overview.md)
- [NixOS modules — compose-stacks](../../nix/modules/nixos/compose-stacks.nix)
- [NixOS modules — nfs-mounts](../../nix/modules/nixos/nfs-mounts.nix)
- [NixOS modules — docker-networks](../../nix/modules/nixos/docker-networks.nix)
- [Disko layout — single-btrfs-luks-virtiofs-key](../../nix/modules/nixos/disko/layouts/single-btrfs-luks-virtiofs-key.nix)
- [Ansible stacks\_deploy role](../../ansible/roles/stacks_deploy/)
- [Current apps host Ansible playbook](../../ansible/playbooks/setup-deploy.ansible.yml)
