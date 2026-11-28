# Backup server on NixOS — plan

Status: **Not started. Capacity measured 2026-11-28; nothing changed yet.** Tracks issue
[#52](https://github.com/snyssen/mother-of-all-infra/issues/52).

## Goal

Move the backup server, `backup.snyssen.be`, the last bare-metal host still configured by
Ansible, to NixOS like the others. At the same time:

- **Put its storage on btrfs, with a monthly scrub**, so bitrot is *detected*. Without
  redundancy a scrub can't repair. That's fine: a bad pack is replaced by a fresh backup
  of the master copy.
- **Require authentication on the restic REST server.** Today it runs with
  `DISABLE_AUTHENTICATION=true` and a `TODO: I should be worried tho`.
- **Retire the Ansible `backup` group**, its playbook and the roles only it uses.

The DNS name `backup.snyssen.be` stays. The Nix host is called `backup-01` here, after
`apps-01` and `hypervisor-01` (see [Open questions](#open-questions)).

The scrub is not the only bitrot check. Backrest's weekly `check` on the on-site repo
(`readDataSubsetPercent = 10`, `nix/hosts/apps-01/backrest.nix`) already re-hashes a
different 10% of the packs each week. The scrub adds a check below restic, covering
blackfog's repo and the filesystem metadata too. Once the pool has redundancy
([Path B](#path-b-keep-the-backups-with-a-new-disk)), the scrub can also repair.

## Current state

Measured from Prometheus (node exporter on the host) on 2026-11-28:

| Item | Value |
|---|---|
| OS | Ubuntu, Ansible-managed (`ansible/playbooks/backup-server-setup.ansible.yml`) |
| CPU / RAM | 4 cores, 4 GB |
| OS disk | `sda`, ~450 GB, LVM `ubuntu--vg`, UEFI; 54 GB used |
| disk1 | `ata-ST8000VN004-2M2101_WSD503DW`, 8 TB, ext4 on the whole disk, **3.48 TB used** |
| disk2 | `ata-ST16000NM001G-2KK103_ZL21CNWC`, 16 TB, ext4 on the whole disk, **11.17 TB used** |
| Pool | mergerfs over both at `/mnt/storage`, **14.65 TB used of 23.8 TB** |
| Addresses | LAN 192.168.1.11, tailnet 100.74.131.24, both hard-coded in the split-horizon record in `ansible/hosts/group_vars/technitium/vars.yml` |

What the playbook sets up:

- `setup_common`: Docker, SSH hardening, CrowdSec firewall bouncer (decisions from
  apps-01's LAPI), Tailscale with `--ssh`, zsh.
- `setup_storage`: the mergerfs pool (`category.create=mfs`, so the files of one repo are
  spread over both disks).
- Prometheus node exporter on `:9100`, scraped by apps-01's Prometheus and checked by Gatus.
- Alloy in a container, shipping host and container logs to Loki.
- `restic/rest-server:0.15.0` in a container, `--prometheus`, no auth, serving
  `/mnt/storage/data` on `:8000`.

What writes to it:

| Client | Repository | Notes |
|---|---|---|
| apps-01 Backrest, `backup_snyssen_be` | `rest:http://backup.snyssen.be:8000/` (the root) | Every plan, daily at 00:30. Weekly check (10%) and prune. `backrest-restore` reads it. |
| blackfog, `services.restic.backups` | `rest:http://backup.snyssen.be:8000/blackfog/` | Own password, `initialize = true`, on-site only. |

Most plans also have an `-offsite` twin writing to B2 (`snyssen_be_autorestic`). Four don't:
**movies, tv, media-extra and peertube-data are backed up on-site only**. They are roughly
10 TB, and their primary copy is on hypervisor-01's `bulk` pool.

## Can the backups be kept?

The host is reinstalled on the same hardware, and moving to btrfs means reformatting the
data disks. To keep the repositories, the 14.65 TB has to live somewhere while that
happens:

- **Shuffle between the two disks: no.** All the data fits on disk2 alone (14.65 of
  15.87 TB). disk1 could then be reformatted, but it holds only about 7.5 TB, so disk2 can
  never be emptied to be reformatted in turn.
- **Park it on hypervisor-01: no.** `/mnt/bulk` has 6.35 TB free, and it holds the primary
  copy of everything. Filling it to the brim for days is not an option.
- **RAID1 over the existing disks: no.** With an 8 TB and a 16 TB disk, btrfs RAID1 gives
  8 TB usable.
- **Convert in place with `btrfs-convert`: possible, but rejected.** See
  [Considered and rejected](#considered-and-rejected).

So, on today's hardware, **the backups start from scratch** ([Path A](#path-a-start-from-scratch)).
That is acceptable: everything except the media also has an off-site copy on B2, history
included, throughout. With a **new disk of at least 16 TB**, the backups can be kept and the
pool gains redundancy as well ([Path B](#path-b-keep-the-backups-with-a-new-disk)). Path A
is the default. Path B applies only if the disk is bought before the migration.

## Target configuration (both paths)

A new `nix/hosts/backup-01/`, built from two existing hosts: `nix/hosts/hypervisor-01/`
(bare metal, LUKS unlocked by USB key, btrfs pools, SMART) and `nix/hosts/technitium-primary/`
(the boilerplate for a small server: users, sops, Tailscale autoconnect, Alloy).

### Disks

The `btrfs-luks-raid1-pools` disko layout
(`nix/modules/nixos/disko/layouts/btrfs-luks-raid1-pools.nix`):

```nix
disko = {
  layout = "btrfs-luks-raid1-pools";
  btrfs-luks-raid1-pools = {
    mainDiskPath = "/dev/disk/by-id/<the OS SSD>";
    usbKeysIds = [ /* sticks carrying /key/backup-01 */ ];
    pools.storage = {
      disks = [ /* per path, below */ ];
      storageMedia = "hdd";
      mountpoint = "/mnt/storage";
    };
  };
};
```

The layout turns on `services.btrfs.autoScrub`, which scrubs monthly. The `smart` module
picks up every disk disko knows. Alloy ships the scrub and SMART results, and the
`BtrfsDeviceErrors`, `Disk*` and `Smart*` alert rules apply unchanged. If the SATA link
problem seen on hypervisor-01 shows up, use the same fix: `ahci.mobile_lpm_policy=1`.

### Modules

| Module | Settings |
|---|---|
| `sops`, `cache`, `grub`, `kbd-layout`, `shell`, `locale`, `nh`, `openssh` | As on the other servers |
| `tailscale` | `autoconnect` with `enableSSH`, tag `server` |
| `crowdsec-firewall-bouncer` | `apiKeyPath` from the host's sops file |
| `prometheus-node-exporter` | `openFirewall`: Gatus's `backup server` check reads `:9100/metrics` |
| `grafana-alloy` | `hostname = "backup"`, to keep the `instance` label that dashboards and alerts use; `journald`, `nodeMetrics`, `smartMetrics`; the Loki and remote-write endpoints of hypervisor-01 |
| `smart` | Defaults |

Docker is gone: nothing on this host needs it any more.

### REST server

There's no module in the repo for this. Use the upstream `services.restic.server`:

```nix
services.restic.server = {
  enable = true;
  dataDir = "/mnt/storage/data";
  listenAddress = "8000";
  prometheus = true;
  htpasswd-file = config.sops.secrets."rest-server/htpasswd".path;
  privateRepos = true;
  extraFlags = [ "--prometheus-no-auth" ];
};
networking.firewall.allowedTCPPorts = [ 8000 ];
```

- **Authentication**: one htpasswd user per client, `apps-01` and `blackfog`, with bcrypt
  entries (`htpasswd -B`). The file is a sops secret of backup-01.
- **`privateRepos`**: a user reaches only `/<user>/…`. blackfog already writes to
  `/blackfog/`, so its URI doesn't change. The on-site Backrest repository moves from the
  root to **`/apps-01/`**.
- **`--prometheus-no-auth`**: keeps `/metrics` open, so the Prometheus `rest_server` job, the
  Grafana dashboard and Gatus's `restic rest server` check keep working unchanged.
- **Not append-only**: Backrest prunes this repository from apps-01.
- **Version**: nixpkgs ships 0.14.0, while the container is 0.15.0. rest-server only serves
  files, so the repository format isn't affected. Check the changelog for anything flag-related
  before the cutover.

Client side. The clients run restic 0.18.1, which reads `RESTIC_REST_USERNAME` and
`RESTIC_REST_PASSWORD`, so the URIs stay free of credentials:

- **apps-01**: in `nix/hosts/apps-01/backrest.nix`, set the `backup_snyssen_be` repo's
  `uri` to `rest:http://backup.snyssen.be:8000/apps-01/` and give the two variables through
  its `env` option (variable name → sops secret path). Then check
  `nix/modules/nixos/backrest/restore.nix`, which has the repo id hard-coded, and the plain
  restic exports in `docs/operations/backups.md`.
- **blackfog**: pass the two variables through `environmentFile` (a sops template) on its
  `services.restic.backups` jobs in `nix/hosts/blackfog/backup.nix`.

The new URI and the credentials go live in the same deploy as the new host. The old server
accepts any request, so no client needs a transition step.

**Transport**: apps-01 resolves `backup.snyssen.be` to the LAN address (split horizon), so
basic auth crosses the LAN in clear text. That's an improvement on no auth, and the LAN is
trusted. TLS can come later, without blocking this migration: rest-server's `--tls`,
`--tls-cert` and `--tls-key` with a certificate from the `tailscale` module's `certificate`
option, and clients pointed at the `ts.net` name.

### Secrets

`nix/hosts/backup-01/data/secrets.yaml`: the htpasswd file, the Tailscale auth key, the
CrowdSec bouncer key. Add the host's age recipient to `.sops.yaml`, following
[Setup a New Machine](../operations/new-machine/index.md). Add the client passwords to
apps-01's `backrest` secrets and blackfog's secrets. Generate them with `just sops-gen-secret`
so they are never printed.

## Path A: start from scratch

The default. Every disk is wiped at install, and both data disks form one btrfs pool with
no redundancy, as today.

### Layout change

The layout formats a pool of two or more disks as RAID1, which here gives only 8 TB. Add a
per-pool option to `btrfs-luks-raid1-pools.nix`, where it currently chooses `raid1` or
`single` from the number of disks:

- `dataProfile`: `"raid1"` (default) or `"single"`.
- Metadata stays `raid1` across two or more disks, and `dup` on one.

With the default unchanged, hypervisor-01's evaluation is untouched. Disko only formats at
install time anyway. backup-01 then uses:

```nix
pools.storage = {
  disks = [
    "/dev/disk/by-id/ata-ST16000NM001G-2KK103_ZL21CNWC"
    "/dev/disk/by-id/ata-ST8000VN004-2M2101_WSD503DW"
  ];
  dataProfile = "single";
  storageMedia = "hdd";
  mountpoint = "/mnt/storage";
};
```

That's about 23.8 TB usable, as today. To gain redundancy later, add a disk by
[Adding a Disk to an Existing Pool](../operations/hypervisor.md#adding-a-disk-to-an-existing-pool)
and convert with `btrfs balance start -dconvert=raid1`.

### Phase 0: prepare (no downtime)

1. Run the [Confirm at runtime](#confirm-at-runtime) checks.
2. Write `nix/hosts/backup-01/`, the layout option and the client changes (on a branch,
   not deployed). Build with `just nix-build backup-01`, and build apps-01 and blackfog too.
3. Make sure the off-site copy is good. Every `-offsite` plan's latest run succeeded, and
   the `backups_check-offsite` heartbeat is green. This is the copy we rely on during
   the migration.
4. Pick a window. Expect the on-site `backups_*` heartbeats in Gatus to fail until the
   reseed is done.

### Phase 1: cutover

1. Pause the on-site Backrest plans, or let them fail. The `-offsite` plans keep running.
2. Install with nixos-anywhere, following
   [Deployment](../operations/new-machine/deployment.md), Part B. **This wipes the OS disk
   and both data disks.**
3. Tailscale: remove the old `backup` node in the admin console. Then do one of the
   following:
   - Give the new node the old address, 100.74.131.24 (Machines → Edit IP). Nothing else
     changes.
   - Or update `ansible/hosts/group_vars/technitium/vars.yml` and run
     `just ansible-playbook technitium-setup`.
4. Check that the LAN address is still 192.168.1.11 (DHCP reservation on the MAC).
5. Deploy apps-01 and blackfog with the new URI and credentials.

### Phase 2: reseed

1. Initialise the on-site repository at `rest:http://backup.snyssen.be:8000/apps-01/`,
   from apps-01, with the **same password** as before (the `backup_snyssen_be` sops
   secret, read from its file, never printed). Backrest does not create the repository.
2. Give the repo a new `guid` in `backrest.nix` (`openssl rand -hex 32`). Backrest keys its
   operation log on it, and the old entries point at snapshots that are gone.
3. Run the plans by hand, the small important ones first and media last. Expect about a day
   per 10 TB on gigabit.
4. blackfog creates its own repository on its next run (`initialize = true`).
5. Done when every `backups_<plan>` heartbeat and `backups_check-onsite` and
   `backups_prune-onsite` are green.

### What is lost

- The on-site **history**. Every plan except the four on-site-only ones keeps its history
  on B2.
- From the wipe until the reseed is done, the **media** (movies, tv, media-extra,
  peertube-data) has one copy: hypervisor-01's `bulk` pool. Its own history (deleted files
  from the last six months) is lost for good.

## Path B: keep the backups with a new disk

If a disk of **at least 16 TB** is bought first, it becomes the pool's first member, and the
old disks follow once their data is copied over. This keeps every snapshot, and ends with
RAID1.

1. **Install with the old data disks unplugged.** This is the simplest guarantee that
   disko can't touch them. Set `pools.storage.disks` to the new disk only: one disk is
   formatted `single` with metadata `dup`, which the layout already supports.
2. Plug the old disks back in and mount each ext4 **read-only**. Both disks hold the same
   directory tree, so mergerfs isn't needed. Before copying, list any path present on both
   disks (there shouldn't be any).
3. `rsync -aHAX` both trees into the pool, the root repository into
   `/mnt/storage/data/apps-01/` and `blackfog/` as it is. The whole 14.65 TB is a local
   copy, about a day at 150–200 MB/s.
4. Start the REST server and check from the clients: `restic snapshots`,
   `restic check --read-data-subset=5%`, a Backrest backup run and a `backrest-restore`
   dry run.
5. Wipe the old disks and add them to the pool, following
   [Adding a Disk to an Existing Pool](../operations/hypervisor.md#adding-a-disk-to-an-existing-pool)
   (the GPT labels must match what boot expects). Then update `disks` and convert with
   `btrfs balance start -dconvert=raid1 -mconvert=raid1`.

The end result is RAID1 over 16 + 16 + 8 TB: about 20 TB usable, 73% full, and a scrub that
**repairs** as well as detects.

- The machine must take four drives at once during the copy (the SSD and three HDDs).
  Check SATA ports, bays and power.
- A smaller new disk (8 TB or more) still keeps the backups, but a RAID1 of 16 + 8 + 8 TB
  would be too full to be worth it.
- Rollback: step 1 wipes the old OS, but the old data disks stay untouched until step 5.
  If anything goes wrong before then, the backups are still on them, readable by any Linux
  machine.

## Considered and rejected

- **`btrfs-convert` in place.** It turns ext4 into btrfs without moving the data: consolidate
  onto disk2, convert it, then add disk1. It keeps the backups on today's hardware, but the
  data disks end up without LUKS and outside disko, unlike every other host. It also means
  converting 15 TB in a single run, which is risky. The backups it saves aren't worth it.
- **bcachefs**: out of the mainline kernel.
- **par2**: parity per file. It doesn't suit restic packs, which change on every prune.

## Monitoring

- `nix/hosts/apps-01/compose/monitoring/prometheus-config.nix`: drop the static `node` job
  for `backup.snyssen.be:9100` once Alloy pushes the host's metrics. Its comment already
  says so. Keep the `rest_server` job.
- Gatus (`gatus-config.nix`): both checks stay as they are.
- `nix/checks/ntfy-template.nix` uses a fake `rest_server` alert as a fixture. Nothing to
  change.

## Cleanup after the cutover

Ansible:

- Remove the `backup` group from `ansible/hosts/prod.yml`, along with
  `ansible/hosts/host_vars/backup.snyssen.be/` and its recipients in `.sops.yaml`.
- Remove `ansible/playbooks/backup-server-setup.ansible.yml`, then every role and Galaxy
  dependency no other playbook uses (grep before deleting): `setup_common`,
  `setup_storage`, `container_rest`, `container_alloy`, `geerlingguy.docker`,
  `geerlingguy.security`, `undergreen.prometheus-node-exporter`, and what they pull in.

Docs:

- `AGENTS.md`, `ansible/README.md`, `docs/index.md` and `docs/architecture/repository.md`:
  Ansible no longer manages the backup server.
- `docs/architecture/network.md`: the host's row.
- `docs/operations/backups.md`: the new URI and credentials, a storage section for this
  host (or a link to the hypervisor's btrfs runbooks), and the DR step that curls the REST
  server.
- This plan: delete it, or move it to the archive (see [Plans](index.md)).

## Confirm at runtime

Read-only, on the current host, before Phase 0:

- `lsblk -o NAME,SIZE,MODEL,SERIAL`: the OS disk's `by-id` name, and nothing unexpected.
- SATA ports, free bays, power connectors (Path B), and a USB port for the key stick.
- `du -sh /mnt/storage/data/*`: anything there besides the two repositories?
- What uses the 54 GB on the OS disk: anything worth keeping besides Docker images?
- Reseed size: `restic stats --mode raw-data` on the latest snapshot of each plan (Path A).
- The DHCP reservation for 192.168.1.11.

## Open questions

- Host name: `backup-01` (this plan) or `backup`.
- TLS on the REST server: in this migration, or after.
- Buy a 16 TB disk (Path B) or not (Path A).
