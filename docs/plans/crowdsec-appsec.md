# CrowdSec AppSec on ingress — plan

Status: **Phase 1 running since 2026-11-27 13:50** (observe only; Phase 0 and the
ingress resize to V-R2 done the same day). The first AppSec checks only got through once
apps-01 could issue the `appsec.snyssen.be` certificate: its Dynu API key had been
disabled, and re-enabling it fixed ACME.

## Goal and decisions already made

Put CrowdSec's AppSec (the WAF: CVE virtual patches plus generic rules) in front of every
**public** route, at **ingress**, and not on apps-01.

- **Ingress, not apps-01.** Ingress terminates TLS, so its Traefik sees decrypted HTTP and
  the real client address (no `X-Forwarded-For` trust to get right). Its routers are
  exactly the public surface. LAN and tailnet clients reach apps-01 directly, so an
  AppSec failure can take the public site down but can never lock the maintainer out of
  Authelia, Grafana or anything else needed to fix it.
- **The engine stays on apps-01 ("option A").** Ingress is 1 vCPU / ~950 MiB, no swap. A
  second CrowdSec there costs 100 MB+ and runs the rules locally. Instead, ingress's
  Traefik runs only the bouncer plugin, and asks apps-01's AppSec engine over the
  tailnet. The cost moves to latency: one extra ingress → apps-01 round trip per request.
- **Plugin in `appsec` mode.** It then does AppSec checks only, no per-request decision
  lookups: ingress's `crowdsec-firewall-bouncer` already enforces bans at L3.
- **Observe before blocking.** A dedicated AppSec listener for ingress starts in
  allow-only mode, with the AppSec scenarios simulated, so nothing is blocked or banned
  until the data says it is safe.
- **apps-01's own `crowdsec-waf`** (on `crowdsec` and `crowdsec-ui`, listener 7422) was
  removed on 2026-11-27, once Phase 1 was running: neither route is public, and it put
  the remote firewall bouncers' LAPI polling behind a fail-closed AppSec check.

## Phase 0 — baseline (now, at least 14 days)

### Prerequisites

- [x] ingress's Traefik metrics deployed (`traefik.metrics` + `grafana-alloy.traefikMetrics`):
      `traefik_router_requests_total{instance="ingress"}` returns data.
- [x] Loki on Traefik's network deployed on apps-01, so ingress's logs (including
      `/var/log/traefik/access.log` via `varlogs`) reach Loki:
      `{host="ingress"}` returns data.
- [x] Measure the tailnet path ingress → apps-01 once, on ingress:
      `tailscale ping --until-direct=false -c 20 apps-01` (without `--until-direct=false`
      it stops at the first direct pong; `-c` is only an upper bound). Record the median
      RTT and whether it says `via DERP(...)` or a direct `via <ip>:<port>`. **A DERP-relayed path is a blocker:**
      every public request would pay a relayed round trip. Fix the direct path first.
      2026-11-27: direct over IPv6 on all 20 pings, median 15 ms (15–16 ms).

### What to record

Run each in Grafana → Explore (datasource `Prometheus`), over the whole baseline window.
Write the numbers into the table at the end of this section — Phase 2 compares
against them.

| # | What | Query | Why |
|---|---|---|---|
| B1 | CPU busy, avg / p99 / max | `1 - avg(rate(node_cpu_seconds_total{instance="ingress",mode="idle"}[5m]))` (use `quantile_over_time`/`max_over_time` over `[14d:5m]` for p99/max) | Headroom for the plugin |
| B2 | Lowest available memory | `min_over_time(node_memory_MemAvailable_bytes{instance="ingress"}[14d])` | Body buffering is the OOM risk (no swap) |
| B3 | Traefik's own memory | `max_over_time(process_resident_memory_bytes{job="traefik",instance="ingress"}[14d])` | The plugin loads into this process |
| B4 | Request rate per router, avg and peak | `sum by (router) (rate(traefik_router_requests_total{instance="ingress"}[5m]))`; peak: `max_over_time(sum(rate(traefik_entrypoint_requests_total{instance="ingress",entrypoint="websecure"}[5m]))[14d:5m])` | Load AppSec will see; which routes dominate |
| B5 | Uploads per router | `sum by (router) (rate(traefik_router_requests_total{instance="ingress",method=~"POST\|PUT\|PATCH"}[5m]))` and `sum by (router) (rate(traefik_router_requests_bytes_total{instance="ingress"}[5m]))` | Which routes send bodies, and how much |
| B6 | Concurrent connections, peak | `max_over_time(sum(traefik_open_connections{instance="ingress",entrypoint="websecure"})[14d:1m])` | Upper bound on bodies buffered at once. Check the metric name in Explore first; Traefik has renamed it before |
| B7 | Latency p95 per router | `histogram_quantile(0.95, sum by (le, router) (rate(traefik_router_request_duration_seconds_bucket{instance="ingress"}[1h])))` | The before picture for the latency AppSec adds |
| B8 | Tailnet RTT | from the prerequisite above | Expected added latency per request ≈ this RTT + ~4 ms |

| | B1 avg / p99 / max | B2 | B3 | B4 avg / peak | B6 | B8 |
|---|---|---|---|---|---|---|
| Baseline | 11 % / 28 % / 91 % | 131 MiB (of 948) | 144 MiB | 1.44 / 11.2 req/s | 517 | 15 ms, direct |
| Phase 2 | | | | | | |

Baseline taken 2026-11-27 over 13 days (2026-11-14 → 11-27), not 14; about 6 h of data
are missing around 2026-11-23. Notes:

- **B2 fails the go/no-go** (< 300 MiB). The typical daily low is 390–450 MiB; the two
  lows (2026-11-15 19:10 and 11-20 18:05 UTC, each a single 5-minute sample) have no
  visible cause in ingress's journal. Decision: resize ingress to V-R2 (2 GiB) first.
- **B4/B5:** `matrix` (0.66 req/s, 46 %) and `social` (0.47 req/s, 33 %) are nearly all
  the traffic, and nearly all the bodies: POST/PUT 0.63/s on `matrix` (federation) and
  0.34/s on `social` (ActivityPub inbox, ~2.7 KiB each). Every other router is under
  0.01 req/s. Request bodies over the window: `social` 1.0 GiB, `immich` 274 MiB,
  `matrix` 155 MiB.
- **B7 is not usable as recorded.** Traefik's default histogram buckets (0.1, 0.3, 1.2,
  5 s) cannot show a ~20 ms change; finer buckets are needed before a latency baseline
  means anything. `matrix`'s p95 is ≥ 5 s because of client `/sync` long-polls.

Decided 2026-11-27: resize to V-R2 and add finer buckets (`metrics.prometheus.buckets` in
`nix/modules/nixos/traefik.nix`), then go straight to Phase 1 **without a second
baseline** — getting the WAF in front of the public routes outweighs clean before/after
numbers. Consequences:

- B2 after the resize is only seen in Phase 2, with the plugin already loaded. Watch it
  closely the first days.
- B7 has no real "before". The fine-bucket data from between the bucket deploy and the
  Phase 1 deploy is all there is (so leave a few hours between them if convenient). In
  Phase 2, the exempted federation routes, which never go through AppSec, give a rough
  comparison for the covered ones.

### Decisions the baseline feeds

- **Body limit.** Start at 1 MiB (`crowdsecAppsecBodyLimit: 1048576`). Worst case buffered
  ≈ B6 × 1 MiB; keep that well under B2 − 150 MiB. If B6 is in the hundreds, lower it.
- **Which routes to exempt.** Any router whose B4 is dominated by many small requests
  (Jellyfin segments, dynmap tiles) is a candidate: multiply its request count by B8 to
  see the latency it would add. Decide per route in Phase 1, not up front.
- **Go/no-go for Phase 1.** Proceed only if B8 is a direct path and ingress has
  comfortable headroom (B1 p99 < 50 %, B2 > 300 MiB).

## Phase 1 — install in observe mode

### apps-01: the CrowdSec stack (`nix/hosts/apps-01/compose/crowdsec/`)

1. **Bouncer key for ingress.** In `default.nix`, add
   `compose-stacks/crowdsec/ingress_waf_bouncer/api_key` (sops, `../../data/crowdsec.yaml`)
   and register it like the others in `compose-crowdsec.env`:
   `BOUNCER_KEY_ingress_waf=${config.sops.placeholder."compose-stacks/crowdsec/ingress_waf_bouncer/api_key"}`.
   Generate it with `just sops-gen-secret` (see `--help`). Add the variable to the
   `crowdsec` service's `environment` list in `docker-compose.yaml`.
2. **A separate AppSec listener for ingress**, so its mode can change without touching
   the one apps-01's `crowdsec-waf` uses. New `crowdsec/acquis.d/appsec-ingress.yaml`:

   ```yaml
   # Ingress's AppSec listener. Observe-only while the trial runs: the last config
   # listed decides default_remediation, and `allow` means a matching rule is logged
   # but the request goes through.
   source: appsec
   listen_addr: 0.0.0.0:7423
   appsec_configs:
     - crowdsecurity/appsec-default
     - snyssen/appsec-observe
   labels:
     type: appsec
   ```

   and `crowdsec/appsec-configs/appsec-observe.yaml`, mounted read-only at
   `/etc/crowdsec/appsec-configs/appsec-observe.yaml`:

   ```yaml
   name: snyssen/appsec-observe
   default_remediation: allow
   ```

   Check after deploy that CrowdSec's log shows the listener on 7423 loading the same
   rules as 7422 ("Loaded 207 inband rules"). If combining configs does not behave as
   documented, the fallback is a full copy of `appsec-default` with
   `default_remediation: allow`.
3. **No bans from AppSec during the trial.** In-band matches can still produce alerts
   that the AppSec scenarios turn into bans. Mount `crowdsec/simulation.yaml` at
   `/etc/crowdsec/simulation.yaml`:

   ```yaml
   simulation: off
   exclusions:
     - crowdsecurity/appsec-vpatch
     - crowdsecurity/appsec-native
     - crowdsecurity/appsec-generic-test
   ```

   This is global: during the trial, AppSec matches on apps-01's own two CrowdSec
   routes are still blocked in-band but no longer lead to bans. Acceptable for a few
   weeks; it ends in Phase 3.
4. **Never ban ingress itself.** Already covered: `crowdsec/self-whitelist.yaml`
   whitelists the whole tailnet (`100.64.0.0/10`), ingress's `100.120.249.84` included.
   Every AppSec call from ingress reaches apps-01's
   Traefik from that address, at the full public request rate, which is exactly what
   `http-crawl-non_statics` bans. Public visitors are unaffected: apps-01 trusts
   ingress's forwarded headers, so they are logged and banned under their own address.

### apps-01: a route to the new listener (`compose/crowdsec/default.nix`)

Added to `reverseProxy.dynamicConfig.crowdsec`:

```yaml
http:
  routers:
    crowdsec-appsec-ingress:
      rule: "Host(`appsec.${config.domains.main}`)"
      entryPoints:
        - websecure
      service: crowdsec-appsec-ingress
      middlewares:
        - ingress-only
      tls:
        certResolver: le_main
      # One log line per public request otherwise; the WAF calls are not traffic.
      observability:
        accessLogs: false
  services:
    crowdsec-appsec-ingress:
      loadBalancer:
        servers:
          - url: "http://crowdsec:7423"
  middlewares:
    ingress-only:
      ipAllowList:
        sourceRange:
          - "100.120.249.84/32"
```

- **Not** `crowdsec-waf` on this router — that would loop.
- Requests also need a valid bouncer key, so the allowlist is defence in depth.
- Check: Traefik's version on apps-01 supports per-router `observability` (v3.1+). If
  not, drop that block; the whitelist in step 4 above is what actually matters.
- Check: from ingress, `getent hosts appsec.snyssen.be` must resolve to apps-01
  (`100.114.242.89`). Ingress resolves its backends through split-horizon or tailnet DNS
  (see the comment on `proxiedWebServices`); public DNS would point at ingress itself.

### ingress (`nix/hosts/ingress/`, `nix/modules/nixos/traefik.nix`)

1. **Secret.** The same key value as step 1, in `nix/hosts/ingress/data/secrets.yaml` as
   `crowdsec/appsec_key`, owner `traefik`, mode `0400`. Copy it across without printing
   it, e.g. `sops decrypt --extract '["compose-stacks"]["crowdsec"]["ingress_waf_bouncer"]["api_key"]' nix/hosts/apps-01/data/crowdsec.yaml | just sops-set-stdin nix/hosts/ingress/data/secrets.yaml crowdsec/appsec_key`.
2. **Plugin source, pinned and offline** — same reasoning as apps-01 (see the
   `localPlugins` comment in `compose/reverse-proxy/docker-compose.yaml`: a failed
   download at startup disables every plugin for the life of the process). Traefik's
   working directory on ingress is `/var/lib/traefik`, so:

   ```nix
   systemd.tmpfiles.rules = [
     "L+ /var/lib/traefik/plugins-local/src/github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin - - - - ${inputs.crowdsec-bouncer-traefik-plugin}"
   ];
   services.traefik.staticConfigOptions.experimental.localPlugins.crowdsec-bouncer.moduleName =
     "github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin";
   ```

   Check: that Traefik follows the symlink into the store (it should — Yaegi only reads).
   If it doesn't, copy the source with `C+` instead of linking it.
3. **Middleware**, in `traefik-configuration.nix`:

   ```nix
   http.middlewares.crowdsec-waf.plugin.crowdsec-bouncer = {
     enabled = true;
     crowdsecMode = "appsec";
     crowdsecAppsecEnabled = true;
     crowdsecAppsecScheme = "https";
     crowdsecAppsecHost = "appsec.snyssen.be";
     crowdsecAppsecPath = "/";
     # Given as a file so it stays out of the store.
     crowdsecAppsecKeyFile = config.sops.secrets."crowdsec/appsec_key".path;
     crowdsecAppsecBodyLimit = 1048576; # see Phase 0
     crowdsecAppsecUnreadableBodyBlock = false;
     # Fail open during the trial; decided in Phase 3.
     crowdsecAppsecFailureBlock = false;
     crowdsecAppsecUnreachableBlock = false;
   };
   ```

   Checked against the pinned plugin (v1.7.1): `appsec` mode skips the LAPI key
   requirement, and `crowdsecAppsecKeyFile` exists.
4. **Attach it to the public routers.** In the `lib.mapAttrs` that builds routers from
   `proxiedWebServices`, add `middlewares = [ "crowdsec-waf" ]`, except for a small
   `wafExempt` list. Start with:
   - **Matrix federation**: give `matrix` a second, higher-priority router for
     ``PathPrefix(`/_matrix/federation`) || PathPrefix(`/_matrix/key`)`` without the
     middleware. Server-to-server traffic from many sources; a false positive there
     silently breaks federation. The client API stays covered.
   - **ActivityPub inbox** (decided 2026-11-27): same treatment for `social` (Sharkey),
     a second router for ``Path(`/inbox`) || PathRegexp(`^/users/[^/]+/inbox$`)``
     without the middleware. Same reasoning as Matrix: server-to-server, and a false
     positive silently breaks federation. It is also a third of all ingress traffic and
     most of its request bodies (see B4/B5), so this roughly halves AppSec's load. Cost:
     the inbox is not inspected. The rest of `social` (web UI, API, media) stays covered.
   - Nothing else exempt yet. Jellyfin, dynmap (`mc-dynmap`) and `argunix` (GitHub
     webhooks carry commit messages and diffs) are watched in Phase 2, not exempted
     blind.

### Deploy order

1. apps-01 first (key, listener, simulation, whitelist, route), then confirm
   `curl -s -o /dev/null -w '%{http_code}\n' https://appsec.snyssen.be/` **from ingress**
   returns 401 (no key) and from anywhere else 403 (allowlist).
2. Then ingress. Confirm in Traefik's log (`/var/log/traefik/traefik.log`) that the
   plugin loaded, and that `cs_appsec_reqs_total{appsec_engine="0.0.0.0:7423/"}` starts
   counting at roughly ingress's request rate.

### Rollback

Remove `crowdsec-waf` from the router list on ingress and switch — every route is back to
plain proxying. Leaving the rest in place is harmless.

## Phase 2 — observe (2–4 weeks)

### Is it working, and what does it cost?

Re-run B1–B7 and fill in the Phase 2 row. Plus:

- AppSec load: `sum(rate(cs_appsec_reqs_total{appsec_engine="0.0.0.0:7423/"}[5m]))` — should
  track ingress's request rate minus exempted routes. A gap means requests are not
  being inspected.
- Plugin errors on ingress: Loki, `{host="ingress"} |= "appsecQuery"` — `unreachable`
  lines mean the route or the engine is failing (with fail-open, silently letting
  traffic through).

### What would have been blocked?

On apps-01 (read-only commands):

```sh
docker exec crowdsec-crowdsec-1 cscli metrics show appsec          # hits per rule, per listener
docker exec crowdsec-crowdsec-1 cscli alerts list --since 168h -s crowdsecurity/appsec-vpatch
docker exec crowdsec-crowdsec-1 cscli alerts list --since 168h -s crowdsecurity/appsec-native
docker exec crowdsec-crowdsec-1 cscli alerts inspect <id> -d       # the matched request
```

The CrowdSec web UI (`crowdsec-ui.snyssen.be`) shows the same alerts with filters.

For each alert, classify it:

1. Find the request in ingress's access log, to see the route and status:
   `{host="ingress"} |= "<source ip>" |= "<path>"` (Loki; the access log comes in through
   the `varlogs` collector).
2. **Attack** — a scanner, a known exploit path, an IP with other CrowdSec alerts.
   Nothing to do; that is the point.
3. **False positive** — a real user or client (the matrix client, Nextcloud sync,
   Immich upload, a GitHub webhook, a wiki edit…). Note the rule name and route.

### Exit criteria

- [ ] Every false positive has either an exception (an `on_match` hook in a
      `snyssen/` appsec-config that sets `allow` for that rule on that host/path), or
      its route moved to `wafExempt`, with the reason written next to it.
- [ ] No false positive left on Authelia, Nextcloud, Immich, Matrix client API.
- [ ] ingress: B2 still > 250 MiB at its lowest, B1 p99 < 60 %, no OOM kills
      (`{host="ingress"} |= "Out of memory"`).
- [ ] Latency: B7 p95 for interactive routes up by no more than ~B8 + 20 ms. Routes
      worse than that go to `wafExempt` (likely candidates: `jellyfin`, `mc-dynmap`).

## Phase 3 — enforce

1. `appsec-ingress.yaml`: drop `snyssen/appsec-observe` (keep any exception config,
   listed last).
2. `simulation.yaml`: remove the three AppSec scenarios (or the whole file).
3. Failure behaviour on ingress — **decide**:
   - `crowdsecAppsecUnreachableBlock`: unreachable almost always means apps-01 or the
     tailnet is down, when the public site is down anyway. Fail-closed costs little and
     stops an attacker from simply outlasting the engine. Recommended: `true`.
   - `crowdsecAppsecFailureBlock`: a 500 from the engine on one request. Recommended:
     `true`, and alert on it (below).
   Either way LAN/tailnet access is unaffected.
4. Grafana alert: `sum(rate(cs_appsec_reqs_total{appsec_engine="0.0.0.0:7423/"}[10m])) == 0`
   while `traefik_router_requests_total{instance="ingress"}` is increasing — the WAF has
   stopped seeing traffic.
5. Watch the first week the same way as Phase 2; rollback is the same as Phase 1.

## Open checks (resolve during Phase 1)

- [ ] Combining `appsec-default` with an `allow`-only config on one listener behaves as
      documented ("the last declared one takes precedence"). Only visible after deploy.
- [x] In `appsec` mode the plugin needs nothing beyond the AppSec settings (plugin
      source, v1.7.1).
- [x] Traefik on apps-01 supports per-router `observability.accessLogs` (v3.7.19).
- [x] Traefik on ingress loads a local plugin through a symlink into the store
      ("Plugins loaded.", 2026-11-27 13:06). First deploy (2026-11-27 12:20) failed: tmpfiles created
      the link's parents owned by root inside traefik's data dir, refused the "unsafe
      path transition", and never created the link. Traefik disabled the plugin and
      dropped every router using `crowdsec-waf`, so all public sites 404ed until the
      rollback. Fixed by declaring the parents owned by traefik. Lesson: a plugin that
      fails to load takes down every router that uses it, not just the WAF. Deploy
      plugin changes on ingress with `test` first.
- [x] `appsec.snyssen.be` resolves to apps-01 from ingress: the split-horizon wildcard
      `*.snyssen.be` answers `100.114.242.89` to tailnet clients
      (`ansible/hosts/group_vars/technitium/vars.yml`).
