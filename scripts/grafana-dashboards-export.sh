#!/usr/bin/env bash
# grafana-dashboards-export.sh
# Pull dashboards from the live Grafana into the repo, where Grafana provisions them from
# (nix/hosts/apps-01/compose/monitoring/grafana/dashboards, one subfolder per Grafana
# folder, the General folder at the root).
#
# Usage:
#   ./grafana-dashboards-export.sh            re-export every dashboard already in the repo
#   ./grafana-dashboards-export.sh <uid>...   export these dashboards (adds new ones)
#
# Needs GRAFANA_URL (.envrc) and GRAFANA_SERVICE_ACCOUNT_TOKEN (.envrc.private, set by
# `just grafana-mcp-setup`); a Viewer token is enough.

set -euo pipefail

DEST="nix/hosts/apps-01/compose/monitoring/grafana/dashboards"

: "${GRAFANA_URL:?GRAFANA_URL is not set (is direnv loaded?)}"
: "${GRAFANA_SERVICE_ACCOUNT_TOKEN:?GRAFANA_SERVICE_ACCOUNT_TOKEN is not set, run 'just grafana-mcp-setup'}"

api() {
  curl -fsS -H "Authorization: Bearer ${GRAFANA_SERVICE_ACCOUNT_TOKEN}" "${GRAFANA_URL%/}$1"
}

slugify() {
  tr '[:upper:]' '[:lower:]' <<<"$1" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

mkdir -p "$DEST"

if [[ $# -gt 0 ]]; then
  uids=("$@")
else
  mapfile -t uids < <(find "$DEST" -name '*.json' -exec jq -r '.uid' {} \; | sort -u)
  if [[ ${#uids[@]} -eq 0 ]]; then
    echo "No dashboards in $DEST yet: pass the uids to export." >&2
    exit 1
  fi
fi

for uid in "${uids[@]}"; do
  json="$(api "/api/dashboards/uid/${uid}")"
  title="$(jq -r '.dashboard.title' <<<"$json")"
  folder="$(jq -r '.meta.folderTitle // "General"' <<<"$json")"

  dir="$DEST"
  [[ "$folder" != "General" ]] && dir="$DEST/$folder"
  file="$dir/$(slugify "$title").json"
  mkdir -p "$dir"

  # A renamed or moved dashboard keeps its uid: drop the file it used to live in.
  while IFS= read -r old; do
    [[ "$old" != "$file" ]] && rm -- "$old" && echo "removed $old"
  done < <(grep -rlF "\"uid\": \"${uid}\"" "$DEST" --include='*.json' | while IFS= read -r f; do
    [[ "$(jq -r '.uid' "$f")" == "$uid" ]] && echo "$f"
  done)

  # id and version are database bookkeeping; provisioning keys on uid alone.
  jq '.dashboard | del(.id, .version, .iteration)' <<<"$json" >"$file"
  echo "exported $file"
done
