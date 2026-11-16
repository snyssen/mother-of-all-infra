# Monitoring as code

Everything the monitoring stack on `apps-01` does is declared in
`nix/hosts/apps-01/compose/monitoring/`: what gets collected, the alert rules, how alerts
are routed, Grafana's datasources and its dashboards. Grafana's UI is for reading. Changes
go through the repo.

## Where things live

| What | File |
| --- | --- |
| Scrape jobs, rule loading, Alertmanager target | `prometheus-config.nix` |
| Alert rules | `prometheus/rules/alerts.yml` |
| Recording rules | `prometheus/rules/recording.yml` |
| Alert rule unit tests | `prometheus/tests/alerts.test.yml` |
| Alert routing, inhibition, receivers | `alertmanager.yml` |
| ntfy message format (title, priority, links) | `../ntfy/alertmanager-template.nix` |
| Grafana datasources | `grafana/provisioning/datasources/datasources.yaml` |
| Grafana dashboards | `grafana/dashboards/<folder>/<name>.json` |

The `monitoring` flake check (`nix/checks/monitoring.nix`, part of `just nix-check`)
validates the rules, runs their unit tests and checks the Alertmanager config.

## Alerts

Prometheus evaluates the rules and Alertmanager routes them:

- **ntfy:** every alert except the Watchdog goes to the `monitoring` topic, over the
  shared Docker network, so delivery does not depend on Traefik.
- **healthchecks.io:** the always-firing `Watchdog` alert is sent there every minute. If
  the pings stop, healthchecks.io alerts on its own, which covers Prometheus, rule
  evaluation and Alertmanager all being down.

Every rule sets two labels:

- `severity` (`warning`, `error` or `critical`) is what the alert means. When a check has
  two levels, both rules share one `alertname` and differ only by threshold and severity.
  While the critical alert fires, Alertmanager mutes the warning alert for the same
  instance and device, so you get one notification that escalates rather than two.
- `priority` (`min`, `low`, `default`, `high` or `urgent`) is the ntfy priority the
  notification is sent with. It is set per rule on purpose: a critical CPU temperature is
  `urgent`, a critical disk is `high`. Resolved notifications always arrive as `low`.

Annotations: `summary` (one line), optional `description`, and `dashboard_uid`, which
becomes a link to that Grafana dashboard in the notification.

To add or change a rule, edit `alerts.yml`, add a case to `alerts.test.yml`, then run
`nix build .#checks.x86_64-linux.monitoring`.

### Silencing

Each firing notification has a **Silence** link to Grafana's silence editor, with the
alert's labels already filled in as matchers. Adjust the duration or matchers, then save.
Silences live in Alertmanager: Grafana manages them through its `alertmanager`
datasource. *Alerting → Silences* lists them, and *Alerting → Alert rules* shows the
Prometheus rules and their state, read-only.

## Dashboards

Grafana loads every JSON file under `grafana/dashboards/`. Each subfolder becomes a
Grafana folder, and files at the root go to *General*. Provisioned dashboards cannot be
saved from the UI. To change one:

1. Edit it in Grafana as usual.
2. Click *Save*. Grafana refuses, because the dashboard is provisioned, and offers the
   dashboard's JSON instead. Copy it over the dashboard's file in the repo.
3. Review the diff and deploy. Until then, your change only lives in that browser tab.

`just grafana-dashboards-export` with no argument re-exports every dashboard already in
the repo. Given one or more uids, it adds or refreshes those. It needs `GRAFANA_URL`
(from `.envrc`) and a Viewer service account token in `GRAFANA_SERVICE_ACCOUNT_TOKEN`
(`just grafana-mcp-setup`).

To add a dashboard, build and save it in the UI, then run
`just grafana-dashboards-export <uid>`. The file lands in the subfolder matching the
Grafana folder it was saved in. Once deployed, the provisioned copy takes over the
saved one, since both share the uid.

To remove a dashboard, delete its file and deploy: Grafana deletes it too. A folder
left empty stays, so delete it in the UI. Datasources work differently: removing one
from `datasources.yaml` leaves it in Grafana. To actually delete it, list it under
`deleteDatasources`.
