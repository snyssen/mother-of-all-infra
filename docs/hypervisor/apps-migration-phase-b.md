# apps VM migration — Phase B (production cutover)

> [!CAUTION]
> **Phase B reinstalls the production server.** Its hardware is the target hardware:
> the legacy box (`snyssen.be`) becomes the hypervisor `hypervisor-01`, and production
> moves into the `apps-01` VM on it. Its boot SSD and its SnapRAID parity disk are wiped.
> Its **two data disks are not**: they are where most of production's data is copied
> from, and they stay untouched until the new setup is verified (step A1). Everything
> else comes back from the restic repositories.
>
> Read "[Before you start](#before-you-start)" in full and tick every box before the
> first destructive step. The point of this document is that nothing has to be
> remembered or improvised on the day: every step is a numbered instruction with its
> commands.

## What Phase B is

The migration is split in two (see [apps-migration-plan.md](apps-migration-plan.md) for
the architecture and per-stack progress):

- **Phase A** — build the apps NixOS VM on the *test* hypervisor and migrate every stack
  to it, against partial data. Done.
- **Phase B — this document** — take the legacy box out of service, reinstall it as the
  real hypervisor, move the VMs that already run on the test hypervisor onto it, build
  the production apps VM there and restore production's data into it.

| Machine | Before | After |
|---|---|---|
| Legacy prod box (i5-13400) | `snyssen.be`, bare-metal Ubuntu, Ansible | `hypervisor-01` (NixOS), running haos, technitium-secondary and `apps-01` |
| Test hypervisor | `hypervisor`, running haos, technitium-secondary and the Phase A `apps` | retired; its disks join `hypervisor-01` (step A2) |
| apps VM | `apps` on the test hypervisor, test domains | `apps-01` on `hypervisor-01`, production domains, LAN IP `192.168.1.10` |

Phase B is also the real disaster-recovery rehearsal: `apps-01` boots *held* and is
restored with the same tools as [the DR runbook](../backups.md#full-disaster-recovery-rebuilding-apps-01-from-scratch).

### How the storage moves

There is no spare disk, so both pools on `hypervisor-01` start with **one disk** each and
grow after the cutover:

| Pool | At install | After the cutover |
|---|---|---|
| `vmstore` (SSD) | the 1 TB Kingston NVMe, taken out of the test hypervisor's vmstore (step P7) | + the test hypervisor's 500 GB WD SSD and its 1 TB Micron boot NVMe → RAID1, ~1.25 TB (step A2) |
| `bulk` (HDD) | the legacy box's 16 TB parity disk (`ata-ST16000NM000J-2TW103_ZR58BLR6`), which holds no data | + the legacy data disks, 12 TB and 8 TB, once verified → RAID1, ~18 TB (step A1); + the test hypervisor's HDDs if there are bays (step A2) |

The legacy data disks never appear in `hypervisor-01`'s disk configuration before step
A1, because nixos-anywhere formats every disk it knows about:

- `ata-ST8000VN004-3CP101_WWZ3XVDG` — 8 TB IronWolf, legacy `/mnt/disk1`
- `ata-ST12000NM0538-2K2101_ZHZ12PTZ` — 12 TB Exos X14, legacy `/mnt/disk2`

Until A1 they are the only on-disk copy of the media; the backup server has
the other.

### How the data moves

| What | From | Tool |
|---|---|---|
| Everything under the legacy `/mnt/storage` (media, Nextcloud, photos, the final PostgreSQL dumps, paperless media, minecraft, Matrix media, Sharkey files, recipes, dawarich storage, PeerTube videos) | the legacy data disks, at disk speed, on `hypervisor-01` | `legacy-import` |
| Everything under the legacy `/home/snyssen/data` (app configs, Grafana, paperless data, Actual, FoundryVTT, Sharkey's Redis) | production's restic snapshots, on `apps-01` | `prod-import` |
| Any `legacy-import` group that fails | production's restic snapshots | `prod-import <group>`, the fallback |
| The databases | the dumps the two above put in `/mnt/bulk/restore/prod-*` | `postgres-restore --from` |
| UniFi | a `.unf` downloaded from the legacy controller | the controller's setup wizard |

Both import tools read the same table, `nix/hosts/apps-01/prod-layout.nix`. The paths
and owners `prod-import` was tested with during Phase A are therefore exactly the ones
`legacy-import` uses; only the transport differs. See
[the import tools](#the-import-tools).

### The hold

`apps-01` is built with `restoreHold.stacks` and `restoreHold.backups` set in its
`configuration.nix` (`nix/hosts/apps-01/restore-hold.nix`). Its first boot starts no
compose stack, no Backrest and no data-acting timer. Every unit still exists, so you
start `compose-databases` by hand for the database restore, and the restore tools leave
stopped units stopped. Releasing a hold is a commit, a deploy with `boot` and a reboot
(steps D7 and D8). It replaces masking units at the GRUB prompt, which needs a console in
time to catch the boot.

## Before you start

Nothing here is destructive. All of it has to be true *before* anything is.

### What Phase A leaves to finish

Phase A itself is done: every stack is migrated and tested on `apps`, and the DNS
migration (#153/#170) is live. Two things it left open have to be closed before D-day:

- [x] **`grafana-to-ntfy` on apps-01.** Prod relays Grafana alerts to ntfy through it.
      Now in apps-01's monitoring stack, with the `monitoring` ntfy user's password
      copied from the vault into `nix/hosts/apps-01/data/ntfy.yaml`. Its test is the
      Grafana line of D7's ntfy check.
- [x] The Backrest design for after the cutover: production's two repositories, B2
      twins, check and prune policies (`nix/hosts/apps-01/backrest.nix`, described in
      [the backups doc](../backups.md#two-repositories-productions-own)), with the
      B2 bucket path and credentials from the vault.

### Backups must be verified, not assumed

- [x] A **fresh, complete** autorestic run on production has finished, with no
      failures in `/var/log/autorestic`.
- [x] `autorestic --ci check` has passed recently on **both** backends
      (`backup-snyssen-be` on-site and `snyssen-be-autorestic` on B2).
- [x] Every `prod-import` group resolves against the real repository. From the Phase A
      `apps` VM, which has the same command:

      ```sh
      ssh apps
      sudo prod-import --list
      sudo prod-import --all --check   # resolves each snapshot, proves every path exists
      ```

- [x] The off-site B2 copy is current. The on-site REST server is a single machine in
      the same building as the one being reinstalled.

### Credentials must exist outside this infrastructure

This is the step that is *actually* irreversible if skipped — see
[key management](../backups.md#key-management-the-actual-single-point-of-failure).

- [x] The breakglass age key is in the password manager **and** is a recipient on every
      secrets file (`git grep -c age1mpnhsfpava0 -- 'nix/hosts/*/data/*'`).
- [x] Both restic repository passwords are in the password manager, as plain text, not
      only inside sops.
- [x] The backup server's **IP address** (`192.168.1.11`) is written down somewhere
      outside this repository: its name is served by Technitium, which a disaster can
      take down too.
- [x] The LUKS passphrase the hypervisors use as a fallback is in the password manager.

### Capacity must be checked, not remembered

Step P2 measures the real numbers. The Phase A estimates, which **will have grown**:

| location | measured size (Phase A) |
| --- | --- |
| `tv` | ~5590 GB |
| `movies` | ~4190 GB |
| `music` (+ `music_vi`) | ~818 GB |
| `nextcloud` | ~353 GB |
| `photos` | ~88 GB |
| `postgres` (all dump dirs) | ~77 GB |
| `audiobooks`, `podcasts`, `books`, PeerTube videos | not measured |

- [x] What `legacy-import` copies fits on the 16 TB disk (~14.5 TiB) with headroom:
      `legacy-import --check --all` reports it on the day (D4), but measure it in P2 so
      there is no surprise.
- [x] The apps-01 disk fits the measured `/home/snyssen/data` and Docker footprint on the
      1 TB vmstore (P2).

## The import tools

**`prod-import`** (on `apps-01`) restores groups from production's restic snapshots,
with paths and owners translated. It is built from the same generator as
`backrest-restore` (`nix/modules/nixos/backrest/restore.nix`), so it shares that
command's safety behaviour: snapshot resolution per group, a real `--dry-run` size
preflight, a confirmation prompt, and `--at`. See
[the backups doc](../backups.md#the-restore-commands) for the shared flags.

**`legacy-import`** (on `hypervisor-01`, `nix/hosts/hypervisor-01/legacy-import.nix`)
copies the `/mnt/storage` groups off the two legacy data disks, which it mounts
read-only itself. `/mnt/storage` was a mergerfs pool over both disks, so a directory may
be split across them; it copies from each. It writes to this host's side of apps-01's
bulk mount (apps-01's `/mnt/bulk/X` is `hypervisor-01`'s `/mnt/bulk/apps/X`). It uses
`rsync -aHAX --numeric-ids` with the table's owner, never deletes anything in a target,
and resumes when re-run. The summary lists every path ok or FAIL, with the `prod-import`
command that takes over a FAIL.

```sh
legacy-import --list                 # every group, and which ones only prod-import has
legacy-import --check --all          # per path: which disk, how big, files on both disks, room left
legacy-import --dry-run <group>...
legacy-import <group>... | --all     # --all puts the media last
```

`restic` restores numeric owners verbatim, and so does `rsync --numeric-ids`, so
production's uid/gid conventions (gid 1000 for the media apps, where this host uses
100) are translated by each row's `owner`, applied recursively.

### Groups

| group | from (legacy) | to (apps-01) | tool |
| --- | --- | --- | --- |
| `monitoring` | `/home/snyssen/data/grafana/data` | `/var/lib/app-data/monitoring/grafana` | prod-import |
| `streaming-config` | jellyfin, audiobookshelf, the 8 `*arr` configs, peertube config | `/var/lib/app-data/…` | prod-import |
| `paperless` | `/home/snyssen/data/paperless/data` | `/var/lib/app-data/paperless/data` | prod-import |
| `actual-budget` | `/home/snyssen/data/actual-budget` | `/var/lib/app-data/actual-budget` | prod-import |
| `foundryvtt` | `/home/snyssen/data/foundryvtt` | `/var/lib/app-data/foundryvtt` | prod-import |
| `sharkey` | `/home/snyssen/data/sharkey/redis` | `/var/lib/app-data/sharkey/redis` | prod-import |
| `postgres` | `/mnt/storage/backups/postgres` | `/mnt/bulk/restore/prod-postgres` (**staging**) | legacy-import |
| `immich` | `/mnt/storage/backups/immich` | `/mnt/bulk/restore/prod-immich` (**staging**) | legacy-import |
| `dawarich` | `/mnt/storage/backups/dawarich` | `/mnt/bulk/restore/prod-dawarich` (**staging**) | legacy-import |
| `dawarich-storage` | `/mnt/storage/dawarich/storage` | `/mnt/bulk/dawarich/storage` | legacy-import, **disks only** |
| `nextcloud` | `/mnt/storage/nextcloud` | `/mnt/bulk/nextcloud` | legacy-import |
| `paperless-media` | `/mnt/storage/paperless/media` | `/mnt/bulk/paperless/media` | legacy-import |
| `photos` | `/mnt/storage/photos` | `/mnt/bulk/photos` | legacy-import |
| `matrix` | `/mnt/storage/matrix/synapse/media_store` | `/mnt/bulk/matrix/synapse/media_store` | legacy-import |
| `minecraft` | `/mnt/storage/{minecraft,mc-usw}/data` | `/mnt/bulk/{minecraft,mc-usw}/data` | legacy-import |
| `recipes` | `/mnt/storage/recipes/mediafiles` | `/mnt/bulk/recipes/mediafiles` | legacy-import |
| `sharkey-files` | `/mnt/storage/sharkey/files` | `/mnt/bulk/sharkey/files` | legacy-import |
| `movies` / `tv` / `music` / `audiobooks` | `/mnt/storage/streaming/media/…` | `/mnt/bulk/streaming/media/…` | legacy-import |
| `media-extra` | `/mnt/storage/streaming/media/{podcasts,podcasts_vi,books}` | same under `/mnt/bulk` | legacy-import, **disks only** |
| `peertube-data` | `/mnt/storage/streaming/peertube/data` | `/mnt/bulk/streaming/peertube/data` | legacy-import, **disks only** |

**Disks only** means the group is in no autorestic location: if `legacy-import` cannot
copy it, there is no restic fallback, so fix the cause and re-run it. Every other
`legacy-import` group falls back to `prod-import <group>`.

The three **staging** groups are deliberate. Production's PostgreSQL dumps must not land
on `/mnt/bulk/backups/*`: that is `apps-01`'s own dump directory, feeding its own
`databases` backup plan. They are loaded with `postgres-restore --from`.

**Not imported, on purpose**: `paperless-export` (regenerated nightly from the library);
Syncthing's folders (apps-01 fills them from its peers); in-progress downloads
(`torrent`, `usenet`), inboxes (paperless `consume`, dawarich `watched`); Garage (the Nix
cache refills from the next pushes); Uptime Kuma (replaced by Gatus, whose checks are in
the repo); ntfy (provisioned from sops); UniFi (its own `.unf`). Docker named volumes are
all disposable caches; anything stateful is a bind mount. The legacy data disks stay
untouched until A1, so anything found missing until then can still be copied by hand.

## P — Preparation

Weeks ahead. Production keeps serving throughout, except for haos and
technitium-secondary during P7.

### P1. Before you start

- [x] Every box in [Before you start](#before-you-start) is ticked.

### P2. Measure the legacy box

Read-only, on the legacy box:

```sh
ssh snyssen.be
lsblk -o NAME,SIZE,MODEL,SERIAL,MOUNTPOINTS      # which disk holds /: the boot SSD
ls -l /dev/disk/by-id/ | grep -v -- -part        # its by-id name
ip -br link                                      # the wired NIC's MAC address
lspci -nn | grep -iE 'vga|display'               # 00:02.0 ... [8086:xxxx]: the iGPU's id
[ -d /sys/firmware/efi ] && echo UEFI || echo BIOS   # must be UEFI
free -g                                          # RAM, for apps-01's share
df -h / /mnt/disk1 /mnt/disk2 /mnt/parity1
sudo du -sh /home/snyssen/data                   # what goes into apps-01's disk
docker system df                                 # plus images and volumes
sudo du -sh /mnt/storage/streaming/media /mnt/storage/streaming/peertube/data \
  /mnt/storage/nextcloud /mnt/storage/photos
sudo du -sh /mnt/storage/dawarich/storage; sudo find /mnt/storage/dawarich/storage -type f | head
```

`/mnt/storage/dawarich/storage` is Dawarich's file store (Rails ActiveStorage): files
uploaded through the web UI's Imports page, and exports generated from it. It is not the
`watched` import folder. The points themselves are all in the database, so it only
matters if you uploaded something you can't download again. Production backs it up
nowhere; `legacy-import dawarich-storage` copies it, and apps-01's `dawarich` plan backs
it up from D8 on. If it is empty, drop that group from the D4 command.

Then fill in the `TODO(P2)` placeholders and commit:

- [x] `nix/hosts/hypervisor-01/configuration.nix`: `mainDiskPath` (the boot SSD's
      `/dev/disk/by-id/…`) and the vfio-pci id (`8086:xxxx`).
- [x] `nix/hosts/hypervisor-01/network.nix`: `macAddress`. The NIC is named `lan0` by
      its MAC, since its `enpXs0` name changes once the Kingston is fitted (D2).
- [x] `ansible/hosts/host_vars/hypervisor-01/vars.yml`, `apps-01`:
  - `ram_mb`: leave the host at least 8 GB;
  - `disk_gb`: app-data plus Docker, with ~50% headroom, at most ~850 (the 1 TB vmstore
    also holds haos and technitium-secondary).
- [x] If the firmware boots BIOS, switch it to UEFI before D2.
- [x] Used space on `/mnt/disk1` + `/mnt/disk2` is well under 14.5 TiB.
- [x] `just nix-build hypervisor-01` succeeds.

### P3. Tailscale auth keys

`nix/hosts/hypervisor-01/data/secrets.yaml` is a copy of the test hypervisor's, and
`nix/hosts/apps-01/data/common.yaml` holds the Phase A VM's key. In the Tailscale admin
console (Settings → Keys), check that the keys they hold are **reusable** (or not yet
used), **pre-approved** and not expiring before D-day. If not, create new ones and put
them in:

```sh
just sops-update nix/hosts/hypervisor-01/data/secrets.yaml   # key: tailscale/authKey
just sops-update nix/hosts/apps-01/data/common.yaml          # key: tailscale/authKey
```

- [x] Keys checked

### P4. hypervisor-01's keys

The SSH host key decides the host's sops identity, so it is made now and installed with
nixos-anywhere (see [Setup New Machine — Pre-Deployment](../nix/Setup%20New%20Machine/Setup%20New%20Machine%20-%20Pre-Deployment.md)
for the background). Keep it out of `/tmp`, which may not survive until D-day:

```sh
H=hypervisor-01
DEPLOY=~/phase-b/$H-deploy
mkdir -p "$DEPLOY/etc/ssh" && chmod 700 ~/phase-b
ssh-keygen -t ed25519 -f "$DEPLOY/etc/ssh/ssh_host_ed25519_key" -N "" -C "root@$H"
just sops-gen-privkey "$DEPLOY/etc/ssh/ssh_host_ed25519_key" ~/phase-b/$H-age-temp
just sops-get-pubkey ~/phase-b/$H-age-temp     # prints age1...
rm ~/phase-b/$H-age-temp
```

- [x] Keys generated

In `.sops.yaml`, add the printed key under `keys:` as `- &root_hypervisor_01 age1…`, and
in the `nix/hosts/hypervisor-01/data/` rule replace `*root_hypervisor` with
`*root_hypervisor_01` (and drop the comment above it). Then:

```sh
just sops-update-keys nix/hosts/hypervisor-01/data/secrets.yaml
```

Commit `.sops.yaml` and the re-encrypted file.

- [x] Key saved

**USB keyfile.** The same two sticks unlock both hypervisors; each gets a second keyfile,
named after the new host. Make it once and copy it to both sticks:

```sh
dd if=/dev/urandom of=~/phase-b/hypervisor-01 bs=512 count=1
# for each stick: mount it, then
cp ~/phase-b/hypervisor-01 /run/media/$USER/<stick>/hypervisor-01 && sync
```

- [x] USB stick prepared and keys are backed up

**LUKS fallback passphrase**, the one in the password manager, for nixos-anywhere:

```sh
read -s > ~/phase-b/hypervisor-01-luks-password.txt
```

- [x] Fallback password is saved in passwords manager

### P5. Rehearse adding a disk (test hypervisor)

Proves the [corrected procedure](overview.md#adding-a-disk-to-an-existing-pool) on a pool
whose data doesn't matter, with the spare 2 TB WD20EZRZ still in the test box. If it
isn't there any more, use any spare disk.

Uses two disk tools:

- `wipefs` (util-linux, on every NixOS host) erases filesystem, RAID and partition-table
  signatures, so nothing recognises the old contents any more;
- `sgdisk` (gptfdisk, the scriptable form of `gdisk`) edits GPT partition tables from
  the command line: `--zap-all` destroys the table, `--new` creates a partition,
  `--typecode`/`--change-name` set its type and partition label. The label is what boot
  finds a pool's disks by.

Both hypervisors' configs include `sgdisk` (and `screen`), and the NixOS installer has
both tools.

1. On the test hypervisor:

   ```sh
   ssh root@hypervisor
   NEW=/dev/disk/by-id/ata-WDC_WD20EZRZ-00Z5HB0_WD-WCC4N2RYUKT9
   POOL=bulk; I=2
   LABEL="disk-0-before-$POOL-$((I - 1))-luks-$POOL"; NAME="crypt-$POOL-$I"
   sgdisk --zap-all "$NEW"
   sgdisk --new=1:0:0 --typecode=1:8309 --change-name=1:"$LABEL" "$NEW"
   udevadm settle
   mkdir -p /key && mount -o ro /dev/disk/by-uuid/9FBA-884A /key
   cryptsetup luksFormat --batch-mode "/dev/disk/by-partlabel/$LABEL" /key/hypervisor
   cryptsetup luksAddKey --key-file /key/hypervisor "/dev/disk/by-partlabel/$LABEL"
   cryptsetup open --key-file /key/hypervisor "/dev/disk/by-partlabel/$LABEL" "$NAME"
   umount /key
   ```

2. In `nix/hosts/hypervisor/configuration.nix`, uncomment the WD20EZRZ line in `bulk`.
   Deploy: `just nix-remote-install switch hypervisor`.
3. Add it to the pool, rebalance and reboot:

   ```sh
   ssh root@hypervisor
   btrfs device add /dev/mapper/crypt-bulk-2 /mnt/bulk
   btrfs balance start -dconvert=raid1,soft -mconvert=raid1,soft /mnt/bulk
   reboot
   ```

4. Once it is back: `ssh root@hypervisor ls /dev/mapper/` shows `crypt-bulk-2`, and
   `btrfs filesystem show /mnt/bulk` shows three devices. **This is the check that
   matters**: the disk was unlocked at boot from its partition label.
5. Take it out again ([Removing a Disk](overview.md#removing-a-disk-from-a-pool); it is
   the last index, so nothing needs relabelling):

   ```sh
   ssh root@hypervisor
   btrfs device remove /dev/mapper/crypt-bulk-2 /mnt/bulk
   cryptsetup close crypt-bulk-2
   ```

   Comment the line again, `just nix-remote-install boot hypervisor`, reboot.

- [x] Rehearsal done

### P6. Rehearse `legacy-import` (test hypervisor)

The test hypervisor has `legacy-import` too, with no data disks, so it runs on two small
loop images instead. The sample data is what Phase A already imported from production,
in `/mnt/bulk/apps`. The rehearsal writes to `/mnt/bulk/rehearsal` (`--target`), never
over it.

1. `legacy-import` came with P5's deploy: `ssh root@hypervisor legacy-import --list`.
2. Build two "data disks", with one directory split across both as mergerfs did:

   ```sh
   ssh root@hypervisor
   mkdir -p /root/rehearsal && cd /root/rehearsal
   # Sparse: they only take the space written into them. The dumps alone are ~125 GB.
   truncate -s 100G disk1.img disk2.img
   # mkfs.ext4 (e2fsprogs) isn't installed: only this rehearsal needs it
   nix shell nixpkgs#e2fsprogs -c sh -c 'mkfs.ext4 -q -F disk1.img && mkfs.ext4 -q -F disk2.img'
   mkdir -p d1 d2 && mount -o loop disk1.img d1 && mount -o loop disk2.img d2
   mkdir -p d1/recipes d2/minecraft d1/backups/postgres d2/backups/postgres
   cp -a /mnt/bulk/apps/recipes/mediafiles d1/recipes/
   cp -a /mnt/bulk/apps/minecraft/data d2/minecraft/
   # half the dump tiers (daily/, last/, …) on each disk: one directory split across both
   ls /mnt/bulk/apps/restore/prod-postgres | awk 'NR%2' | xargs -I{} cp -a /mnt/bulk/apps/restore/prod-postgres/{} d1/backups/postgres/
   ls /mnt/bulk/apps/restore/prod-postgres | awk '!(NR%2)' | xargs -I{} cp -a /mnt/bulk/apps/restore/prod-postgres/{} d2/backups/postgres/
   ```

   (If any of those sources is missing, use any other Phase A path under
   `/mnt/bulk/apps`; the point is real files in the legacy layout.)

   If an image fills up anyway (`No space left on device`), grow it in place and re-run
   the copy that failed. Here for `disk1.img`; `losetup -j disk1.img` names its loop
   device:

   ```sh
   truncate -s 150G disk1.img
   losetup -c /dev/loop0
   nix shell nixpkgs#e2fsprogs -c resize2fs /dev/loop0
   ```

3. Run it:

   ```sh
   legacy-import --check --sources /root/rehearsal/d1,/root/rehearsal/d2 --target /mnt/bulk/rehearsal recipes minecraft postgres
   legacy-import --sources /root/rehearsal/d1,/root/rehearsal/d2 --target /mnt/bulk/rehearsal recipes minecraft postgres photos
   ```

   Expect `ok` for recipes, minecraft's `data` and postgres. Expect `FAIL` for
   minecraft's `mc-usw` and for `photos` (not on the images), each naming its
   `prod-import` fallback, and a non-zero exit.
4. Check owners and contents:

   ```sh
   stat -c '%u:%g %n' /mnt/bulk/rehearsal/minecraft/data /mnt/bulk/rehearsal/recipes/mediafiles
   diff -r /mnt/bulk/apps/recipes/mediafiles /mnt/bulk/rehearsal/recipes/mediafiles && echo SAME
   ls /mnt/bulk/rehearsal/restore/prod-postgres | wc -l; ls /mnt/bulk/apps/restore/prod-postgres | wc -l
   ```

   `1000:1000` for minecraft, `0:0` for recipes, identical contents, and both halves of
   the dumps in one directory.
5. Re-run the same command: it finishes quickly (nothing left to copy).
6. Clean up:

   ```sh
   cd /root && umount rehearsal/d1 rehearsal/d2 && rm -r rehearsal /mnt/bulk/rehearsal
   losetup -a                  # nothing left
   ```

- [x] Rehearsal done

### P7. Take the Kingston NVMe out of the test hypervisor

The test vmstore is RAID1 over the 1 TB Kingston and the 500 GB WD. It drops to the WD
alone, and the Kingston goes to `hypervisor-01`. haos and technitium-secondary keep
running throughout the conversion and are only down for the final reboot.

1. Safety copies, on your machine:
   - In Home Assistant: Settings → System → Backups → download the newest backup.
   - technitium-secondary's image and key, in case it has to be put back by hand:

     ```sh
     mkdir -p ~/phase-b/vm-copy
     ssh root@hypervisor 'tar -C / -cSf - mnt/vmstore/technitium-secondary var/lib/vm-keys/technitium-secondary var/lib/libvirt/qemu/nvram/technitium-secondary_VARS.fd' > ~/phase-b/vm-copy/technitium-secondary.tar
     ```

2. Check it fits: `FS bytes used` must be well under the WD's 465 GiB (it was 312 GiB at
   the time of writing). Not `btrfs filesystem usage`: its `Used` counts both RAID1 copies,
   so it shows twice the data.

   ```sh
   ssh root@hypervisor btrfs filesystem show /mnt/vmstore   # FS bytes used
   ```

3. Convert and remove the Kingston (index 0, `crypt-vmstore-0`), in a `screen` session
   (see [Long-running steps](#long-running-steps-screen)):

   ```sh
   ssh root@hypervisor
   screen -S vmstore
   btrfs balance start -dconvert=single -mconvert=dup /mnt/vmstore
   btrfs device remove /dev/mapper/crypt-vmstore-0 /mnt/vmstore
   btrfs filesystem show /mnt/vmstore            # one device left: the WD
   cryptsetup close crypt-vmstore-0
   ```

4. Relabel. The WD becomes index 0, so it takes index 0's label. The Kingston gives it
   up first, so no two partitions share it:

   ```sh
   sgdisk --change-name=1:retired-vmstore /dev/disk/by-id/nvme-KINGSTON_SNV3S1000G_50026B7383A64113
   sgdisk --change-name=1:disk-vmstore-luks-vmstore /dev/disk/by-id/ata-WDC_WDS500G2B0B-00YS70_204246801987
   udevadm settle
   ls -l /dev/disk/by-partlabel/ | grep vmstore  # disk-vmstore-luks-vmstore -> the WD's partition
   ```

5. In `nix/hosts/hypervisor/configuration.nix`, make the vmstore pool the WD alone:

   ```nix
   vmstore = {
     disks = [
       "/dev/disk/by-id/ata-WDC_WDS500G2B0B-00YS70_204246801987"
     ];
     storageMedia = "ssd";
   };
   ```

   Commit, then deploy for the next boot only (the mapper names change):
   `just nix-remote-install boot hypervisor`.
6. Shut the test hypervisor down (`ssh root@hypervisor poweroff`), take the Kingston out,
   boot it. Check:

   ```sh
   ssh root@hypervisor 'ls /dev/mapper/; btrfs filesystem show /mnt/vmstore; virsh list --all'
   ```

   `crypt-vmstore-0` on the WD, and haos, technitium-secondary and apps running.

- [x] Kingston NVMe is out of hypervisor and ready to be put in hypervisor-01

## D — D-day

Plan for about two days of downtime; the disk copy sets the pace. Run every long step in
**`screen`**: an SSH drop kills it otherwise.

### Long-running steps: `screen`

`screen` keeps a shell running on the server after your SSH connection drops. It is
installed on both hypervisors and on apps-01. All you need:

| Do | Command |
| --- | --- |
| Start a named session | `screen -S <name>` |
| Detach (it keeps running) | `Ctrl-a`, then `d` |
| List sessions | `screen -ls` |
| Re-attach | `screen -r <name>` |
| End it | `exit` inside it |

If the connection drops while you are attached, the session detaches by itself;
`screen -r <name>` gets it back. To scroll back through output: `Ctrl-a`, then `Esc`,
then the arrow keys or PgUp; `Esc` again to leave.

### Binary cache

`cache.snyssen.be` is down from D1 until the stacks are back (D7), and every Nix command
that lists it as a substituter (nixos-anywhere, `just nix-remote-install`, a `nix shell`
on hypervisor-01) waits on it first. Leave it out, in every shell you use until D7, on
your machine and on hypervisor-01:

```sh
export NIX_CONFIG="substituters = https://nix-community.cachix.org https://cache.nixos.org/"
```

Narrowing the list needs no trusted user: Nix accepts any subset of the substituters it
is configured with. A new shell, or `unset NIX_CONFIG`, brings the cache back.

### D1. Freeze and final backup

- [x] Announce downtime to anyone else who uses the services.
- [x] Stop writing: pause anything that ingests data (paperless consume folder, `*arr`
      downloads, Syncthing, Immich mobile backup,sharkey).
- [x] UniFi: on the legacy controller, Settings → System → Advanced → **Inform Host**
      must be the name `unifi.snyssen.be`, not the legacy box's IP, so devices follow
      DNS to apps-01. If it isn't, set it and wait for every device to show Online
      again.
- [x] UniFi: Settings → System → Backups → **download** a backup to your machine.
- [x] Home Assistant: download its newest backup to your machine. Its backups normally go
      to the legacy Nextcloud, which is about to go down.
- [x] Run the final PostgreSQL dumps and confirm they are in the dump directories
      (`/mnt/storage/backups/{postgres,immich,dawarich}`). `legacy-import` copies these.
- [x] Run a final full autorestic backup, **and watch it finish**. Then disable
      autorestic's cron.
- [x] `autorestic --ci check` on both backends, one last time.
- [x] Note the snapshot ID of every location. If a `prod-import` later resolves an older
      snapshot than these, something is wrong.

```yaml
# Save snapshots IDs here:
backup.snyssen.be:
    tv: 5bc1f831
    syncthing: f97acbb8
    nextcloud: ad7806fe
    music: 0b28883c
    actual-budget: ac191c60
    paperless-export: 4a4c099b
    minecraft: 2c70f5c4
    paperless: c5b33c6e
    audiobooks: d9e4eaf8
    sharkey: 0b123a9e
    movies: 2e63f3ad
    ntfy: bc06b10b
    monitoring: 625011eb
    foundryvtt: 22a675be
    # mobilizon: 06a35bb4
    matrix: 74aaf348
    unifi: 506d6140
    postgres: 4cb8227b
    streaming-config: 3d0f1227
    recipes: ecaab362
    photos: cae29784
```

- [x] Shut down the Phase A VM for good. It shares apps-01's Syncthing identity and MAC,
      so the two must never run at once:

      ```sh
      ssh root@hypervisor 'virsh shutdown apps; virsh autostart --disable apps'
      ```

### D2. Install hypervisor-01

1. `ssh snyssen.be sudo poweroff`.
2. Fit the Kingston NVMe in the free M.2 slot. Label the HDDs physically:
   - "FORMAT" on the 16 TB parity disk (`ZR58BLR6`);
   - "KEEP" on the 8 TB (`WWZ3XVDG`) and the 12 TB (`ZHZ12PTZ`).
3. **Unplug the two KEEP disks** (SATA data cable) for the install. Nothing in the
   config formats them, but unplugged they can't be touched by mistake.
4. Boot the NixOS installer USB, with one of the USB key sticks plugged in. On the
   console:

   ```sh
   passwd                                        # temporary, for nixos-anywhere
   ip -br addr                                   # note the IP
   lsblk -d -o NAME,SIZE,MODEL,SERIAL            # boot SSD, Kingston, 16 TB: nothing else
   mkdir -m 0755 -p /key && mount -n -t vfat -o ro -U 73A2-0467 /key   # or 9FBA-884A
   ls /key                                       # hypervisor-01 is there
   ```

5. From your machine, at the repo root, on the commit with P2–P4 in. `nix flake check`
   passes on it, run locally: argunix is down until after the cutover (the Phase A VM
   doesn't have the RAM for it), so it can't vouch for the commit:

   ```sh
   TARGET_IP=<the IP above>
   nix run github:nix-community/nixos-anywhere -- \
     --flake .#hypervisor-01 \
     --target-host root@$TARGET_IP \
     --generate-hardware-config nixos-generate-config \
       nix/hosts/hypervisor-01/hardware-configuration.nix \
     --extra-files ~/phase-b/hypervisor-01-deploy \
     --disk-encryption-keys /tmp/secret.key ~/phase-b/hypervisor-01-luks-password.txt \
     --chown /etc/ssh/ssh_host_ed25519_key 0:0 \
     --chown /etc/ssh/ssh_host_ed25519_key.pub 0:0
   ```

   See [Setup New Machine — Deployment](../nix/Setup%20New%20Machine/Setup%20New%20Machine%20-%20Deployment.md)
   for what each part does and what to expect.
6. It reboots into hypervisor-01. Commit the generated
   `nix/hosts/hypervisor-01/hardware-configuration.nix`.
7. Power it off, plug the two KEEP disks back in, boot.
8. Delete `~/phase-b/hypervisor-01-deploy` and `~/phase-b/hypervisor-01-luks-password.txt`
   from your machine.

- [x] hypervisor-01 is booted on the new system

### D3. Check hypervisor-01

```sh
ssh root@hypervisor-01
btrfs filesystem show /mnt/vmstore /mnt/bulk     # one device each
btrfs filesystem usage /mnt/bulk | grep -E 'Data|Metadata'   # single / DUP
tailscale status                                 # joined
ls -l /dev/disk/by-id/ | grep -E 'WWZ3XVDG|ZHZ12PTZ'   # both KEEP disks visible
ls /sys/bus/pci/devices/0000:00:02.0/iommu_group/devices/   # only 0000:00:02.0
basename "$(readlink /sys/bus/pci/devices/0000:00:02.0/driver)"   # vfio-pci
bridge link                                      # lan0 master br0
ip -br addr show br0                             # the host's LAN address is on br0
```

In the Tailscale admin console, **remove the legacy box's machine**. That frees its
address, `100.114.242.89`, for apps-01 (D5).

- [x] All checks are green on hypervisor-01

### D4. Start `legacy-import`

It runs for many hours. Everything up to D6's database restores can happen alongside it.

```sh
ssh root@hypervisor-01
screen -S import
legacy-import --check --all     # sizes, files on both disks, room on bulk
```

Look at any `WARNING: … exist on both disks` (the copy from the second disk would win)
before going on. Then copy everything. `--all` takes the app data first and the media
last (`legacy-import --list` shows the order), and a failed row doesn't stop the rest,
so it can run unattended overnight. The log outlives screen's 100-line scrollback:

```sh
legacy-import --all 2>&1 | tee /root/legacy-import.log
```

Detach with `Ctrl-a d`; re-attach with `screen -r import`. Note every `FAIL` line in
the summary (`grep -E '^(FAIL|ok) ' /root/legacy-import.log`): each names the
`prod-import` command that takes over (D6).

- [ ] All data copied successfully

### D5. Build and boot apps-01

Until D7, reach apps-01 as root over its LAN address, `ssh root@192.168.1.10`, wherever
this runbook says `ssh apps-01`. Tailscale SSH re-authenticates through Authelia, which
runs on apps-01 and is down until then; `nix/hosts/apps-01/cutover-root-ssh.nix` lets
your two keys in as root meanwhile, on the LAN address only (Tailscale SSH holds port
22 on the tailnet one).

1. Build the image:

   ```sh
   just hypervisor-build-vm-images hypervisor-01
   ```

   It generates apps-01's SSH host key, prints the age key derived from it, and
   **pauses**. While it waits, in another terminal at the repo root:

   - in `.sops.yaml`, add `- &root_apps_01 age1…` (the printed key) under `keys:`, and in
     the `nix/hosts/apps-01/data/` rule replace `*root_apps` with `*root_apps_01` (and
     drop the comment above it);
   - re-encrypt apps-01's files for it. **Before** continuing, since the image is built
     from them as they are now:

     ```sh
     for f in nix/hosts/apps-01/data/*.yaml; do sops updatekeys -y "$f"; done
     ```

   Then type `CONTINUE`. When it finishes, commit `.sops.yaml` and
   `nix/hosts/apps-01/data/`. Set `build: false` on apps-01 in
   `ansible/hosts/host_vars/hypervisor-01/vars.yml` and commit that too.
2. Provision and start it:

   ```sh
   just hypervisor-provision-vms hypervisor-01 -e libvirt_vms_only=apps-01
   ```

3. It boots **held**. Check, on it:

   ```sh
   ssh apps-01
   ip -br addr | grep 192.168.1.10                 # static LAN address
   sudo ls /run/secrets/backrest/repos/            # sops decrypts
   ls /mnt/bulk                                    # the NFS mount from hypervisor-01
   systemctl list-units 'compose-*' --no-legend    # nothing running
   ```

4. In the Tailscale admin console, edit apps-01's machine and set its IPv4 address to
   `100.114.242.89`, the legacy box's. The split-horizon records for `snyssen.be`,
   `*.snyssen.be` and `bigdouf.team`, and ingress's `appsServerIp`, all name that
   address, so none of them changes. Then `sudo systemctl restart tailscaled` on
   apps-01, and check `tailscale ip -4`. If the console doesn't allow it, edit those
   records in `ansible/hosts/group_vars/technitium/vars.yml` and `appsServerIp` in
   `nix/hosts/ingress/traefik-configuration.nix` to apps-01's address instead.
5. The `argunix` and `argunix-ingress` records still name the Phase A VM
   (`100.86.224.95`). Point them at `100.114.242.89` in
   `ansible/hosts/group_vars/technitium/vars.yml`, commit, push, and:

   ```sh
   just ansible-playbook technitium-setup -i hosts/prod.yml
   ```

   argunix comes back with the stacks in D7. Once it does, check that
   <https://argunix.snyssen.be> evaluates the latest commit: it is the first CI run since
   the Phase A VM.

### D6. Restore

On apps-01, in `screen` (`ssh apps-01`, `sudo -i`, `screen -S restore`).

1. The boot-SSD groups, from restic. These go into the VM's own disk and don't depend on
   `legacy-import`:

   ```sh
   prod-import --check monitoring streaming-config paperless actual-budget foundryvtt sharkey
   prod-import --dry-run monitoring streaming-config paperless actual-budget foundryvtt sharkey
   prod-import monitoring streaming-config paperless actual-budget foundryvtt sharkey
   ```

   **Never** `prod-import --all` here: that would also pull the ~10.6 TB of media through
   restic.
2. Any group `legacy-import` reported as `FAIL` (except a disks-only one, which needs
   `legacy-import` re-run on hypervisor-01): `prod-import <group>`.
3. Once `legacy-import`'s **first** command (the app data) has printed its summary, load
   the databases. There are three PostgreSQL instances:
   - the central cluster, in the `databases` stack;
   - Immich's own, in the `immich` stack;
   - Dawarich's own, in the `dawarich` stack.

   The hold leaves all three stacks stopped. Start `databases` by hand: on start it
   creates every application's role and database, which the restore needs, and the
   Docker networks the other two use. Matrix needs its database created with collation
   `C` (see [Matrix](#per-stack-restore-notes)), which a fresh cluster does.

   Immich and Dawarich don't need starting: `postgres-restore` reaches them with
   `docker compose run` on their dump sidecar, and that starts only the sidecar's
   database container, not the app. That container is left running afterwards, so the
   last lines below stop all three stacks again; step D7 starts everything in order.

   ```sh
   systemctl start compose-databases
   postgres-restore --from /mnt/bulk/restore/prod-postgres --all --dry-run
   postgres-restore --from /mnt/bulk/restore/prod-postgres --all
   postgres-restore --from /mnt/bulk/restore/prod-immich immich
   postgres-restore --from /mnt/bulk/restore/prod-dawarich dawarich
   compose-immich down
   compose-dawarich down
   systemctl stop compose-databases
   docker ps --format '{{.Names}}'     # no databases, immich or dawarich container left
   ```

   `--from` applies to everything selected, so the central cluster goes first with
   `--all`, then one instance at a time. A database with no dump in the directory is
   listed as `skipped`, not as an error. In the dry run, check that `immich` and
   `dawarich` show `skipped` (their dumps are in their own directories) and every other
   database names a dump from the freeze.
4. Wait for `legacy-import`'s second command (the media) to finish, so the `*arr` apps
   never see an empty library.

### D7. Release the stacks, then verify

1. In `nix/hosts/apps-01/configuration.nix`, set `restoreHold.stacks = false`. Commit,
   push, then:

   ```sh
   just nix-remote-install boot apps-01 192.168.1.10
   ssh root@192.168.1.10 reboot
   ```

   Everything starts in dependency order. Traefik requests its certificates once, for
   the real domains.
2. UniFi: open `https://unifi.snyssen.be`, pick **restore from backup** in the setup
   wizard, and upload the `.unf` downloaded in D1.
3. Fix what the per-stack notes below say needs fixing (the `*arr` root folders, …).
4. Verify, before decommissioning anything:
   - [ ] Every service answers on its real hostname, over TLS, with a valid certificate,
         from the LAN, the tailnet, and outside (through ingress).
   - [ ] Authelia login works, including a second factor and at least one OIDC client.
   - [ ] Tailscale SSH works again (`ssh apps-01`, through Authelia). Then delete
         `nix/hosts/apps-01/cutover-root-ssh.nix` and its import, commit, and
         `just nix-remote-install switch apps-01`.
   - [ ] Nextcloud: files present, a desktop client syncs, CalDAV/CardDAV resolves.
   - [ ] Immich: assets present *and* thumbnails render (a restored database with absent
         files looks fine until you scroll).
   - [ ] Paperless: documents searchable, OCR runs on a new upload.
   - [ ] Jellyfin plays something; check the playback info for hardware (QSV)
         transcoding.
   - [ ] Matrix: log in through Element, recent messages and media load, a message
         reaches someone on another server, the bridges connect.
   - [ ] Sharkey: log in, timelines load, an existing image displays, a post reaches a
         remote follower.
   - [ ] UniFi: every device **Online**. They come back by themselves once
         `unifi.snyssen.be` resolves to apps-01 on the LAN, which it does from the
         start (`*.snyssen.be` → `192.168.1.10`).
   - [ ] Syncthing: the Pixel has `apps-01` with address `tcp://apps-01:22000` (edit
         the device by hand), and the folders are filling from the peers.
   - [ ] Monitoring: Grafana dashboards populated, Gatus checks green. The Grafana
         "Uptime Kuma" dashboard replaced by its Gatus version.
   - [ ] ntfy delivers to your phone, from each kind of sender (each one uses its own
         ntfy user, carried over from prod):
     - Grafana (`monitoring` user, through `grafana-to-ntfy`): Alerting → Contact
       points → the ntfy contact point → **Test**.
     - Home Assistant (`hass` user): Developer tools → Actions → the `notify.*` action
       that posts to ntfy, with a test message.
     - The `*arr` apps (`streaming` token): in Sonarr, Settings → Connect → the ntfy
       connection → **Test**.
     - UnifiedPush (anonymous `up*` topics): with Matrix live, a message from another
       account raises a notification from Element on the phone.

### D8. Release the backups

apps-01's Backrest is already configured for production's two repositories (see
[the backups doc](../backups.md#two-repositories-productions-own)): every plan into the
on-site repository, and its `-offsite` twin into B2, with check and prune policies on
both. Until now the hold kept it from starting, so the first thing it writes into those
repositories is apps-01's restored state. Autorestic's snapshots stay as they are;
`prod-import` keeps reading them.

1. Release the hold: in `nix/hosts/apps-01/configuration.nix`, set
   `restoreHold.backups = false`. Commit, push, then:

   ```sh
   just nix-remote-install switch apps-01
   ```

2. Let the first night run, or trigger the plans from Backrest's UI
   (`https://backrest.snyssen.be`) rather than waiting. Backrest runs one operation at a
   time, and these first runs read every file once (~12 TB with movies and tv), so they
   take a day or more. They upload next to nothing: restic finds the data already
   stored. Until they are through, expect `backups_*` Gatus checks to go red for missing
   their 26-hour heartbeat.
3. As each finishes, check in the UI that its snapshot **added** little data. A plan
   that uploads close to its full size means restic didn't recognise the data: stop and
   look before the B2 twins upload it all again.
4. Once every plan, on-site and off-site, has a snapshot, prove both restore commands
   find them:

   ```sh
   ssh apps-01
   sudo backrest-restore --check --all
   sudo backrest-restore-offsite --check --all
   ```

   Every `backups_*` Gatus check is green by then.
5. Re-enable ingest (consume folders, download clients, mobile backup).

### D9. Move technitium-secondary, then haos

Not urgent: both keep running on the test hypervisor until then, and nothing in
D1–D8 depends on where they run. Do it once the stacks are back, or days later; only A2
needs it done.

Both are commented out of `libvirt_vms` in `ansible/hosts/host_vars/hypervisor-01/vars.yml`
until their move, so no earlier provisioning run can start a second haos (same MAC as
the one still running) or a technitium-secondary with no disk image. Each move below
uncomments its own entry.

From your machine. Each VM: shut down on the old box, copy its disk image, NVRAM (UEFI
boot entries) and, for technitium-secondary, its disk key, then provision it on
hypervisor-01. The copy goes through your machine, so the two servers need no trust
between them; `tar -S` keeps the images sparse.

**technitium-secondary** (the NUC keeps serving DNS meanwhile):

Uncomment its entry in `ansible/hosts/host_vars/hypervisor-01/vars.yml`, commit and push
(the playbook's safety check wants a clean tree in sync with upstream). Then:

```sh
VM=technitium-secondary
FILES="mnt/vmstore/$VM/disk.qcow2 var/lib/libvirt/qemu/nvram/${VM}_VARS.fd var/lib/vm-keys/$VM/luks.key"
ssh root@hypervisor "virsh shutdown $VM"
until ssh root@hypervisor "virsh domstate $VM" | grep -q 'shut off'; do sleep 5; done
ssh root@hypervisor "virsh autostart --disable $VM"
ssh root@hypervisor "tar -C / -cSf - $FILES" | ssh root@hypervisor-01 "tar -C / -xSpf -"
diff <(ssh root@hypervisor "cd / && sha256sum $FILES") \
     <(ssh root@hypervisor-01 "cd / && sha256sum $FILES") && echo IDENTICAL
just hypervisor-provision-vms hypervisor-01 -e libvirt_vms_only=$VM
```

Check: `dig @192.168.1.3 snyssen.be` answers, and the Technitium cluster page on the NUC
shows the secondary in sync.

**haos** (home automation is down for ~10 minutes):

Uncomment its entry in `ansible/hosts/host_vars/hypervisor-01/vars.yml`, commit and push
(the playbook's safety check wants a clean tree in sync with upstream). Then:

```sh
VM=haos
FILES="mnt/vmstore/$VM/haos.qcow2 var/lib/libvirt/qemu/nvram/${VM}_VARS.fd"
ssh root@hypervisor "virsh shutdown $VM"
until ssh root@hypervisor "virsh domstate $VM" | grep -q 'shut off'; do sleep 5; done
ssh root@hypervisor "virsh autostart --disable $VM"
ssh root@hypervisor "tar -C / -cSf - $FILES" | ssh root@hypervisor-01 "tar -C / -xSpf -"
diff <(ssh root@hypervisor "cd / && sha256sum $FILES") \
     <(ssh root@hypervisor-01 "cd / && sha256sum $FILES") && echo IDENTICAL
```

Move the ZBT-2 USB dongle from the test hypervisor to hypervisor-01, then:

```sh
just hypervisor-provision-vms hypervisor-01 -e libvirt_vms_only=$VM
```

Check: Home Assistant answers at `https://hass.snyssen.be`, and a Zigbee device responds.

**If a move misbehaves**: shut the new copy down
(`just hypervisor-vm-stop <vm> hypervisor-01`), then
`ssh root@hypervisor "virsh autostart <vm>; virsh start <vm>"`. The old files are still
there. To rebuild instead:

- **haos**: delete `/mnt/vmstore/haos/haos.qcow2` on hypervisor-01 and provision again
  (it downloads a fresh HAOS image), then restore the backup downloaded in D1.
- **technitium-secondary**: set `build: true` for it in
  `ansible/hosts/host_vars/hypervisor-01/vars.yml` and follow D5's build steps for it
  (new key → `.sops.yaml` → re-encrypt `nix/hosts/technitium-secondary/data/*`). The
  cluster re-syncs its zones from the NUC.

## A — Afterwards

### A1. The legacy data disks join `bulk` (after about a week)

Once everything has run cleanly for a while and nothing turned out to be missing, the two
KEEP disks become part of `bulk`, which becomes RAID1. **This destroys the last on-disk
copy of the legacy layout**; the backup server keeps the restic one.

1. On hypervisor-01, as root, wipe and prepare the 12 TB disk as `bulk`'s index 1:

   ```sh
   ssh root@hypervisor-01
   legacy-import --unmount
   NEW=/dev/disk/by-id/ata-ST12000NM0538-2K2101_ZHZ12PTZ
   POOL=bulk; I=1
   LABEL="disk-0-before-$POOL-$((I - 1))-luks-$POOL"; NAME="crypt-$POOL-$I"
   echo "$NEW -> $LABEL -> $NAME"               # check twice: this erases the disk
   wipefs -a "$NEW"
   sgdisk --zap-all "$NEW"
   sgdisk --new=1:0:0 --typecode=1:8309 --change-name=1:"$LABEL" "$NEW"
   udevadm settle
   mkdir -p /key && mount -o ro /dev/disk/by-uuid/8B34-7D3C /key   # or 9FBA-884A
   cryptsetup luksFormat --batch-mode "/dev/disk/by-partlabel/$LABEL" /key/hypervisor-01
   cryptsetup luksAddKey --key-file /key/hypervisor-01 "/dev/disk/by-partlabel/$LABEL"
   cryptsetup open --key-file /key/hypervisor-01 "/dev/disk/by-partlabel/$LABEL" "$NAME"
   ```

   `luksAddKey` asks for the fallback passphrase (the one in the password manager).
2. The same for the 8 TB disk as index 2 (the key is still mounted):

   ```sh
   NEW=/dev/disk/by-id/ata-ST8000VN004-3CP101_WWZ3XVDG
   I=2
   LABEL="disk-0-before-$POOL-$((I - 1))-luks-$POOL"; NAME="crypt-$POOL-$I"
   echo "$NEW -> $LABEL -> $NAME"
   wipefs -a "$NEW"
   sgdisk --zap-all "$NEW"
   sgdisk --new=1:0:0 --typecode=1:8309 --change-name=1:"$LABEL" "$NEW"
   udevadm settle
   cryptsetup luksFormat --batch-mode "/dev/disk/by-partlabel/$LABEL" /key/hypervisor-01
   cryptsetup luksAddKey --key-file /key/hypervisor-01 "/dev/disk/by-partlabel/$LABEL"
   cryptsetup open --key-file /key/hypervisor-01 "/dev/disk/by-partlabel/$LABEL" "$NAME"
   umount /key
   ```

3. In `nix/hosts/hypervisor-01/configuration.nix`, `bulk`'s `disks` become (order
   matters: it is the index):

   ```nix
   disks = [
     "/dev/disk/by-id/ata-ST16000NM000J-2TW103_ZR58BLR6"
     "/dev/disk/by-id/ata-ST12000NM0538-2K2101_ZHZ12PTZ"
     "/dev/disk/by-id/ata-ST8000VN004-3CP101_WWZ3XVDG"
   ];
   ```

   Remove `legacyImport.disks` and the warning about the data disks. Commit, push,
   `just nix-remote-install switch hypervisor-01`.
4. Add them and convert, in `screen` (a day or more; services stay up):

   ```sh
   ssh root@hypervisor-01
   btrfs device add /dev/mapper/crypt-bulk-1 /dev/mapper/crypt-bulk-2 /mnt/bulk
   screen -S balance
   btrfs balance start -dconvert=raid1 -mconvert=raid1 /mnt/bulk
   ```

   Follow it with `btrfs balance status /mnt/bulk` from another shell.
5. Prove it survives a reboot: `reboot`, then
   `btrfs filesystem usage /mnt/bulk | grep -E 'Data|Metadata'` shows RAID1, and
   `ls /dev/mapper/` lists `crypt-bulk-0` to `crypt-bulk-2`.

### A2. Retire the test hypervisor

Its disks join `hypervisor-01`: both SSDs into `vmstore`, which becomes RAID1 (1 TB +
1 TB + 500 GB gives ~1.25 TB), and its HDDs into `bulk` if there are bays and SATA ports
for them.

| Disk | by-id | Goes to |
| --- | --- | --- |
| 1 TB Micron NVMe (its boot disk) | `nvme-Micron_2300_NVMe_1024GB__20292942A517` | `vmstore` index 1, if a second M.2 slot is free |
| 500 GB WD SSD | `ata-WDC_WDS500G2B0B-00YS70_204246801987` | `vmstore` index 2 (index 1 without the Micron) |
| 4 TB IronWolf | `ata-ST4000VN008-2DR166_ZDH9AT9F` | `bulk` index 3, optional |
| 2 TB IronWolf | `ata-ST2000VN004-2E4164_Z524CEHK` | `bulk` index 4, optional |
| 2 TB WD Green (the spare) | `ata-WDC_WD20EZRZ-00Z5HB0_WD-WCC4N2RYUKT9` | `bulk` index 5, optional |

> [!WARNING]
> **Wipe them in the test box, before they go anywhere near hypervisor-01** (step 2).
> They carry the very partition labels hypervisor-01 boots from: `boot` and `luks` on
> the Micron, `disk-vmstore-luks-vmstore` on the WD (since P7), `disk-bulk-luks-bulk`
> and `disk-0-before-bulk-0-luks-bulk` on the HDDs. Both boxes share the fallback
> passphrase. Plugged in as they are, hypervisor-01 could mount the test box's `/boot`
> or unlock its pool in place of its own.

1. Nothing must still run on it:

   ```sh
   just hypervisor-vm-list hypervisor    # every VM: shut off
   ssh root@hypervisor poweroff
   ```

2. Wipe all five disks. Boot the test box from the NixOS installer USB, then on its
   console:

   ```sh
   for d in \
     /dev/disk/by-id/nvme-Micron_2300_NVMe_1024GB__20292942A517 \
     /dev/disk/by-id/ata-WDC_WDS500G2B0B-00YS70_204246801987 \
     /dev/disk/by-id/ata-ST4000VN008-2DR166_ZDH9AT9F \
     /dev/disk/by-id/ata-ST2000VN004-2E4164_Z524CEHK \
     /dev/disk/by-id/ata-WDC_WD20EZRZ-00Z5HB0_WD-WCC4N2RYUKT9
   do
     for p in "$d"-part*; do [ -e "$p" ] && wipefs -a "$p"; done
     wipefs -a "$d"
     sgdisk --zap-all "$d"
   done
   lsblk -o NAME,SIZE,MODEL,PARTLABEL       # no partitions left on any of them
   poweroff
   ```

3. Fit them in hypervisor-01. This stops every VM on it for the time it takes, so
   announce it like D-day's downtime:

   ```sh
   ssh root@hypervisor-01 poweroff
   ```

   Fit the WD SSD, the Micron if an M.2 slot is free, and whichever HDDs have a bay and a
   SATA port. Boot, then check that it came up on its own disks and sees the new ones:

   ```sh
   ssh root@hypervisor-01
   findmnt -no SOURCE /boot /mnt/vmstore /mnt/bulk   # /dev/disk/by-partlabel/boot, crypt-vmstore-0, crypt-bulk-0
   virsh list --all                                  # haos, technitium-secondary, apps-01 running
   ls -l /dev/disk/by-id/ | grep -E 'Micron|WDS500G2B0B|ZDH9AT9F|Z524CEHK|WCC4N2RYUKT9'
   ```

4. Prepare each new disk: a GPT partition with the label boot looks for, LUKS with the
   USB keyfile plus the fallback passphrase, opened under the name boot will give it.
   Define the helper once, in the same root shell:

   ```sh
   mkdir -p /key && mount -o ro /dev/disk/by-uuid/8B34-7D3C /key   # or 9FBA-884A
   prep_disk() {  # prep_disk <disk> <pool> <index> [extra cryptsetup open options]
     local new=$1 pool=$2 i=$3; shift 3
     local label="disk-0-before-$pool-$((i - 1))-luks-$pool" name="crypt-$pool-$i"
     echo "$new -> $label -> $name"
     printf 'This erases %s. Type yes: ' "$new"; read -r ok
     [ "$ok" = yes ] || return 1
     wipefs -a "$new"
     sgdisk --zap-all "$new"
     sgdisk --new=1:0:0 --typecode=1:8309 --change-name=1:"$label" "$new"
     udevadm settle
     wipefs -a "/dev/disk/by-partlabel/$label"
     cryptsetup luksFormat --batch-mode "/dev/disk/by-partlabel/$label" /key/hypervisor-01
     cryptsetup luksAddKey --key-file /key/hypervisor-01 "/dev/disk/by-partlabel/$label"
     cryptsetup open --key-file /key/hypervisor-01 "$@" "/dev/disk/by-partlabel/$label" "$name"
   }
   ```

   Then the SSDs, with discards on as for every SSD pool. `luksAddKey` asks for the
   fallback passphrase each time.

   ```sh
   prep_disk /dev/disk/by-id/nvme-Micron_2300_NVMe_1024GB__20292942A517 vmstore 1 --allow-discards
   prep_disk /dev/disk/by-id/ata-WDC_WDS500G2B0B-00YS70_204246801987 vmstore 2 --allow-discards
   ```

   Without the Micron, only the WD, as index 1:
   `prep_disk /dev/disk/by-id/ata-WDC_WDS500G2B0B-00YS70_204246801987 vmstore 1 --allow-discards`.

   Then the HDDs you fitted, in this order, skipping the ones you didn't fit and
   numbering on from 3 without gaps:

   ```sh
   prep_disk /dev/disk/by-id/ata-ST4000VN008-2DR166_ZDH9AT9F bulk 3
   prep_disk /dev/disk/by-id/ata-ST2000VN004-2E4164_Z524CEHK bulk 4
   prep_disk /dev/disk/by-id/ata-WDC_WD20EZRZ-00Z5HB0_WD-WCC4N2RYUKT9 bulk 5
   umount /key
   ls /dev/mapper/                  # the new crypt-vmstore-* and crypt-bulk-* are there
   ```

5. In `nix/hosts/hypervisor-01/configuration.nix`, list them in the same order as their
   indexes (order matters: it is the index):

   ```nix
   bulk = {
     disks = [
       "/dev/disk/by-id/ata-ST16000NM000J-2TW103_ZR58BLR6"
       "/dev/disk/by-id/ata-ST12000NM0538-2K2101_ZHZ12PTZ"
       "/dev/disk/by-id/ata-ST8000VN004-3CP101_WWZ3XVDG"
       "/dev/disk/by-id/ata-ST4000VN008-2DR166_ZDH9AT9F"
       "/dev/disk/by-id/ata-ST2000VN004-2E4164_Z524CEHK"
       "/dev/disk/by-id/ata-WDC_WD20EZRZ-00Z5HB0_WD-WCC4N2RYUKT9"
     ];
     storageMedia = "hdd";
   };
   vmstore = {
     disks = [
       "/dev/disk/by-id/nvme-KINGSTON_SNV3S1000G_50026B7383A64113"
       "/dev/disk/by-id/nvme-Micron_2300_NVMe_1024GB__20292942A517"
       "/dev/disk/by-id/ata-WDC_WDS500G2B0B-00YS70_204246801987"
     ];
     storageMedia = "ssd";
   };
   ```

   Commit, push, `just nix-remote-install switch hypervisor-01`.
6. Add them to the pools and convert, in `screen` (hours for `vmstore`, a day or more
   for `bulk`; services stay up). Name only the mappers you created in step 4:

   ```sh
   ssh root@hypervisor-01
   screen -S balance
   btrfs device add /dev/mapper/crypt-vmstore-1 /dev/mapper/crypt-vmstore-2 /mnt/vmstore
   btrfs balance start -dconvert=raid1 -mconvert=raid1 /mnt/vmstore
   btrfs device add /dev/mapper/crypt-bulk-3 /dev/mapper/crypt-bulk-4 /dev/mapper/crypt-bulk-5 /mnt/bulk
   btrfs balance start /mnt/bulk
   ```

   `vmstore` was single-disk, so it converts to RAID1. `bulk` is already RAID1 since A1,
   so a plain balance only spreads the existing data onto the new disks. Follow either
   with `btrfs balance status /mnt/<pool>` from another shell.
7. Prove it survives a reboot:

   ```sh
   ssh root@hypervisor-01 reboot
   # once it is back:
   ssh root@hypervisor-01 'ls /dev/mapper/; btrfs filesystem usage /mnt/vmstore | grep -E "Data|Metadata"; btrfs filesystem show /mnt/bulk'
   ```

   Every `crypt-*` mapper is there, `vmstore` shows RAID1, and `bulk` lists all its
   devices.
8. Code cleanup, one commit:
   - delete `nix/hosts/hypervisor/`, `ansible/hosts/host_vars/hypervisor/`, its inventory
     entry in `ansible/hosts/prod.yml`, and its key and rule in `.sops.yaml`;
   - delete `nix/hosts/hypervisor-01/legacy-import.nix` and its `scripts/`,
     `nix/hosts/apps-01/prod-import.nix` and `prod-layout.nix`, and their imports;
   - remove the legacy box's Syncthing device (`sync.snyssen.be`) from
     `nix/data/syncthing.nix` and from every folder in `nix/hosts/apps-01/syncthing.nix`;
   - set `restoreHold` back to `false` for both (the module stays, for the DR runbook);
   - drop the Phase A repository's password, which nothing reads any more:
     `sops unset nix/hosts/apps-01/data/common.yaml '["backrest"]["repos"]["apps"]'`.
9. Destroy the Phase A test repository on the backup server
   (`rest:http://backup.snyssen.be:8000/apps/`), once D8 has produced good snapshots.

### A3. Last steps

- [ ] Enable Photon (`nix/hosts/apps-01/compose/dawarich/default.nix`,
      `photon.enable = true`) once `vmstore` has room: prod's worldwide index is ~200 GB
      and grows 10–20 GB a year, and its `PARALLEL` update strategy needs twice that while
      swapping. Grow apps-01's disk first (`disk_gb`), or pick a smaller `REGION` and/or
      `UPDATE_STRATEGY`.
- [ ] Keep production's final snapshots **indefinitely**: they are the only pre-cutover
      state that exists.
- [ ] Update `apps-migration-plan.md` to mark Phase B complete.

## Per-stack restore notes

Things that are not obvious from the group table, and that cost time if discovered on
the day.

**UniFi — a `.unf` restore, not an import.** A `.unf` holds the whole controller: sites,
devices and their keys, settings, admins. MongoDB on apps-01 starts empty, with its own
passwords, and the controller's setup wizard restores the backup into it. The devices
don't need re-adopting: they know the controller by its Inform Host, which is why that
must be a name. Until they reconnect they keep working; only management is down.

The same goes for a disaster recovery later: `backrest-restore unifi` brings back the
controller's autobackups (`/var/lib/app-data/unifi/config/data/backup/autobackup`). Copy
the newest `.unf` off the host and upload it in the wizard. How often the controller
writes them is its own setting (Settings → System → Backups), which comes back with the
restore. Prod's is monthly; daily costs a few MB and loses less.

**Nextcloud — the strictest pairing.** Its database indexes its file tree; neither half
is usable without the other. Started against an empty `/mnt/bulk/nextcloud`, the
entrypoint runs its first-run installer and writes a config and schema of its own,
which a later `postgres-restore nextcloud` then half-replaces. The hold keeps it down
until both `legacy-import nextcloud` and `postgres-restore … nextcloud` are done.

Its `extra.config.php` is what makes the imported `config.php` work at all: Nextcloud
reads `*.config.php` after `config.php`, so the restored file keeps pointing at
production's database password, domain and Redis host, and the generated one overrides
all three. `passwordsalt`, `secret` and `instanceid` must be production's values —
`secret` keys every encrypted field, and `instanceid` names the `appdata_<id>`
directory inside the restored tree.

**Immich — database and photos together.** Restoring the database without
`legacy-import photos` leaves a library whose every asset is missing. Its dumps are in
production's `postgres` location but belong to its own PostgreSQL, which is why they
get a separate group and a separate staging path.

**Paperless — mind the export timer.** The nightly export runs
`document_exporter --delete`, so it mirrors the library. Run against a database that
has not been restored yet, it finds no documents and clears the export directory. The
hold keeps the timer off until the stacks are released. Nothing is lost permanently
either way: the export is regenerable.

**Streaming — expect stale configuration.** The `*arr` applications and Jellyfin store
absolute paths and hostnames in their configs. After an import they point at
production's layout. Budget time for fixing root folders and indexers rather than
assuming the import is the end of it.

**Team wiki — database only.** `postgres-restore --from /mnt/bulk/restore/prod-postgres
team_wiki`. Its site URL and OIDC endpoints live in the database and name production's
domain, which is right again on apps-01. Keep the OIDC strategy as imported: its id is
part of the redirect URI registered with Authelia.

**Rallly — database only.** Its base URL and OIDC endpoints come from the environment, so
they follow `domains.team` without editing anything in the app.

**Speedtest Tracker — database only.** Its `APP_KEY` is prod's, so whatever the database
holds encrypted with it stays readable.

**Sharkey — first run is the cutover.** It was never started during Phase A: its `url`
is the instance's identity on the fediverse, so it only ever runs under
`social.snyssen.be`. Its data comes from both tools: `prod-import sharkey` (Redis, which
carries the job queue, so deliveries pending at the freeze go out from the new host) and
`legacy-import sharkey-files` (the drive's files), then
`postgres-restore … sharkey`. The hold keeps it down until all three are done.

**Dawarich — database, then the geocoder.** `postgres-restore --from
/mnt/bulk/restore/prod-dawarich dawarich` goes to its own PostGIS. Points imported from
prod are already geocoded and keep their data. Reverse geocoding of new points needs
Photon, which stays off until vmstore has room (A3). While it is off, the imported
database may still name `photon:2322`, so lookups go to a host that doesn't exist. In
1.17.0 a lookup that errors is retried three times and then dropped, leaving the point to
catch up once Photon is on. `legacy-import dawarich-storage` brings the original import
files, which prod backed up nowhere.

**Matrix — database collation first.** Synapse refuses a database whose collation isn't
`C`, and a restore can't change it: it comes from `CREATE DATABASE`. The databases stack
creates `matrix` that way (`cLocaleDbNames`) when it doesn't exist yet, which on a fresh
apps-01 it doesn't. If its provisioning logs `WARNING: database matrix has
collation/ctype ...`, drop the database (pgAdmin, or `DROP DATABASE matrix;` as the
superuser), restart `compose-databases` and restore again. apps-01 runs Matrix `live`:
federation, push and the bridges are on, which is only safe because the legacy Synapse
and bridges are gone for good. maubot is not carried over.

**Syncthing — synced, not imported.** apps-01 is the Phase A VM's device renamed (same
ID, from `nix/hosts/apps-01/data/syncthing.yaml`), and fills its folders from its peers.
The Nix hosts learn the new name and address from `nix/data/syncthing.nix` on their next
rebuild; the Pixel needs the address `tcp://apps-01:22000` by hand.

**`monitoring` — Uptime Kuma is not migrated.** Gatus replaces it, with every check
declared in `compose/monitoring/gatus-config.nix`. Grafana's "Uptime Kuma" dashboard has
to be replaced by its Gatus version, along with any alert rules written against Kuma's
`monitor_*` metrics.

## Open questions

- ~~How the media disks move into the hypervisor pool~~ — resolved: they don't move.
  They are in the legacy box already; `legacy-import` copies their data at disk speed,
  and they join `bulk` once it is verified (A1).
- ~~How long production's hardware stays untouched~~ — resolved: the data disks stay
  untouched until A1, whatever the timing. Only the boot SSD and the parity disk are
  wiped on D-day.
- ~~DNS cutover sequencing~~ — resolved: Technitium is live (#170). apps-01 takes the
  legacy box's LAN address and tailnet address, so the records don't change.
- ~~Whether `attic` moves before or after~~ — resolved: retired, replaced by Garage.
- **Known risk, accepted: databases kept as plain files were copied live** by prod's
  autorestic (Actual's SQLite, FoundryVTT's LevelDB worlds). These come through
  `prod-import`, as tested in Phase A. Backrest's hooks can stop or dump them first; that
  is post-cutover work.
- **Rehearsal** — partial. P5 rehearses growing a pool, P6 the disk copy, P7 shrinking
  one, and Phase A rehearsed every `prod-import` group and database restore. Not
  rehearsed: the D-day sequence end to end on the real hardware.
