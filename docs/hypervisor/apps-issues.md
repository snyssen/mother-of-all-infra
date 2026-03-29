# apps VM Migration — GitHub Issue Bodies

This file contains paste-ready bodies for creating the GitHub epic and sub-issues that track the `apps` VM migration.
Copy each section's body into the GitHub issue creation UI.

---

## Epic

**Title:** `feat: migrate apps server to NixOS VM under hypervisor`

**Body:**

```markdown
## Goal

Migrate the current bare-metal Ubuntu apps server (`snyssen.be`), managed entirely through Ansible, to a NixOS VM named **`apps`** running under the hypervisor host.

The new VM follows the same patterns established by the `scrypted` VM: NixOS + disko + SOPS + compose-stacks module + libvirt provisioning.

## Scope

- **In scope:** All ~33 Docker Compose stacks currently deployed by the `stacks_deploy` Ansible role, the OS and storage configuration, monitoring, backups, and secrets management.
- **Out of scope:** DNS migration (tracked in #153); Unifi (moves to a dedicated Unifi OS Server VM); production cutover (tracked in a future Phase B epic).

## Architecture Decisions

| Concern | Decision |
|---------|----------|
| Hostname | `apps` |
| Local app data | `/var/lib/app-data` (OS btrfs disk) |
| Bulk data | `/mnt/bulk` — NFS mount of `/mnt/bulk/apps` on hypervisor |
| Compose path | `nix/hosts/apps/compose/${stack}/docker-compose.yaml` |
| Docker networks | `web`, `db`, `ldap`, `monitoring` bridge networks via new `docker-networks` NixOS module |
| `lan` ipvlan | **Not recreated** — Unifi → dedicated VM; Syncthing → regular bridge |
| Monitoring | `prometheus-node-exporter` + `grafana-alloy` (NixOS modules) + `cAdvisor` (new NixOS module) |
| Backups | `services.restic.backups` (NixOS native); restores via `restic` CLI |
| VM provisioning | `libvirt_provision` Ansible role |

## Approach

Two-phase strategy driven by hardware constraints:

- **Phase A (this epic):** Code-complete the apps VM config; test iteratively on the current test hypervisor with partial data.
- **Phase B (future epic):** Final backup → wipe production server → install hypervisor → recreate VMs → restore data.

## Planning document

See [`docs/hypervisor/apps-migration-plan.md`](docs/hypervisor/apps-migration-plan.md) for full details.

## Sub-issues

- [ ] Phase 0 — Create migration planning document
- [ ] Phase 0 — Inventory stacks, data, and secrets
- [ ] Phase 1 — Hypervisor: add NFS export and provision VM
- [ ] Phase 2 — Create apps base NixOS MVS configuration
- [ ] Phase 3 — Add `docker-networks` NixOS module
- [ ] Phase 3 — Add `cadvisor` NixOS module
- [ ] Phase 4 — Configure restic backups
- [ ] Phase 5 — Migrate compose stacks
- [ ] Phase 5 — Iterative test plan
```

---

## Sub-issue 1 of 9

**Title:** `[apps] Phase 0 — Create migration planning document`

**Body:**

```markdown
## Objective

Create a comprehensive migration planning document at `docs/hypervisor/apps-migration-plan.md`.

## Tasks

- [ ] Document the full architecture decisions (hostname, data paths, networks, monitoring, backups)
- [ ] List all stacks currently deployed and their disposition (migrate / exclude / defer)
- [ ] Document current → new data path mapping (`/home/snyssen/data` → `/var/lib/app-data`, `/mnt/storage` → `/mnt/bulk`)
- [ ] List required NixOS modules (existing vs. new)
- [ ] Document hypervisor changes required (NFS export + VM provisioning config)
- [ ] Include per-stack migration checklist template
- [ ] Document iterative testing strategy

## Acceptance Criteria

- `docs/hypervisor/apps-migration-plan.md` exists and is merged
- All key decisions are recorded and rationale is clear
```

---

## Sub-issue 2 of 9

**Title:** `[apps] Phase 0 — Inventory stacks, data, and secrets`

**Body:**

```markdown
## Objective

Perform a detailed inventory of the current apps server before touching any code.

## Tasks

- [ ] For each of the ~33 stacks, document:
  - Data directories under `/home/snyssen/data` (size, purpose)
  - Data directories under `/mnt/storage` (size, purpose)
  - Inter-stack dependencies (shared DB containers, networks, volume references)
  - Required secrets (API keys, DB passwords, SMTP credentials, etc.)
- [ ] Identify stacks that should **not** migrate to the `apps` VM (e.g. candidates for their own VM or retirement)
- [ ] Estimate VM resource requirements (vCPUs, RAM, OS disk size) based on current usage
- [ ] Decide on VM MAC address for DHCP reservation
- [ ] List all secrets that need to be moved into `nix/hosts/apps/data/secrets.yaml`

## Output

A completed inventory section in `docs/hypervisor/apps-migration-plan.md` (or a linked companion document) that Phase 5 stack migration sub-tasks can reference.
```

---

## Sub-issue 3 of 9

**Title:** `[apps] Phase 1 — Hypervisor: add NFS export and provision VM`

**Body:**

```markdown
## Objective

Prepare the hypervisor to host the `apps` VM and export its bulk data directory.

## Tasks

### NFS export (`nix/hosts/hypervisor/configuration.nix`)

- [ ] Add `/mnt/bulk/apps` to `nfsExports.exports`:

```nix
nfsExports.exports = [
  { path = "/mnt/bulk/scrypted"; }  # existing
  { path = "/mnt/bulk/apps"; }       # new
];
```

- [ ] Run `nh os switch` on hypervisor to apply
- [ ] Verify export is visible: `showmount -e hypervisor`

### VM provisioning (`ansible/hosts/host_vars/hypervisor/vars.yml`)

- [ ] Add `apps` VM entry to `libvirt_vms` list (use values from Phase 0 capacity planning):

```yaml
- name: apps
  vcpu: 4
  ram_mb: 8192
  mac_address: "52:54:00:XX:XX:XX"
  disk_gb: 128
  virtiofs_luks_key:
    enable: true
  iso_image:
    url: "https://channels.nixos.org/nixos-25.11/latest-nixos-minimal-x86_64-linux.iso"
    dest: "/mnt/vmstore/apps/installer.iso"
    enable_mount: false
```

- [ ] Run `just ansible-playbook playbook=libvirt-provision flags='-i hosts/prod.yml'`
- [ ] Verify VM is defined and boots to NixOS installer: `virsh list --all`

## Acceptance Criteria

- NFS export `/mnt/bulk/apps` is visible on the hypervisor
- `apps` VM is defined in libvirt, boots, and is accessible via VNC/console
```

---

## Sub-issue 4 of 9

**Title:** `[apps] Phase 2 — Create apps base NixOS MVS configuration`

**Body:**

```markdown
## Objective

Create a Minimum Viable System (MVS) NixOS configuration for the `apps` VM: everything needed to have a working, secured, monitored host — but **no compose stacks yet**.

## Tasks

### Files to create

- [ ] `nix/hosts/apps/configuration.nix` — main system config (see structure below)
- [ ] `nix/hosts/apps/hardware-configuration.nix` — generated after first boot via `nixos-generate-config`
- [ ] `nix/hosts/apps/data/secrets.yaml` — SOPS-encrypted secrets (user password hashes, Tailscale auth key, CrowdSec API key)

### `configuration.nix` structure

```nix
imports = [
  flake.modules.nixos.disko          # single-btrfs-luks-virtiofs-key layout
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
  flake.modules.nixos.docker-networks   # Phase 3
  flake.modules.nixos.cadvisor          # Phase 3
  flake.modules.nixos.nfs-mounts
  flake.modules.nixos.compose-stacks
];

disko.layout = "single-btrfs-luks-virtiofs-key";

nfsMounts.enable = true;
nfsMounts.mounts.bulk = {
  path = "/mnt/bulk";
  host = "hypervisor";
  remotePath = "/mnt/bulk/apps";
  dependsOn.tailscale = true;
};
```

### Install steps

- [ ] Install NixOS on the VM: `just nix-remote-install apps`
- [ ] Verify host is reachable via Tailscale SSH
- [ ] Verify NFS mount `/mnt/bulk` is working
- [ ] Verify node exporter metrics are scraped by Prometheus
- [ ] Verify Alloy is collecting logs

## Acceptance Criteria

- NixOS boots successfully on the `apps` VM
- Tailscale SSH works
- NFS bulk mount is accessible
- Monitoring is active (node exporter + Alloy)
- CrowdSec bouncer is running
```

---

## Sub-issue 5 of 9

**Title:** `[apps] Phase 3 — Add docker-networks NixOS module`

**Body:**

```markdown
## Objective

Create a reusable NixOS module (`nix/modules/nixos/docker-networks.nix`) that pre-creates named Docker bridge networks as systemd oneshot services, ensuring they exist before any compose stack starts.

## Background

The current Ansible `stacks_deploy` role creates four Docker bridge networks (`web`, `db`, `ldap`, `monitoring`) before deploying any stack. In NixOS, compose stack systemd services need these networks to already exist when they start.

## Tasks

- [ ] Create `nix/modules/nixos/docker-networks.nix` with:
  - `dockerNetworks.networks` option: list of network names to create
  - One `systemd.services.docker-network-<name>` oneshot service per network
  - Services `After = [ "docker.service" ]` and `Before` any compose stack service
  - Idempotent: use `docker network create --driver bridge <name> || true`
- [ ] Register the module in `flake.nix` / `nix/modules/nixos/default.nix`
- [ ] Use the module in `nix/hosts/apps/configuration.nix`:

```nix
dockerNetworks.networks = [ "web" "db" "ldap" "monitoring" ];
```

- [ ] Update `compose-stacks` module (or apps config) so stack services `After` + `Requires` the relevant network units

## Acceptance Criteria

- `docker network ls` on the apps VM shows `web`, `db`, `ldap`, `monitoring` after rebuild
- Compose stacks that use these networks start without "network not found" errors
```

---

## Sub-issue 6 of 9

**Title:** `[apps] Phase 3 — Add cadvisor NixOS module`

**Body:**

```markdown
## Objective

Create a NixOS module (`nix/modules/nixos/cadvisor.nix`) to run [cAdvisor](https://github.com/google/cadvisor) for Docker container metrics, replacing the current `container_cadvisor` Ansible role.

## Background

cAdvisor exposes per-container CPU, memory, network, and filesystem metrics in Prometheus format. It is currently deployed as a container by the `container_cadvisor` Ansible role. On the NixOS apps VM it should run as a native service (or via `virtualisation.oci-containers`) alongside the `prometheus-node-exporter` module.

## Tasks

- [ ] Create `nix/modules/nixos/cadvisor.nix`:
  - Use `virtualisation.oci-containers.containers.cadvisor` (or a direct systemd service with the cAdvisor binary from nixpkgs if available)
  - Mount `/var/run/docker.sock`, `/sys`, `/var/lib/docker` (read-only where possible)
  - Expose metrics on port `8080` (default cAdvisor port)
  - Enable option: `cadvisor.enable`
- [ ] Register the module in `flake.nix` / `nix/modules/nixos/default.nix`
- [ ] Enable in `nix/hosts/apps/configuration.nix`
- [ ] Verify Prometheus can scrape `<apps-ip>:8080/metrics`

## Acceptance Criteria

- cAdvisor is running after NixOS rebuild
- Container metrics are visible in Grafana
```

---

## Sub-issue 7 of 9

**Title:** `[apps] Phase 4 — Configure restic backups`

**Body:**

```markdown
## Objective

Replace the current `autorestic`-based cron backup setup with NixOS-native `services.restic.backups` on the `apps` VM.

## Background

The current apps server uses `autorestic` (a restic wrapper) with cron jobs defined in the `setup_backups` Ansible role. NixOS provides `services.restic.backups` which offers:
- Declarative backup job definitions
- Systemd timers (replacing cron)
- Pre/post backup hooks (for DB dumps, etc.)
- SOPS-managed repository passwords

## Tasks

- [ ] Add `services.restic.backups` configuration to `nix/hosts/apps/configuration.nix` (or a dedicated included file):
  - Backup job for `/var/lib/app-data` (local data)
  - Backup job for critical secrets/config
  - Pre-backup hook for PostgreSQL dumps (`pg_dumpall` or per-DB)
  - Pre-backup hook for MariaDB dumps
  - Repository password from `nix/hosts/apps/data/secrets.yaml` via SOPS
  - Schedule: daily backup, weekly prune
- [ ] Verify backup jobs run successfully: `systemctl status restic-backups-*.service`
- [ ] Document restore procedure (CLI-based) in `docs/backups.md` or the migration plan
- [ ] (Optional) Deploy `backrest` compose stack as a read-only snapshot browser

## SOPS secrets needed

```yaml
restic/repository-password: <password>
restic/b2-account-id: <id>       # or other backend credentials
restic/b2-account-key: <key>
```

## Acceptance Criteria

- At least one successful backup run is confirmed
- Backup repo is accessible and browsable via `restic snapshots`
- Restore procedure is documented
```

---

## Sub-issue 8 of 9

**Title:** `[apps] Phase 5 — Migrate compose stacks`

**Body:**

```markdown
## Objective

Migrate all applicable Docker Compose stacks from the Ansible `container_*` roles to `nix/hosts/apps/compose/<stack>/docker-compose.yaml` files managed by the `compose-stacks` NixOS module.

## Stacks to migrate (in suggested order)

### Infrastructure (migrate first — others depend on these)
- [ ] `databases` — PostgreSQL + MariaDB + Redis
- [ ] `monitoring` — Prometheus + Grafana
- [ ] `backbone` — Traefik + authentik
- [ ] `crowdsec` — CrowdSec security engine
- [ ] `ddns` — Dynamic DNS
- [ ] `ntfy` — Push notifications

### Productivity
- [ ] `nextcloud`
- [ ] `paperless`
- [ ] `actual-budget`
- [ ] `recipes`
- [ ] `team_wiki`
- [ ] `rallly`
- [ ] `s-pdf`
- [ ] `semaphore`
- [ ] `dashboard`

### Media / Photos
- [ ] `immich`
- [ ] `streaming` (Jellyfin + Gluetun VPN + *arr stack)

### Social / Communication
- [ ] `matrix`
- [ ] `sharkey`
- [ ] `mobilizon`

### Personal / Tools
- [ ] `personal_website`
- [ ] `quartz` (remove Syncthing dependency)
- [ ] `dawarich`
- [ ] `attic` (Nix binary cache)
- [ ] `syncthing` (drop `lan` network; use regular bridge)
- [ ] `speedtest`
- [ ] `speedtest-tracker`

### Gaming (on-demand)
- [ ] `foundryvtt`
- [ ] `minecraft`
- [ ] `skyrim_together`

### Optional / deferred
- [ ] `backrest` (read-only backup browser)

## Per-stack checklist (for each stack above)

1. Copy `docker-compose.yml` from `ansible/roles/container_<name>/` to `nix/hosts/apps/compose/<name>/docker-compose.yaml`
2. Replace `{{ docker_mounts_directory }}` → `/var/lib/app-data`, `/mnt/storage` → `/mnt/bulk`
3. Remove `lan` network references if present
4. Extract all secrets to `nix/hosts/apps/data/secrets.yaml`
5. Add `compose-stacks.stacks.<name>` entry in `configuration.nix`
6. Add `extraAfter = [ "mnt-bulk.mount" ]` for stacks using `/mnt/bulk`
7. Verify stack starts cleanly on test VM

## Excluded stacks

- `unifi` — moves to dedicated Unifi OS Server VM
- `scrypted` — already its own NixOS VM
- DNS stacks — tracked in issue #153

## Acceptance Criteria

- All applicable stacks start successfully on the test VM
- Data volumes are correctly mapped to new paths
- Secrets are managed via SOPS (no plaintext secrets in compose files)
```

---

## Sub-issue 9 of 9

**Title:** `[apps] Phase 5 — Iterative test plan`

**Body:**

```markdown
## Objective

Define and execute an iterative test plan for the apps VM on the current (test) hypervisor before committing to production cutover.

## Test phases

### T1 — MVS boot test (after Phase 2)

- [ ] VM boots successfully from NixOS install
- [ ] Tailscale SSH accessible
- [ ] NFS `/mnt/bulk` mount works
- [ ] Node exporter metrics scraped
- [ ] Alloy log collection working
- [ ] CrowdSec bouncer running
- [ ] Docker daemon running
- [ ] `web`, `db`, `ldap`, `monitoring` networks exist (`docker network ls`)

### T2 — Infrastructure stacks test (after migrating databases/backbone/monitoring)

- [ ] `databases` stack: PostgreSQL and MariaDB accept connections
- [ ] `backbone` stack: Traefik is routing and authentik is reachable
- [ ] `monitoring` stack: Prometheus scrapes all targets (node exporter, cAdvisor, Traefik, apps)
- [ ] `crowdsec` + `ddns` + `ntfy`: running without errors

### T3 — Data path test (partial restore)

- [ ] Restore a small dataset from current apps server (e.g., a test Nextcloud instance, a Postgres DB dump)
- [ ] Verify data is accessible at new paths (`/var/lib/app-data`, `/mnt/bulk`)
- [ ] Verify backup job runs and creates a new snapshot

### T4 — Full stack test

- [ ] All migrated stacks start without errors
- [ ] A sample of services are functionally tested (Nextcloud login, Jellyfin media scan, authentik login)
- [ ] Traefik routing works for at least the core stacks

### T5 — Resilience test

- [ ] VM is rebooted; all stacks come back automatically
- [ ] NFS mount reconnects after reboot (Tailscale dependency)
- [ ] A manual restic restore is performed from backup

## Notes

- All testing is on the **test hypervisor** only — no DNS changes, no production traffic
- Production cutover is tracked separately in the Phase B epic
```

---

> **How to create these issues:**
> 
> 1. Go to https://github.com/snyssen/mother-of-all-infra/issues/new
> 2. Copy the title and body for each issue above
> 3. Create sub-issues first, note their issue numbers
> 4. Update the epic body's sub-issue list with the actual issue numbers before creating the epic
> 
> Or using the GitHub CLI (when network access is available):
> ```sh
> gh issue create --title "[apps] Phase 0 — Create migration planning document" \
>   --body-file docs/hypervisor/apps-issues.md \
>   --repo snyssen/mother-of-all-infra
> ```
