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
| `quartz` | Quartz digital garden (static) | ⛔ Exclude - Outdated stack |
| `s-pdf` | Stirling PDF tools | ✅ Migrate |
| `foundryvtt` | FoundryVTT TTRPG platform | ✅ Migrate |
| `minecraft` | Minecraft server | ✅ Migrate |
| `syncthing` | File sync | ⛔ Exclude - Will move to syncthing Nix module |
| `team_wiki` | Wiki.js team wiki | ✅ Migrate |
| `rallly` | Meeting scheduler | ✅ Migrate |
| `speedtest-tracker` | Speedtest tracker | ✅ Migrate |
| `sharkey` | Misskey fork (ActivityPub) | ✅ Migrate |
| `dawarich` | Location history tracker | ✅ Migrate |
| `semaphore` | Ansible Semaphore UI | ✅ Migrate |
| `backrest` | Restic backup browser GUI | ⚠️ Migrate as read-only browse UI (restores via CLI) |
| `skyrim_together` | Skyrim Together Reborn server | ✅ Migrate (on-demand only) |
| `matrix` | Matrix homeserver (Synapse) + bridges | ✅ Migrate |
| `attic` | Nix binary cache (Attic server) | ⛔ Exclude - Makes more sense as a nix module (dedicated VM?) |
| `mobilizon` | Federated events platform | ✅ Migrate |
| `scrypted` | NVR / camera bridge | ⛔ Exclude — already its own NixOS VM |

---

## Phase 0 Inventory Worksheet (to fill from live server)

### Per-stack inventory

| Stack | `/home/snyssen/data` dirs (size, purpose) | `/mnt/storage` dirs (size, purpose) | Inter-stack dependencies (DB/network/volumes) | Required secrets (to move into `nix/hosts/apps/data/secrets.yaml`) | Target (`apps` / dedicated VM / retire) |
|---|---|---|---|---|---|
| `databases` | `/home/snyssen/data/databases/postgres/data` (size: live measure; PostgreSQL data), `/home/snyssen/data/databases/postgres/{servers.json,config_local.py}` (pgAdmin config) | `/mnt/storage/backups` (shared backup root), `/mnt/storage/backups/postgres` (Postgres dumps) | Uses `db` and `web` networks; `pgadmin` + `postgres_backups` depend on `postgres`; provides shared `postgres` for many stacks | `db__pg_password`, `db__pgadmin_password`, `db__pgadmin_email` | `apps` |
| `monitoring` | `/home/snyssen/data/monitoring/prometheus` (Prometheus TSDB), `/home/snyssen/data/grafana/data` (Grafana DB), `/home/snyssen/data/monitoring/loki` (logs), `/home/snyssen/data/uptime` (Uptime Kuma state) | `/mnt/storage/prometheus` (Prometheus config/rules) | Uses `web`, `monitoring`, `db`; `umami` connects to `postgres`; consumes ntfy topic for alerts; OIDC via Authelia | `monitoring__umami_db_pass`, `monitoring__umami_app_secret`, `backbone__authelia__oidc_grafana_clientsecret`, `smtp__pass` | `apps` |
| `backbone` | `/home/snyssen/data/traefik` (cert storage), `/home/snyssen/data/authelia/config` (Authelia config) | none in compose | Uses `web`, `db`, `ldap`, `monitoring`, `authelia`; `lldap` uses shared `postgres`; central ingress/auth dependency for almost all stacks | `backbone__lldap__db_user`, `backbone__lldap__db_pass`, `backbone__lldap__jwt_secret`, `backbone__lldap__key_seed` (+ Authelia secrets from mounted config) | `apps` |
| `unifi` | `/home/snyssen/data/unifi/config` (controller config), `/home/snyssen/data/unifi/mongodb` (MongoDB data), `/home/snyssen/data/unifi/init-mongo.js` (init script) | none in compose | Unifi app depends on `unifi-db`; uses `web` plus L2/L3 discovery + controller ports (TCP/UDP) | `unifi__mongo_pass`, `unifi__mongo_root_pass` | `dedicated VM` |
| `crowdsec` | `/home/snyssen/data/crowdsec/crowdsec` (config), `/home/snyssen/data/crowdsec/data` (runtime data), `/home/snyssen/data/crowdsec-web-ui/data` (UI db) | none in compose | Uses `web` (and `db` external network defined); integrates with Traefik + Authelia logs/parsers | `crowdsec__firewall_bouncer__api_key`, `crowdsec__webui_user`, `crowdsec__webui_password` | `apps` |
| `ntfy` | `/home/snyssen/data/ntfy/cache` (cache), `/home/snyssen/data/ntfy/auth` (users/tokens DB) | none in compose | Uses `web`; downstream dependency for alerting/notifications (`monitoring`, scripts) | `ntfy__users_entries`, `ntfy__tokens_entries`, `ntfy__topics_entries` | `apps` |
| `streaming` | `/home/snyssen/data/jellyfin/{data,config,cache,logs}`, `/home/snyssen/data/audiobookshelf/{config,metadata}`, `/home/snyssen/data/{sonarr,radarr,lidarr,prowlarr,bazarr,pinchflat,lidatube,lidify}/config`, `/home/snyssen/data/peertube/{config,redis}`, `/home/snyssen/data/gluetun` | `/mnt/storage/streaming` (media/arr/torrent/usenet/peertube data), `/mnt/storage/torrent`, `/mnt/storage/usenet` | Uses `web`, `monitoring`, `lan`, `db`; many services depend on `vpn`; `peertube`/`audiomuse` use shared `postgres`; local Redis services for `peertube` + `audiomuse` | `peertube__db_password`, `peertube__secret`, `peertube__oidc_client_secret`, `audiomuse__db_password`, `vpn__wireguard_pk`, `vpn__control_server_api_key`, `smtp__pass` | `apps` |
| `immich` | `/home/snyssen/data/immich/postgres` (Immich Postgres data) | `/mnt/storage/photos` (library uploads), `/mnt/storage/backups/immich` (DB dumps) | Uses `web` + `db`; `immich_server` depends on internal `redis`; DB backup sidecar | `immich__db_password` | `apps` |
| `paperless` | `/home/snyssen/data/paperless/redis` (redis data), `/home/snyssen/data/paperless/data` (app data) | `/mnt/storage/paperless/{media,export,consume}` (documents/import/export) | Uses `web` + `db`; depends on internal `paperless_redis`; app DB host is shared `postgres`; OIDC via Authelia | `paperless__postgres_password`, `paperless__secret_key`, `backbone__authelia__oidc_paperless_clientsecret` | `apps` |
| `nextcloud` | none in compose (state is mounted from `/mnt/storage`) | `/mnt/storage/nextcloud` (Nextcloud data/code), `/mnt/storage/nextcloud_logs`, `/mnt/storage/paperless`, `/mnt/storage/streaming/media` | Uses `web`, `monitoring`, `db`, `lan`; depends on internal `nextcloud_redis`; app DB host is shared `postgres` | `nextcloud__postgres_password`, `nextcloud__nextcloud_password`, `nextcloud__nextcloud_admin` | `apps` |
| `actual-budget` | `/home/snyssen/data/actual-budget` (app data) | none in compose | Uses `web`; OIDC against Authelia (`auth.<domain>`) | `backbone__authelia__oidc_actual_budget_clientsecret` | `apps` |
| `recipes` | none in compose | `/mnt/storage/recipes/{staticfiles,mediafiles}` | Uses `web` + `db`; app DB host is shared `postgres`; OIDC via Authelia | `recipes__secret_key`, `recipes__db_password`, `backbone__authelia__oidc_recipes_clientsecret` | `apps` |
| `speedtest` | none in compose | none in compose | Uses `web` only | none in compose | `apps` |
| `dashboard` | none in compose (container uses `.env`) | none in compose | Uses `web`; operationally depends on URLs/services from many other stacks | `dashboard__open_weather_key` (from role `.env` template) | `apps` |
| `personal_website` | none in compose | none in compose | Uses `web` only | none in compose | `apps` |
| `quartz` | dynamic bind mount from `vault.path` (size: live measure; vault content), not fixed to one base dir in compose | depends on configured `vault.path` value (currently points into `/mnt/storage/syncthing/...` in vars) | Uses `web`; protected with `authelia@docker` middleware | no intrinsic app secret in compose; uses `vault.name`/`vault.path` metadata | `retire` |
| `s-pdf` | `/home/snyssen/data/s-pdf/ocr` (OCR language data), `/home/snyssen/data/s-pdf/config` (app config) | none in compose | Uses `web`; behind Authelia middleware | none in compose | `apps` |
| `foundryvtt` | `/home/snyssen/data/foundryvtt` (worlds/modules/data) | none in compose | Uses `web`; Authelia-protected route | `foundryvtt__password`, `foundryvtt__admin_key` (and username for bootstrap) | `apps` |
| `minecraft` | none in compose | `/mnt/storage/minecraft/data`, `/mnt/storage/mc-usw/data` | Uses `web` + `lan`; `mc-router` depends on `minecraft` + `mc-usw`; exposes game + dynmap routes | no secret in compose (game settings are non-secret vars) | `apps` |
| `syncthing` | `/home/snyssen/data/syncthing/config` | `/mnt/storage/syncthing/data` | Uses `web` + `lan` + UDP discovery entrypoints; no DB dependency | none in compose | `apps` |
| `team_wiki` | none in compose | none in compose | Uses `web`, `db`, `ldap`; app DB host is shared `postgres` | `team_wiki__db_pass` | `apps` |
| `rallly` | none in compose | none in compose | Uses `web` + `db`; app DB host is shared `postgres`; OIDC via team-domain Authelia | `rallly__db_pass`, `rallly__secret`, `backbone__authelia__oidc_rallly_clientsecret`, `smtp__pass` | `apps` |
| `speedtest-tracker` | `/home/snyssen/data/speedtest-tracker` (`/config` volume) | none in compose | Uses `web` + `db`; DB host is shared `postgres`; SMTP for notifications | `speedtest_tracker__app_key`, `speedtest_tracker__db_pass`, `smtp__pass` | `apps` |
| `sharkey` | `/home/snyssen/data/sharkey/config` (ro config), `/home/snyssen/data/sharkey/redis` | `/mnt/storage/sharkey/files` (uploads/files) | Uses `web` + `db`; internal redis dependency | no active secret in compose (secrets likely in mounted config files) | `apps` |
| `dawarich` | `/home/snyssen/data/dawarich/{shared,postgres,photon}` | `/mnt/storage/dawarich/{public,watched,storage}`, `/mnt/storage/backups/dawarich` | Uses `web` + `db`; app + sidekiq depend on `dawarich_db` and `dawarich_redis`; OIDC via Authelia | `dawarich__db_pass`, `backbone__authelia__oidc_dawarich_clientsecret`, `smtp__pass` | `apps` |
| `semaphore` | none in compose | `/mnt/storage/semaphore/config` (`/etc/semaphore`) | Uses `web` + `db` (shared `postgres`) | `semaphore__admin_pass`, `semaphore__encryption_key` | `apps` |
| `backrest` | `/home/snyssen/data/backrest/{data,config,cache,tmp}` | none in compose | Uses `web`; Authelia-protected UI; backup repositories configured via mounted config | no required compose secret currently (credentials expected in app config) | `apps` |
| `skyrim_together` | none in compose | `/mnt/storage/skyrim_together/{config,logs,Data}` | Uses `web` network with UDP Traefik entrypoint; no DB dependency | none in compose | `apps` |
| `matrix` | `/home/snyssen/data/matrix/maubot/dbs` | `/mnt/storage/matrix/{synapse,mas,element/config.json,matrix_discord,matrix_signal,matrix_whatsapp,matrix_meta,maubot}` | Uses `web` + `db`; bridges and maubot rely on mounted config/data; MAUBOT has dedicated route | no direct Jinja secrets in compose (secrets likely in mounted Matrix config files) | `apps` |
| `attic` | none under `/home/snyssen/data` in compose | `/mnt/storage/attic/{attic.toml,storage}` | Uses `web` (+ `db` network declared external); routed via Traefik | no Jinja secret in compose; sensitive values likely in `/mnt/storage/attic/attic.toml` | `dedicated VM` |
| `mobilizon` | `/home/snyssen/data/mobilizon/postgres` (DB data) | `/mnt/storage/backups/mobilizon` (DB dumps), `/mnt/storage/mobilizon/uploads`, `/mnt/storage/mobilizon/config.exs` | Uses `web` + `db`; app depends on `mobilizon_db`; DB backup sidecar | `mobilizon__db_pass`, `mobilizon__secret_key_base`, `mobilizon__secret_key`, `smtp__pass` | `apps` |
| `scrypted` | `/home/snyssen/data/scrypted` (server volume) | `/mnt/storage/scrypted/nvr` | Uses `web`; LAN/hardware-oriented workload already split to own VM | no Jinja secrets in compose | `dedicated VM` |

### Stacks not migrating to `apps` VM

| Stack | Current rationale | Final decision (confirm) | Notes |
|---|---|---|---|
| `unifi` | Already targeted for dedicated Unifi OS VM | `dedicated VM` | N/A |
| `scrypted` | Already on its own NixOS VM | `dedicated VM` | N/A |
| `quartz` | Marked excluded in current inventory (`Outdated stack`) | `retire` | Keep data source available; stop compose deployment |
| `syncthing` | Marked excluded from compose migration | `apps` | Recreate as NixOS module, not as compose stack |
| `attic` | Marked excluded from compose migration (`nix module` path) | `dedicated VM` | Decide final host/module placement in follow-up |

### VM capacity sizing worksheet

Collect live metrics from current apps host and fill:

| Metric | Observed current usage | Headroom policy | Proposed `apps` VM |
|---|---|---|---|
| vCPU | `2` | `2` | `4` (test hardware), `6` (prod hardware) |
| RAM | `26GiB` | `8GiB` | `8GiB` (test hardware), `48GiB` (prod hardware) |
| OS/data disk (`/var/lib/app-data`) | `600GiB` | `500GiB` | `300GiB` (test hardware), `2TiB` (prod hardware) |
| Bulk disk (`/mnt/bulk` via NFS) | `11TiB` | `2TiB` | `1TiB` (test hardware), `20TiB` (prod hardware) |

### DHCP reservation / MAC decision

- Chosen MAC address for `apps`: `52:54:00:00:00:01` (QEMU OUI format `52:54:00:xx:xx:xx`)
- Reservation target: `192.168.1.10` (DHCP server / static lease reference)
- Collision check done: ✅

### Secrets migration index (`nix/hosts/apps/data/secrets.yaml`)

Track every secret key/value that must move to SOPS:

| Stack | Secret names / purpose | Source today (vault/env/file) | Destination key path in `secrets.yaml` | Rotated during migration? |
|---|---|---|---|---|
| `databases` | `db__pg_password` (postgres/admin + backup sidecar), `db__pgadmin_password` | Vault-backed Ansible vars used in `templates/docker-compose.yml` | `stacks.databases.pg.password`, `stacks.databases.pgadmin.password` | No |
| `monitoring` | `smtp__pass` (Grafana mail), `backbone__authelia__oidc_grafana_clientsecret` (OIDC), `vault_ntfy__users__monitoring_password` (grafana-to-ntfy basic auth), `monitoring__umami_db_pass`, `monitoring__umami_app_secret`, `monitoring__healthchecks_{project_uuid,api_key}`, `hass__prometheus_token` | Vault/group vars + template env values in `templates/docker-compose.yml` and `templates/prometheus.yml` | `stacks.monitoring.smtp.password`, `stacks.monitoring.oidc.grafana.client_secret`, `stacks.monitoring.ntfy.monitoring_password`, `stacks.monitoring.umami.db_password`, `stacks.monitoring.umami.app_secret`, `stacks.monitoring.healthchecks.project_uuid`, `stacks.monitoring.healthchecks.api_key`, `stacks.monitoring.prometheus.hass_token` | No |
| `backbone` | `backbone__lldap__{db_user,db_pass,jwt_secret,key_seed}` (lldap), Authelia secrets in `templates/authelia/configuration.yml`: `backbone__authelia__{jwt_secret,ldap_pass,session_secret,encryption_key,db_pass,oidc_hmac_secret,oidc_jwks_key}` and OIDC client secret hashes | Vault-backed vars rendered to compose + Authelia template files under `templates/authelia/` | `stacks.backbone.lldap.{db_user,db_pass,jwt_secret,key_seed}`, `stacks.backbone.authelia.{jwt_secret,ldap_pass,session_secret,encryption_key,db_pass,oidc_hmac_secret,oidc_jwks_key,oidc_clients}` | Partial: rotate OIDC client secrets/hashes during cutover recommended |
| `unifi` | `unifi__mongo_pass`, `unifi__mongo_root_pass` | Vault/group vars rendered in `templates/docker-compose.yml` | `stacks.unifi.mongo.user_password`, `stacks.unifi.mongo.root_password` | No (stack moves to dedicated VM) |
| `crowdsec` | `crowdsec__firewall_bouncer__api_key`, `crowdsec__webui_password` | Vault/group vars in `templates/docker-compose.yml` | `stacks.crowdsec.firewall_bouncer.api_key`, `stacks.crowdsec.webui.password` | Recommended (bouncer API key) |
| `ntfy` | `ntfy__users_entries`, `ntfy__topics_entries`, `ntfy__tokens_entries` (auth DB bootstrap) | Vault/group vars rendered in `templates/docker-compose.yml` | `stacks.ntfy.auth.users_entries`, `stacks.ntfy.auth.topics_entries`, `stacks.ntfy.auth.tokens_entries` | Optional (recommended for tokens) |
| `streaming` | `peertube__{db_password,secret,oidc_client_secret}`, `audiomuse__db_password`, `vpn__wireguard_pk`, `vpn__control_server_api_key`, `smtp__pass` | Vault/group vars in `templates/docker-compose.yml` | `stacks.streaming.peertube.{db_password,secret,oidc_client_secret}`, `stacks.streaming.audiomuse.db_password`, `stacks.streaming.vpn.{wireguard_private_key,control_server_api_key}`, `stacks.streaming.smtp.password` | Recommended for VPN and app tokens |
| `immich` | `immich__db_password` | Vault/group vars in `templates/docker-compose.yml` | `stacks.immich.db.password` | No |
| `paperless` | `paperless__postgres_password`, `paperless__secret_key`, `backbone__authelia__oidc_paperless_clientsecret` | Vault/group vars in `templates/docker-compose.yml` | `stacks.paperless.db.password`, `stacks.paperless.secret_key`, `stacks.paperless.oidc.client_secret` | Optional (rotate OIDC client secret) |
| `nextcloud` | `nextcloud__postgres_password`, `nextcloud__nextcloud_password` | Vault/group vars in `templates/docker-compose.yml` | `stacks.nextcloud.db.password`, `stacks.nextcloud.admin.password` | Optional (admin password) |
| `actual-budget` | `backbone__authelia__oidc_actual_budget_clientsecret` | Vault/group vars in `templates/docker-compose.yml` | `stacks.actual_budget.oidc.client_secret` | Optional |
| `recipes` | `recipes__secret_key`, `recipes__db_password`, `backbone__authelia__oidc_recipes_clientsecret` | Vault/group vars in `templates/docker-compose.yml` | `stacks.recipes.secret_key`, `stacks.recipes.db.password`, `stacks.recipes.oidc.client_secret` | Optional |
| `speedtest` | none currently | no secret material in stack templates | n/a | n/a |
| `dashboard` | `dashboard__open_weather_key` | Vault/group vars rendered by `templates/.env.j2` | `stacks.dashboard.openweather.api_key` | No |
| `personal_website` | none currently | no secret material in stack templates | n/a | n/a |
| `quartz` | none currently (content path variable only) | no secret material in stack templates | n/a | n/a |
| `s-pdf` | none currently | no secret material in stack templates | n/a | n/a |
| `foundryvtt` | `foundryvtt__password`, `foundryvtt__admin_key` | Vault/group vars in `templates/docker-compose.yml` | `stacks.foundryvtt.user.password`, `stacks.foundryvtt.admin.key` | Optional |
| `minecraft` | none currently | no secret material in stack templates | n/a | n/a |
| `syncthing` | none currently | no secret material in stack templates | n/a | n/a |
| `team_wiki` | `team_wiki__db_pass` | Vault/group vars in `templates/docker-compose.yml` | `stacks.team_wiki.db.password` | No |
| `rallly` | `rallly__db_pass`, `rallly__secret`, `smtp__pass`, `backbone__authelia__oidc_rallly_clientsecret` | Vault/group vars in `templates/docker-compose.yml` | `stacks.rallly.db.password`, `stacks.rallly.secret`, `stacks.rallly.smtp.password`, `stacks.rallly.oidc.client_secret` | Optional |
| `speedtest-tracker` | `speedtest_tracker__app_key`, `speedtest_tracker__db_pass`, `smtp__pass` | Vault/group vars in `templates/docker-compose.yml` | `stacks.speedtest_tracker.app_key`, `stacks.speedtest_tracker.db.password`, `stacks.speedtest_tracker.smtp.password` | Optional |
| `sharkey` | `sharkey__db_pass` in `templates/config/default.yml` (meili key template currently commented) | Vault/group vars in template subdir + compose comments | `stacks.sharkey.db.password` (reserve `stacks.sharkey.meili.master_key` if enabling meili) | No |
| `dawarich` | `dawarich__db_pass`, `backbone__authelia__oidc_dawarich_clientsecret`, `smtp__pass` | Vault/group vars in `templates/docker-compose.yml` | `stacks.dawarich.db.password`, `stacks.dawarich.oidc.client_secret`, `stacks.dawarich.smtp.password` | Optional |
| `semaphore` | `semaphore__admin_pass`, `semaphore__encryption_key` | Vault/group vars in `templates/docker-compose.yml` | `stacks.semaphore.admin.password`, `stacks.semaphore.access_key_encryption` | Recommended (encryption key if rekeying) |
| `backrest` | none currently in templates (credentials live in mounted app config/repo definitions) | runtime app config, not templated secret vars | `stacks.backrest.repositories` (if modeled later) | n/a |
| `skyrim_together` | none currently | no secret material in stack templates | n/a | n/a |
| `matrix` | Extensive template subdir secrets: Synapse (`matrix__db_pass`, `matrix__registration_shared_secret`, `matrix__macaroon_secret_key`, `matrix__form_secret`), MAS (`matrix__mas__{db_pass,encryption_secret,shared_secret}`), bridges (`matrix__{discord,signal,whatsapp,meta}__{db_pass,as_token,hs_token,shared_secret,pickle_key}`), doublepuppet (`matrix__doublepuppet__{as_token,hs_token}`), maubot (`matrix__maubot__{db_pass,shared_secret,admin_pass}`), OIDC (`backbone__authelia__oidc_matrix_clientsecret`) | Vault/group vars rendered across files under `templates/{synapse,mas,matrix_*,maubot}/` | `stacks.matrix.synapse.*`, `stacks.matrix.mas.*`, `stacks.matrix.bridges.{discord,signal,whatsapp,meta}.*`, `stacks.matrix.doublepuppet.*`, `stacks.matrix.maubot.*`, `stacks.matrix.oidc.client_secret` | Recommended (bridge tokens + shared secrets) |
| `attic` | none templated in repo; possible credentials live in `/mnt/storage/attic/attic.toml` | file-mounted config (`attic.toml`) | `stacks.attic.config` (if migrating into SOPS-managed template) | n/a (stack not migrating to apps) |
| `mobilizon` | `mobilizon__db_pass`, `mobilizon__secret_key_base`, `mobilizon__secret_key`, `smtp__pass` | Vault/group vars in `templates/docker-compose.yml` | `stacks.mobilizon.db.password`, `stacks.mobilizon.secret_key_base`, `stacks.mobilizon.secret_key`, `stacks.mobilizon.smtp.password` | Optional |
| `scrypted` | none templated in repo | no secret material in stack templates | n/a | n/a (dedicated VM) |

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
