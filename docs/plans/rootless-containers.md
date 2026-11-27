# Rootless containers — plan

Status: **Inventory confirmed at runtime 2026-11-27, nothing changed yet.** Tracks issue
[#322](https://github.com/snyssen/mother-of-all-infra/issues/322).

## Goal

Get apps-01's containers ready to run under a runtime that does not give them real root:
rootless Docker, rootless Podman, or Docker with `userns-remap`. The issue's own scope is
the first step: **no container should run as root unless it truly needs to.**

The work splits in two, and only the first is decided:

1. **Phase 1: drop root inside the containers**, still under today's rootful Docker. Each
   stack changes on its own, can be rolled back on its own, and helps whatever runtime
   comes next. Most of the work is here.
2. **Phase 2: change the runtime.** That changes the whole host at once and has its own
   blockers (see [Runtime blockers](#runtime-blockers)). Decide it once Phase 1 is done.

## Inventory

From the [runtime check](#confirm-at-runtime) on apps-01, 2026-11-27: every process in
every running container, by uid. skyrim-together was not running at the time; its image
starts as root. Nothing mounts the Docker socket, and nothing runs `privileged` or with
`network_mode: host`.

### A. No root process (43)

Nothing to fix for root, but many share a uid, across stacks too. The
[uid policy](#uid-policy) gives each its own.

| uid | Containers |
|---|---|
| **1000 (= `snyssen` on the host)** | foundryvtt, minecraft, mc-usw, team-wiki, crowdsec-web-ui |
| 999 | 8 × redis (auth, dawarich, immich, nextcloud, paperless, sharkey, audiomuse, peertube), postgres (databases), database (immich), peertube, unifi-db |
| 33 | jellyfin, audiobookshelf, pinchflat (compose `user: 33:100`), lidatube, lidify |
| 1337 | 4 × mautrix bridges |
| 991 | synapse, sharkey |
| 1001 | umami, gotenberg |
| 101 | bentopdf, element |
| 100 | rallly, sharkey_deeplx |
| 65532 | matrix_mas, mc-router |
| 65534 | prometheus, alertmanager |
| one each | dawarich_db (70), grafana (472), loki (10001), tika (35002), photon (9011) |

### B. Root supervisor, app non-root (14)

The app itself already runs unprivileged; an init or master process stays root.

| Stack | Container | Root part | App as | First idea |
|---|---|---|---|---|
| auth | lldap | `tini` | 1000 | `lldap/lldap:*-rootless` image variant |
| databases | pgadmin | postfix `master` | 5050 | postfix is only for mail; check if it can be dropped |
| nextcloud | nextcloud | `apache2` master | 33 (also Collabora) | `user: 33` is supported by the image when the data dir is already owned |
| speedtest | speedtest | `apache2` master | 33 | same as nextcloud |
| paperless | paperless | s6 | 33 | s6 needs root; check upstream non-root support |
| streaming | bazarr, lidarr, prowlarr, radarr, sonarr, torrent, usenet | s6 | 33 | linuxserver.io: check per image whether `user:` (non-root mode) is supported |
| speedtest-tracker | speedtest-tracker | s6, nginx/php-fpm masters | 1000 | same as other linuxserver.io images |
| unifi | unifi-network-application | s6 | 1000 | same; frozen at 10.6.109, so low priority |

### C. App runs as root (19): what Phase 1 has to fix

| Stack | Container | First idea |
|---|---|---|
| actual-budget | actual-budget | `user:`; data dir is `root 0700` today |
| auth | authelia | `user:`; supported upstream |
| crowdsec | crowdsec | reads host logs; needs read access to those files under a non-root uid |
| dashboard | dashboard | own image (`snyssen/webb-launcher`): set `USER` upstream |
| personal-website | personal-website | own image: set `USER` upstream |
| databases, dawarich, immich | postgres_backups, dawarich_backups, backup | `go-cron` as root; check `user:` support in `prodrigestivill/postgres-backup-local` |
| dawarich | dawarich_app | to investigate |
| garage | garage, garage-ui | `user:`; meta dir is `root 0700` today |
| immich | immich-server, immich-machine-learning | upstream documents `user:`; photos are on `/mnt/bulk` |
| monitoring | gatus | `user:`; data dir `root 0700` today |
| ntfy | ntfy | `user:`; cache/auth dirs root today |
| recipes | recipes | gunicorn runs as root (only nginx workers drop to 100); to investigate |
| reverse-proxy | traefik | `user:`; Docker already allows binding ports below 1024 inside a container (`ip_unprivileged_port_start=0`); certs dir `root 0700` |
| streaming | audiomuse_web, audiomuse_worker | supervisord as root; to investigate |
| skyrim-together | skyrim-together | not running during the check; to investigate |

### D. Needs extra privileges

| Stack | Container | Needs | Notes |
|---|---|---|---|
| streaming | vpn (gluetun) | root, `NET_ADMIN`, `/dev/net/tun` | Must keep root *in its own netns*; works under rootless/userns runtimes. 7 containers share its network |
| streaming | jellyfin | `/dev/dri` | Non-root already; needs the `render`/`video` group on the host device |

## Confirm at runtime

How the inventory was made, and how to re-check progress after each stack. Read-only, on
apps-01:

```sh
ssh root@apps-01 'for c in $(docker ps --format "{{.Names}}" | sort); do
  printf "%-32s cfg=%-12s " "$c" "$(docker inspect -f "{{.Config.User}}" "$c")"
  docker top "$c" -eo pid,uid,comm | tail -n +2 | awk "{print \$2\":\"\$3}" | sort -u | tr "\n" " "
  echo
done'
```

A process with uid `0` puts its container in table B (if the app process itself is
non-root), C or D.

## Phase 1 — non-root under rootful Docker

Per stack, in its own commit:

1. Give the container its own uid/gid (see [uid policy](#uid-policy)).
2. Change the stack's `systemd.tmpfiles` rule to that owner. tmpfiles `d` does not chown an
   existing tree, so the first deploy needs a one-off `chown -R` (or a `Z` rule).
3. Set `user:` (or the image's PUID-style variables) in `docker-compose.yaml`.
4. Check mounted SOPS secrets: today most are `0400` root-owned, so they must get an
   `owner` that matches the container's uid.
5. Build (`just nix-build apps-01`), deploy, check the service and its Gatus check.

### uid policy

**One uid per container that owns data**, sidecars included (an app's redis or postgres
gets its own). Inside a container the uid hardly matters, since each container only sees
its own mounts. It matters after a container escape, where the host uid is what the kernel
checks, and later under `userns-remap`, where every container shares one host range and
only distinct uids keep them apart.

- **Never 0 or 1000.** uid 1000 is `snyssen`, who is in `wheel`; an escape as 1000 lands in
  the maintainer's home. crowdsec-web-ui, unifi, speedtest-tracker, foundryvtt and minecraft
  run as 1000 today and move off it.
- **Avoid NixOS's auto-allocated system range (400–999).** The images' own 999 (postgres,
  redis, mongo) can collide with a host system user. Also avoid ids the images share by
  default: 65534 (`nobody`: prometheus and alertmanager), 65532 (MAS and mc-router).
- **Declare them as NixOS users and groups** with pinned uids in a reserved range (for
  example 2000–2999), one per app. `ls` and `ps` on the host then show names, nothing else
  can be given those ids, and SOPS secrets use `owner = "<app>"` instead of raw numbers.
- **Shared data goes through a group, not a shared uid.** `/mnt/bulk/streaming/media` is
  written by the *arr apps and read by jellyfin, audiobookshelf and nextcloud. Give it a
  dedicated `media` group (setgid directories, umask 002) instead of today's `33:100`.
  gid 100 is `users`, the maintainer's primary group. The NFS export carries numeric ids, so
  re-owning it is a one-off `chown` on hypervisor-01.
- Some images need their uid to exist in `/etc/passwd` or need a writable `HOME`. Set
  `HOME` in the compose file, or keep the image's user for those and note why.

Suggested order: own images (dashboard, personal-website) and the simple ones with local
data (ntfy, gatus, garage, actual-budget, authelia, lldap); then the redis/postgres
sidecars; then the `/mnt/bulk` users (immich, nextcloud, streaming); then the linuxserver
images; traefik and crowdsec last, as everything depends on them.

## Runtime blockers

To settle before Phase 2, whichever runtime is chosen:

- **Client IP at Traefik.** Rootless Docker's default port forwarding (rootlesskit's
  `builtin` driver) replaces the client's address with its own. CrowdSec, the access logs
  and Authelia's rate limits depend on the real one. Needs `slirp4netns` or `pasta` port
  handling, or a userns-remap/rootful-Podman design that keeps host networking.
- **`/mnt/bulk` over NFS.** A user namespace shifts uids (container 33 → host 100032 or
  similar), so files would be created with new owners on hypervisor-01, and existing ones
  would appear as `nobody`. Either keep the shift identity for these uids, or re-own the
  share.
- **Host-native services.** The firewall trust rule for `172.16.0.0/12` in
  `nix/modules/nixos/docker.nix` and the `host.docker.internal` routes (argunix, cAdvisor,
  node-exporter) assume rootful bridges. Rootless networking reaches the host differently.
- **cAdvisor** is configured with rootful Docker's containerd socket path.
- **Journald logging** (Alloy reads the journal) and the `compose-<stack>.service` units in
  `nix/modules/nixos/compose-stacks.nix` assume the system daemon.
- **Secrets ownership** in SOPS templates is set with host uids, which would need mapping.

Options for Phase 2:

| Option | What changes | Main cost |
|---|---|---|
| Docker `userns-remap` | Daemon stays root; container root maps to an unprivileged range | NFS uid shift; one setting for the whole daemon |
| Rootless Docker | Daemon runs as a user | Client IP, networking to the host, all units move to user services |
| Podman (rootful or rootless) | New runtime, `podman compose` or Quadlet | Rewrite of `compose-stacks.nix`; rootless shares the Docker blockers |

## Open questions

- Is the target rootless *runtime*, or is "no container runs as root" (Phase 1) enough on
  its own for now?
- For `/mnt/bulk`: keep 33:100 as the shared media owner, or one uid per app?
- Does every image in table C actually work non-root? Each "to investigate" needs a test.
