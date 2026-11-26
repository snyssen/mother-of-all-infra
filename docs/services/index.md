# Services

Production's apps run on `apps-01`, a NixOS VM on hypervisor-01. Each app is a Docker Compose
stack in `nix/hosts/apps-01/compose/<stack>/`: a `default.nix` (secrets, directories, Traefik
routes, systemd wiring) plus a `docker-compose.yaml`, realised as a `compose-<stack>.service`
unit. Why a stack is set up the way it is lives in comments next to the code, not here.

Every hostname below is under `${config.domains.main}` unless it says
`${config.domains.team}`, and is routed by Traefik (the `reverse-proxy` stack). App data is
backed up by Backrest; see [Backups](../operations/backups.md).

| Stack | What it is | Exposed at | Code |
| --- | --- | --- | --- |
| actual-budget | Actual, personal budgeting | `actual.` | `nix/hosts/apps-01/compose/actual-budget/` |
| auth | Authelia (SSO, forward auth, OIDC) and LLDAP | `auth.`, `auth.${config.domains.team}`, `ldap.` | `nix/hosts/apps-01/compose/auth/` |
| bentopdf | BentoPDF, PDF tools in the browser | `pdf.` | `nix/hosts/apps-01/compose/bentopdf/` |
| crowdsec | CrowdSec LAPI and a web UI | `crowdsec.` (LAPI, tailnet only), `crowdsec-ui.` | `nix/hosts/apps-01/compose/crowdsec/` |
| dashboard | webb-launcher start page | `dash.` | `nix/hosts/apps-01/compose/dashboard/` |
| databases | Shared PostgreSQL, pgAdmin, scheduled dumps | `pgadmin.` | `nix/hosts/apps-01/compose/databases/` |
| dawarich | Dawarich location history, with a Photon geocoder | `location.` | `nix/hosts/apps-01/compose/dawarich/` |
| foundryvtt | Foundry Virtual Tabletop | `dnd.` | `nix/hosts/apps-01/compose/foundryvtt/` |
| garage | Garage S3 object storage and its web UI; serves the `cache` bucket | `s3.`, `cache.`, `garage.` (LAN and tailnet only) | `nix/hosts/apps-01/compose/garage/` |
| immich | Immich photo library | `photos.` | `nix/hosts/apps-01/compose/immich/` |
| matrix | Synapse, Matrix Authentication Service, Element, mautrix bridges (Discord, Meta, Signal, WhatsApp) | `matrix.`, `matrix-mas.`, `element.` | `nix/hosts/apps-01/compose/matrix/` |
| minecraft | Two Minecraft servers behind mc-router, with Dynmap live maps | TCP `:25565`; maps at `mc.`, `mc-usw.` | `nix/hosts/apps-01/compose/minecraft/` |
| monitoring | Prometheus, Alertmanager, Loki, Grafana, Gatus, Umami | `monitor.`, `uptime.`, `prometheus.`, `umami.`, `loki.` (tailnet only) | `nix/hosts/apps-01/compose/monitoring/` |
| nextcloud | Nextcloud | `cloud.` | `nix/hosts/apps-01/compose/nextcloud/` |
| ntfy | ntfy push notifications | `ntfy.` | `nix/hosts/apps-01/compose/ntfy/` |
| paperless | Paperless-ngx, with Tika and Gotenberg | `paperless.` | `nix/hosts/apps-01/compose/paperless/` |
| personal-website | Personal website | `${config.domains.main}` (apex) | `nix/hosts/apps-01/compose/personal-website/` |
| rallly | Rallly scheduling polls | `events.${config.domains.team}` | `nix/hosts/apps-01/compose/rallly/` |
| recipes | Tandoor recipe manager | `recipes.` | `nix/hosts/apps-01/compose/recipes/` |
| reverse-proxy | Traefik: every HTTP route plus the game and UniFi ports; also routes argunix | `routing.` (dashboard), `argunix.` | `nix/hosts/apps-01/compose/reverse-proxy/` |
| sharkey | Sharkey fediverse server, with DeepLX translation | `social.` | `nix/hosts/apps-01/compose/sharkey/` |
| skyrim-together | Skyrim Together Reborn game server | UDP `:10578` | `nix/hosts/apps-01/compose/skyrim-together/` |
| speedtest | LibreSpeed speed test | `speedtest.` | `nix/hosts/apps-01/compose/speedtest/` |
| speedtest-tracker | Speedtest Tracker, scheduled internet speed tests | `speedtest-tracker.` | `nix/hosts/apps-01/compose/speedtest-tracker/` |
| streaming | Jellyfin, PeerTube, Audiobookshelf, the *arr apps, SABnzbd, Transmission behind Gluetun, Pinchflat, AudioMuse, Lidify, LidaTube | `streaming.`, `peertube.`, `audiobooks.`, `yt.`, `sonarr.`, `radarr.`, … | `nix/hosts/apps-01/compose/streaming/` |
| team-wiki | Wiki.js | `${config.domains.team}` (apex) | `nix/hosts/apps-01/compose/team-wiki/` |
| unifi | UniFi Network Application, with MongoDB | `unifi.`, `unifi-guest.` (LAN and tailnet only) | `nix/hosts/apps-01/compose/unifi/` |
| Backrest | restic backups with a web UI (native NixOS service) | `backrest.` | `nix/hosts/apps-01/backrest.nix` |
| Syncthing | File sync (native NixOS service) | `sync.` (GUI); sync ports directly, not through Traefik | `nix/hosts/apps-01/syncthing.nix` |

> [!NOTE]
> "Exposed at" lists the Traefik host rules only. Whether a route also requires an Authelia
> login, and whether it is reachable from the internet through the ingress host, is decided
> per route in the stack's `default.nix` and in `auth/authelia-configuration.nix`.

## Dedicated pages

- [Monitoring](monitoring.md)
- [Scanner to Paperless](scanner-to-paperless.md)
