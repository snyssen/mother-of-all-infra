# apps VM migration — Phase B (production cutover)

> [!CAUTION]
> **Phase B destroys the production server.** Its hardware is the target hardware: the
> only way to run the new infrastructure on it is to wipe the machine that is currently
> serving everything. There is no rollback once the disks are repartitioned — the only
> way back is a restore from the restic repositories onto *different* hardware.
>
> Read "[Before you start](#before-you-start)" in full and tick every box before the
> first destructive step. The day this runs will be stressful; the point of this
> document is that nothing has to be remembered or improvised on the day.

## What Phase B is

The migration is split in two (see [apps-migration-plan.md](apps-migration-plan.md) for
the architecture and per-stack progress):

- **Phase A** — build the `apps` NixOS VM on the *test* hypervisor and migrate every
  stack to it, iteratively, against partial data. This is where the work tracked in
  `apps-migration-plan.md` happens.
- **Phase B — this document** — take the production box (`snyssen.be`, bare-metal
  Ubuntu, Ansible-managed) out of service, wipe it, install the hypervisor NixOS config
  on it, recreate the VMs, and restore all production data onto them.

Phase A exists only because production runs on the better hardware. Everything else is
a consequence of that one constraint.

Phase B is also the real disaster-recovery rehearsal: it exercises the same restore
path as [the DR runbook](../backups.md#full-disaster-recovery-rebuilding-apps-from-scratch),
with the difference that the source snapshots are production's rather than `apps`'s own.

## Before you start

Nothing here is destructive. All of it has to be true *before* anything is.

### Phase A must be finished

- [ ] Every stack marked **Migrate** in the Current Stack Inventory is **Done**, not
      just the ones in daily use.
- [ ] `nix flake check` passes and argunix is green on `main`.
- [ ] `apps` has run for a sustained period on the test hypervisor with no unresolved
      issues.
- [ ] The DNS migration (issue #153) is either done or has a decided, written plan —
      it is excluded from this document on purpose and is not something to improvise.

### Backups must be verified, not assumed

- [ ] A **fresh, complete** autorestic run on production has finished, with no
      failures in `/var/log/autorestic`.
- [ ] `autorestic --ci check` has passed recently on **both** backends
      (`backup-snyssen-be` on-site and `snyssen-be-autorestic` on B2).
- [ ] Every `prod-import` group has been verified against the real repository:

      ```sh
      prod-import --list
      prod-import --all --check     # resolves each snapshot, proves every path exists
      ```

- [ ] The off-site B2 copy is current. The on-site REST server is a single machine in
      the same building as the one being wiped.

### Credentials must exist outside this infrastructure

This is the step that is *actually* irreversible if skipped — see
[key management](../backups.md#key-management-the-actual-single-point-of-failure).

- [ ] The breakglass age key is in the password manager **and** is a recipient on every
      secrets file (`git grep -c age1mpnhsfpava0 -- 'nix/hosts/*/data/*'`).
- [ ] Both restic repository passwords are in the password manager, as plain text, not
      only inside sops.
- [ ] The backup server's **IP and MAC address** are written down somewhere outside
      this repository. It is wake-on-LAN'd, and DNS for `backup.snyssen.be` goes away
      with the production box.

### Capacity must be checked, not remembered

Production holds roughly 12 TB. The numbers below were measured during Phase A and
**will have grown** — re-measure rather than trusting this table.

| location | measured size (Phase A) |
| --- | --- |
| `tv` | ~5590 GB |
| `movies` | ~4190 GB |
| `music` (+ `music_vi`) | ~818 GB |
| `nextcloud` | ~353 GB |
| `photos` | ~88 GB |
| `postgres` (all dump dirs) | ~77 GB |
| `audiobooks` (+ `audiobooks_vi`) | not measured |

- [ ] Target pool capacity on the rebuilt hypervisor is known and exceeds the above
      with headroom.
- [ ] The decision on media is made — see
      [what does not come through restic](#data-that-does-not-come-through-restic).

## The `prod-import` tooling

`prod-import` is a generated on-host command that pulls legacy-production data onto
`apps` with paths and ownership translated. It is **transitional**: it is declared in
`nix/hosts/apps/prod-import.nix`, and that file plus its one `import` line in
`configuration.nix` are deleted at the end of Phase B.

It is built from the same generator as `backrest-restore` (see
`nix/modules/nixos/backrest/restore.nix`), so it shares all of that command's safety
behaviour — snapshot resolution per group, a real `--dry-run` size preflight checked
per filesystem, a confirmation prompt, and `--at` for older states. See
[the backups doc](../backups.md#the-restore-commands) for the shared flags.

The one thing it adds is translation. Each entry is a `from` → `to` pair plus an
optional `owner`, and restic's `snapshotID:subfolder` syntax does the retargeting
natively: the subfolder becomes the root of the restore, and it may be *deeper* than
the snapshot's own root.

```nix
monitoring = fromLocation "monitoring" // {
  stopUnits = [ "compose-monitoring.service" ];
  paths = [
    { from = "/home/snyssen/data/grafana/data";
      to   = "/var/lib/app-data/monitoring/grafana";
      owner = "472:472"; }
  ];
};
```

`owner` matters more than it looks. restic restores numeric owners verbatim, and
production's uid/gid conventions are not this host's — production used the deploy
user's gid 1000 for the media applications, where `apps` uses gid 100. The `chown` is
recursive on purpose: systemd-tmpfiles re-asserts ownership of a directory's *top
level* on every activation but never touches its children, so a shallow chown leaves a
correct-looking directory over wrongly-owned contents.

### Import groups

One group per autorestic location, selected by name, variadic. Groups commented out in
`prod-import.nix` are declared but disabled — uncomment them when the target has the
capacity.

| group | from (prod) | to (`apps`) | state |
| --- | --- | --- | --- |
| `monitoring` | `/home/snyssen/data/{grafana/data,uptime}` | `/var/lib/app-data/monitoring/{grafana,uptime}` | enabled |
| `streaming-config` | jellyfin, audiobookshelf, the 8 `*arr` configs, peertube config | `/var/lib/app-data/…` | enabled |
| `postgres` | `/mnt/storage/backups/postgres` | `/mnt/bulk/restore/prod-postgres` | enabled, **staging** |
| `immich` | `/mnt/storage/backups/immich` | `/mnt/bulk/restore/prod-immich` | enabled, **staging** |
| `nextcloud` | `/mnt/storage/nextcloud` | `/mnt/bulk/nextcloud` | enabled, ~353 GB |
| `paperless` | `/home/snyssen/data/paperless/data`, `/mnt/storage/paperless/media` | `/var/lib/app-data/paperless/data`, `/mnt/bulk/paperless/media` | enabled |
| `paperless-export` | `/mnt/storage/paperless/export` | `/mnt/bulk/paperless/export` | **commented out** |
| `photos` | `/mnt/storage/photos` | `/mnt/bulk/photos` | **commented out**, ~88 GB |
| `movies` / `tv` / `music` / `audiobooks` | `/mnt/storage/streaming/media/…` | `/mnt/bulk/streaming/media/…` | **commented out**, ~10.6 TB total |

The two **staging** groups are deliberate. Production's PostgreSQL dumps must not land
on `/mnt/bulk/backups/postgres`: that is `apps`'s own dump directory, feeding `apps`'s
own `databases` backup plan. Importing onto it would both clobber this host's dumps and
push production's data into this host's backups. They go to `/mnt/bulk/restore/prod-*`
instead and are loaded with `postgres-restore --from`.

`paperless-export` is commented out because it roughly doubles paperless' bytes and the
nightly `paperless-export.timer` regenerates it from the library anyway.

## Data that does not come through restic

**Media — roughly 10.6 TB of the 12 TB.** `movies`, `tv`, `music` and `audiobooks`
should not be streamed through restic. The plan is to move the physical disks into the
hypervisor's pool instead. This is also consistent with production's own policy, where
`movies` and `tv` are on-site-only and never went to B2 at all.

- [ ] Decide and write down *here* how the media disks are moved, before the day.
      This is currently the largest open question in this document.

**Docker named volumes.** Nothing backs them up, by design — backups are path-based.
Every named volume in use today is disposable (Redis caches, Immich's ML model cache),
and the convention for new stacks is that anything stateful is a bind mount. Worth
re-checking at cutover that this is still true.

**Dawarich's uploaded files.** Prod's `/mnt/storage/dawarich/storage` holds the
original import files (GPX, Google Takeout...) and generated exports, and is in no
autorestic location, so restic has nothing to import from. The points themselves are in
the database and do come across. `apps` backs this directory up from now on.

- [ ] Copy it across by hand at cutover (e.g. `rsync` from the legacy box to
      `/mnt/bulk/dawarich/storage`), or decide the originals aren't needed.

**maubot's plugins.** Prod's `/mnt/storage/matrix/maubot/plugins` (the uploaded `.mbp`
files) is in no autorestic location. Without them every bot instance stays disabled
until they are uploaded again. `apps` backs them up from now on.

- [ ] Copy them across by hand at cutover (into `/var/lib/app-data/matrix/maubot/plugins`,
      owner 1337), or re-download them from their releases.

**Docker images.** Pinned by digest. A rebuild with no working internet — or after an
upstream digest has been garbage-collected — leaves stacks that will not start.

**The age keys.** Covered under preconditions above, and worth repeating because it is
the one failure that makes everything else moot.

## Cutover checklist

### 1. Freeze

- [ ] Announce downtime to anyone else who uses the services.
- [ ] Stop writing: pause anything that ingests data (paperless consume folder,
      `*arr` downloads, Syncthing, Immich mobile backup).
- [ ] Disable autorestic's cron on production so no partial state is captured mid-wipe.

### 2. Final backup

- [ ] Run a final full autorestic backup, **and watch it finish.**
- [ ] Run the final PostgreSQL dumps and confirm they are in the dump directories.
- [ ] `autorestic --ci check` on both backends, one last time.
- [ ] Note the snapshot IDs of every location. If something later resolves to an older
      snapshot than these, something is wrong.

### 3. Point of no return

- [ ] Re-read [Before you start](#before-you-start). Every box ticked.
- [ ] Physically label the production disks before removing anything.
- [ ] Wipe and install the hypervisor NixOS configuration on the production hardware.

### 4. Rebuild

- [ ] `just hypervisor-build-vm-images` — note this generates **new** SSH host keys, and
      therefore new `root_<vm>` age keys.
- [ ] Add each new key to `.sops.yaml`, then `just sops-update-keys-all`, then commit.
      **Not optional**: without it sops-nix cannot decrypt and no secret — including the
      restic repository password — ever reaches the host.
- [ ] `just hypervisor-provision-vms`.
- [ ] Boot `apps` with `docker.service` and `backrest.service` **masked** (append
      `systemd.mask=docker.service systemd.mask=backrest.service` at the GRUB prompt).
      See the warning in [the DR runbook](../backups.md#full-disaster-recovery-rebuilding-apps-from-scratch)
      — this is what stops a half-restored state from being backed up over the good
      snapshots.
- [ ] Sanity-check: `ls /run/secrets/backrest/repos/`, `tailscale status`, `ls /mnt/bulk`.
- [ ] Wake the backup server and confirm `http://backup.snyssen.be:8000/metrics` answers.

### 5. Restore

Run everything in **tmux**. Several of these take hours and an SSH drop kills them.

- [ ] `prod-import --all --check` — proves every path still resolves before writing.
- [ ] `prod-import --all --dry-run` — review the per-filesystem size table.
- [ ] `prod-import --all` (or group by group, which is easier to recover from).
- [ ] `postgres-restore --from /mnt/bulk/restore/prod-postgres --all` for the central
      cluster.
- [ ] `postgres-restore --from /mnt/bulk/restore/prod-immich immich`.
      `--from` applies to everything selected, so do one instance at a time.
- [ ] Media: whatever the disk-relocation decision turns out to be.

### 6. Code changes at cutover

These are known, grounded in the repository, and all of them are needed for the new
setup to be "production" rather than "a test VM":

- [ ] `nix/hosts/apps/configuration.nix` — `domains.main = "snyssen1.xyz"` becomes
      `"snyssen.be"`.
- [ ] `nix/hosts/apps/configuration.nix` — `domains.team = "snyssen2.xyz"` becomes
      `"bigdouf.team"`.
- [ ] Delete `nix/hosts/apps/prod-import.nix` and its `import` line.
- [ ] `nix/hosts/apps/compose/reverse-proxy/default.nix` — drop the hardcoded
      `argunix_domain = "snyssen.be"` and restore `config.domains.main` (the commented
      line directly above it).
- [ ] `nix/hosts/apps/compose/streaming/default.nix` — `autostart = false` back to true
      (disabled during testing so it would not act on absent media).
- [ ] `nix/hosts/apps/compose/nextcloud/default.nix` — `autostart = false` back to true,
      once its data and database are both in.
- [ ] `nix/hosts/apps/compose/sharkey/default.nix` — `autostart = false` back to true,
      in the same deploy as `domains.main`, and only after its data and database are in.
- [ ] `nix/hosts/apps/compose/dawarich/default.nix` — `photon.enable = true`, and only
      once there is room for it. Prod's worldwide index is ~200 GB and grows 10–20 GB a
      year; its `PARALLEL` update strategy needs twice that while swapping. The VM's
      whole disk is 300 GB (`disk_gb` in `ansible/hosts/host_vars/hypervisor/vars.yml`).
      So grow the disk, or pick a smaller `REGION` and/or `UPDATE_STRATEGY` first.
- [ ] `nix/hosts/apps/compose/matrix/default.nix` — `live = true`, in the same deploy as
      `domains.main`: federation and push back on, and the bridges and maubot started.
      Only after prod's Synapse and bridges are stopped for good — two copies of the
      same server, or of the same bridge session, must never run at once.
- [ ] `nix/hosts/apps/compose/minecraft/default.nix` — restore prod's sizing in the
      `memory` binding: 8G heap / 8.2g limit for both servers (shrunk to fit the 8 GiB
      test VM).
- [ ] `nix/hosts/ingress/traefik-configuration.nix` — `appsServerIp` is the legacy box's
      tailnet address, and it is what the TCP proxy (Minecraft, 25565) forwards to.
      Point it at the new `apps` VM's tailnet IP. The HTTP backends are unaffected: they
      resolve by hostname, so they follow DNS.
- [ ] Grafana Alloy dual-shipping: nine configurations currently push to **both** the
      legacy and the new Prometheus/Loki. Drop the `*.snyssen1.xyz` entries when
      `domains.main` flips, and the legacy `*.snyssen.be` entries once the old box is
      gone — each carries the same `TODO` comment:
      `apps`, `blackfog`, `gaming`, `hypervisor`, `ingress`, `purplehaze`, `sninful`,
      `technitium-primary`, `technitium-secondary`.
- [ ] `nix/hosts/apps/backrest.nix` — decide what happens to the `backup_snyssen_be`
      repository registration. It is production's repo, registered read-only. After
      cutover it holds the only copy of pre-migration history, so it should stay
      registered, still with no plans and no prune/forget policy.

### 7. Verify before decommissioning anything

- [ ] Every service answers on its real hostname, over TLS, with a valid certificate.
- [ ] Authelia login works, including a second factor and at least one OIDC client.
- [ ] Nextcloud: files present, a desktop client syncs, CalDAV/CardDAV resolves.
- [ ] Immich: assets present *and* thumbnails render (a restored database with absent
      files looks fine until you scroll).
- [ ] Paperless: documents searchable, OCR runs on a new upload.
- [ ] `backrest-restore --check` passes against `apps`'s own repository.
- [ ] A backup has actually run and produced a snapshot in the `apps` repository.
- [ ] Monitoring: Grafana dashboards populated, Uptime Kuma monitors green, alerts
      firing to ntfy.

### 8. Only then

- [ ] Unmask `docker.service` and `backrest.service`, reboot, confirm a clean ordered
      start.
- [ ] Re-enable ingest (consume folders, download clients, mobile backup).
- [ ] Keep production's final snapshots **indefinitely** — they are the only pre-cutover
      state that exists.
- [ ] Update `apps-migration-plan.md` to mark Phase B complete.

## Per-stack restore notes

Things that are not obvious from the group table, and that cost time if discovered on
the day.

**Nextcloud — the strictest pairing.** Its database indexes its file tree; neither half
is usable without the other. Started against an empty `/mnt/bulk/nextcloud`, the
entrypoint runs its first-run installer and writes a config and schema of its own,
which a later `postgres-restore nextcloud` then half-replaces. The stack ships with
`autostart = false` for exactly this reason. Order:

```sh
prod-import nextcloud                 # ~353 GB, hours — tmux
postgres-restore --from /mnt/bulk/restore/prod-postgres nextcloud
systemctl start compose-nextcloud
```

Its `extra.config.php` is what makes an imported `config.php` work at all: Nextcloud
reads `*.config.php` after `config.php`, so the restored file keeps pointing at
production's database password, domain and Redis host, and the generated one overrides
all three. `passwordsalt`, `secret` and `instanceid` must be production's values —
`secret` keys every encrypted field, and `instanceid` names the `appdata_<id>`
directory inside the restored tree.

**Immich — database and photos together.** Restoring the database without
`prod-import photos` leaves a library whose every asset is missing. Its dumps are in
production's `postgres` location but belong to its own PostgreSQL, which is why they
get a separate group and a separate staging path.

**Paperless — mind the export timer.** The nightly export runs
`document_exporter --delete`, so it mirrors the library. Run against a database that
has not been restored yet, it finds no documents and clears the export directory.
`prod-import paperless` restarts the stack when it finishes, so either load the
database before the next 22:43 or pass `--keep-stopped` and start the stack by hand.
Nothing is lost permanently — the export has its own snapshots and is regenerable.

**Streaming — expect stale configuration.** The `*arr` applications and Jellyfin store
absolute paths and hostnames in their configs. After an import they will be pointing at
production's layout and domain. Budget time for fixing root folders and indexers rather
than assuming the import is the end of it.

**Team wiki — database only, then its own settings.** There is no file data, so the
import is `prod-import postgres` followed by
`postgres-restore --from /mnt/bulk/restore/prod-postgres team_wiki`. On the test host the restored wiki still names production's domain in
its own settings, which live in the database: the site URL, and the OIDC strategy's
authorization, token, userinfo and issuer URLs (all `auth.bigdouf.team`). Edit them in
the wiki's admin UI to `snyssen2.xyz` to test login. At cutover the domain is
production's again, so they are right as imported. Keep the strategy itself rather
than recreating it: its id is part of the redirect URI registered with Authelia.

**Rallly — database only.** `postgres-restore --from /mnt/bulk/restore/prod-postgres
rallly`. Its base URL and OIDC endpoints come from the environment, not the database,
so they follow `domains.team` without editing anything in the app.

**Speedtest Tracker — database only.** `postgres-restore --from
/mnt/bulk/restore/prod-postgres speedtest_tracker`. Its `APP_KEY` is prod's, so
whatever the database holds encrypted with it stays readable.

**Sharkey — first run is the cutover.** It was never started on `apps`: its `url` is the
instance's identity on the fediverse, so it only runs under `social.snyssen.be`. The
restore is therefore also its first test. Order:

```sh
prod-import sharkey      # Redis + drive files; check the snapshot has files first (--dry-run)
postgres-restore --from /mnt/bulk/restore/prod-postgres sharkey
# then deploy with domains.main = snyssen.be and autostart = true, which starts it
```

Things to check once it is up: log in, timelines load, an existing image displays (the
drive's files), and a post reaches a remote follower. Redis carries the job queue across,
so deliveries that were pending at the freeze go out from the new host.

**Dawarich — database, then the geocoder.** `prod-import dawarich`, then
`postgres-restore --from /mnt/bulk/restore/prod-dawarich dawarich`, which goes to its own
PostGIS. Points imported from prod are already geocoded and keep their data. Reverse
geocoding of new points needs Photon. While it is off, the imported database may still
name `photon:2322` (Dawarich copies the setting from its environment into its own
settings), so lookups go to a host that doesn't exist. In 1.17.0 a lookup that errors is
retried three times and then dropped, leaving the point to catch up once Photon is on.
Only an *empty* answer marks a point as geocoded for good. That depends on the geocoder
raising on an unreachable host (read from the code, not tested).

**Matrix — database collation first.** Synapse refuses a database whose collation isn't
`C`, and a restore can't change it: it comes from `CREATE DATABASE`. The databases stack
now creates `matrix` that way (`cLocaleDbNames`), but only if it doesn't exist yet. If
its provisioning logs `WARNING: database matrix has collation/ctype ...`, the database
predates that: drop it (pgAdmin, or `DROP DATABASE matrix;` as the superuser) and restart
`compose-databases` to recreate it. Then:

```sh
prod-import postgres matrix
postgres-restore --from /mnt/bulk/restore/prod-postgres matrix matrix_mas matrix_discord matrix_signal matrix_whatsapp matrix_meta maubot
```

On the test host it runs in restore-test mode: no federation, no push, no bridges, no
maubot. That is enough to check that the restore is whole — log in through Element,
recent messages and media load — without acting as prod anywhere. Logging in needs
Authelia's database to be prod's too: MAS links each user to Authelia's `sub` for them,
which is per-instance.

**Syncthing — synced, not imported.** There is no `prod-import syncthing`: apps is a new
device (its own ID, in `nix/data/syncthing.nix`), and it fills its folders from its
peers. Restoring prod's files under it first would only invite `.sync-conflict` copies
wherever they differ from the peers' current versions. What has to happen on the other
devices instead:

- The Nix hosts learn the `apps` device from `nix/data/syncthing.nix` on their next
  rebuild, but only share a folder with it once `apps` is in that folder's `devices`.
- The Pixel (and any other device not managed here) has to accept apps by hand, with
  address `tcp://apps:22000` if discovery doesn't find it.
- Apps' folders list the devices that carry each one, plus prod's own `sync.snyssen.be`
  on every folder until the cutover, so apps gets a full copy from it. Remove it from
  those lists and from `nix/data/syncthing.nix` once prod is gone (TODO in
  `nix/hosts/apps/syncthing.nix`).

**`monitoring` — Uptime Kuma push tokens.** Push monitors come back with the restored
Uptime Kuma data, so the tokens stay valid, but anything referencing them in sops
(for example `compose-stacks/nextcloud/uptime_push_token`) must match what the restored
instance actually holds.

## Open questions

Things that need deciding or discovering before the day. Add to this as they surface.

- **How the media disks move into the hypervisor pool.** The single largest open item;
  ~10.6 TB that cannot practically go through restic.
- **DNS cutover sequencing** — tracked separately as issue #153, but Phase B cannot be
  scheduled without it.
- **How long production's hardware stays untouched** after the final backup. Ideally
  the disks are not wiped until the new setup has been verified, which conflicts with
  needing that exact hardware.
- **Whether `attic` moves before or after** — it is excluded from `apps` and destined
  for its own VM.
- **Rehearsal**: is there a way to dry-run the whole sequence on the test hypervisor
  with a meaningful subset first? `prod-import --all --check` covers snapshot
  resolution, but not the rebuild-and-restore path end to end.
