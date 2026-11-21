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
#
# ntfy constraints this has to live within (both reject the whole publish with a 400, so
# the alert is silently lost — check Alertmanager's logs for `Notify failed`):
# - Since v2.38, `call`, `html`, `js` and `urlquery` are refused (error 40044), so silence
#   matchers are percent-encoded by hand with `replace` (`%` first, so it isn't doubled).
# - The rendered message must fit ntfy's message size limit, 4 KB by default (error
#   40041). Rules without an `instance` label (EndpointDown) can group dozens of alerts,
#   e.g. every backup check failing at once, so past `$compact` alerts the per-alert
#   descriptions and links give way to one dashboard/silence link for the whole group.
let
  # Kept on one line each: they are spliced into the YAML block scalars below, where a
  # line break would leave the rest at the wrong indentation.
  # Matcher `name=value`, percent-encoded for a query string.
  matcher =
    value:
    ''{{ ${value} | replace "%" "%25" | replace "&" "%26" | replace "#" "%23" | replace "+" "%2B" | replace " " "%20" | replace "=" "%3D" | replace "\"" "%22" }}'';
  silenceLink =
    labels:
    "[Silence](${grafanaUrl}/alerting/silence/new?alertmanager=alertmanager"
    + "{{ range $name, $value := ${labels} }}&matcher=${matcher ''printf "%s=%s" $name $value''}{{ end }})";
in
''
  title: |
    {{- if eq .status "firing" }}🚨{{ else }}✅{{ end }} {{ .commonLabels.alertname }}
    {{- with .commonLabels.severity }} ({{ . }}){{ end }}
  priority: |
    {{- if eq .status "resolved" }}low{{ else }}{{ .commonLabels.priority | default "default" }}{{ end }}
  message: |
    {{- $compact := gt (len .alerts) 5 }}
    {{- range .alerts }}
    {{ if eq .status "firing" }}🔥{{ else }}✅{{ end }} {{ .annotations.summary | default .labels.alertname }}
    {{- if not $compact }}
    {{- with .annotations.description }}

    {{ . }}
    {{- end }}
    {{- if or .annotations.dashboard_uid (eq .status "firing") }}

    {{ with .annotations.dashboard_uid }}[Dashboard](${grafanaUrl}/d/{{ . }}){{ end }}
    {{- if and .annotations.dashboard_uid (eq .status "firing") }} · {{ end }}
    {{- if eq .status "firing" }}${silenceLink ".labels"}{{ end }}
    {{- end }}
    {{ end }}
    {{- end }}
    {{- if $compact }}

    {{ with .commonAnnotations.dashboard_uid }}[Dashboard](${grafanaUrl}/d/{{ . }}){{ end }}
    {{- if and .commonAnnotations.dashboard_uid (eq .status "firing") }} · {{ end }}
    {{- if eq .status "firing" }}${silenceLink ".commonLabels"} (all {{ len .alerts }}){{ end }}
    {{- end }}
''
