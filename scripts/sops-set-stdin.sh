#!/usr/bin/env bash
# sops-set-stdin.sh
# Store whatever arrives on stdin, byte for byte, as one key of a SOPS file — without the
# value ever being printed, written to disk in plaintext, or passed on a command line. For
# secrets that already exist as a file somewhere else, typically on another machine:
#
#   ssh gaming cat ~/Documents/.config/syncthing/key.pem \
#     | just sops-set-stdin nix/hosts/gaming/data/secrets.yaml syncthing/key
#
# Usage: ./scripts/sops-set-stdin.sh <sops-file> <sops/key/path>
#
# The SOPS file is created from .sops.yaml's rules if needed. An existing key is never
# overwritten — rotating a secret is a deliberate act, done with
# `just sops-update`. The value is read back and compared before reporting success.
# Never run this under `bash -x`: tracing would print the variable holding the value.

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

usage() {
  echo "Usage: $0 <sops-file> <sops/key/path>  (value on stdin)" >&2
  exit 2
}

[ $# -eq 2 ] || usage
SOPS_FILE=$1
PATH_ARG=$2
[[ "$PATH_ARG" =~ ^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$ ]] || { echo "Invalid sops key path: $PATH_ARG" >&2; exit 2; }
[ ! -t 0 ] || { echo "Nothing on stdin — pipe the value in." >&2; exit 2; }

for tool in sops yq; do
  command -v "$tool" >/dev/null || { echo "$tool not found — run this from the devshell." >&2; exit 1; }
done

index=""
IFS=/ read -ra segments <<<"$PATH_ARG"
for segment in "${segments[@]}"; do index+="[\"$segment\"]"; done

if [ ! -f "$SOPS_FILE" ]; then
  mkdir -p "$(dirname "$SOPS_FILE")"
  # Recipients come from whichever .sops.yaml rule matches the target path, exactly as
  # `sops <file>` would pick them for a new file.
  printf '{}\n' | sops encrypt --filename-override "$SOPS_FILE" --input-type yaml --output-type yaml /dev/stdin >"$SOPS_FILE.tmp"
  mv "$SOPS_FILE.tmp" "$SOPS_FILE"
  echo -e "${GREEN}+${NC} created $SOPS_FILE"
fi

if sops decrypt --extract "$index" "$SOPS_FILE" >/dev/null 2>&1; then
  echo -e "${RED}✗${NC} $index already exists in $SOPS_FILE — not overwriting" >&2
  exit 1
fi

# The whole of stdin as one JSON string (what `sops set` takes), final newline included.
# Held only in this unexported variable.
VALUE_JSON=$(yq -n -o=json -I=0 'load_str("/dev/stdin")')
trap 'unset VALUE_JSON' EXIT
[ "$VALUE_JSON" != '""' ] || { echo -e "${RED}✗${NC} stdin was empty" >&2; exit 1; }

printf '%s' "$VALUE_JSON" | sops set --value-stdin "$SOPS_FILE" "$index"

if cmp -s <(printf '%s\n' "$VALUE_JSON") <(sops decrypt --output-type json "$SOPS_FILE" | yq -p=json -o=json -I=0 ".$index"); then
  echo -e "${GREEN}✓${NC} stdin → ${BOLD}$index${NC} in $SOPS_FILE"
else
  echo -e "${RED}✗${NC} value read back from $SOPS_FILE does not match" >&2
  exit 1
fi
