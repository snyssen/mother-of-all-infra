{ grafanaUrl }:
# ntfy message template for Alertmanager's webhook payload, selected with
# `?template=alertmanager-grafana` (see monitoring's alertmanager.yml). Replaces both the
# grafana-to-ntfy relay and ntfy's built-in `alertmanager` template, to keep what the
# former gave: the priority taken from the alert's `priority` label, and links back to
# Grafana (the dashboard, and a silence pre-filled with the alert's labels).
#
# Go templates, rendered by ntfy with its sprig-like functions. Alertmanager groups alerts
# by alertname, instance and severity, so the common `priority` label always exists.
# Resolved notifications drop to `low`: they need no attention.
''
  title: |
    {{- if eq .status "firing" }}🚨{{ else }}✅{{ end }} {{ .commonLabels.alertname }}
    {{- with .commonLabels.severity }} ({{ . }}){{ end }}
  priority: |
    {{- if eq .status "resolved" }}low{{ else }}{{ .commonLabels.priority | default "default" }}{{ end }}
  message: |
    {{- range .alerts }}
    {{ if eq .status "firing" }}🔥{{ else }}✅{{ end }} {{ .annotations.summary | default .labels.alertname }}
    {{- with .annotations.description }}

    {{ . }}
    {{- end }}
    {{- if or .annotations.dashboard_uid (eq .status "firing") }}

    {{ with .annotations.dashboard_uid }}[Dashboard](${grafanaUrl}/d/{{ . }}){{ end }}
    {{- if and .annotations.dashboard_uid (eq .status "firing") }} · {{ end }}
    {{- if eq .status "firing" }}[Silence](${grafanaUrl}/alerting/silence/new?alertmanager=alertmanager
    {{- range $name, $value := .labels }}&matcher={{ urlquery (printf "%s=%s" $name $value) }}{{ end }}){{ end }}
    {{- end }}
    {{ end }}
''
