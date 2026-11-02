#!/usr/bin/env bash
# sops-from-vault.sh
# Copy secrets from the legacy Ansible Vault into a SOPS file, without the values ever
# being printed, written to disk in plaintext, or passed on a command line. Built for
# the apps migration (docs/hypervisor/apps-migration-plan.md), where every stack
# carries some of its vault values over to nix/hosts/apps/data/<stack>.yaml.
#
# Usage: ./scripts/sops-from-vault.sh [--vault FILE] [--force] <sops-file> <vault_var>=<sops/key/path>...
#
#   just sops-from-vault nix/hosts/apps/data/actual-budget.yaml \
#     vault_backbone__authelia__oidc_actual_budget_clientid=compose-stacks/actual-budget/oidc/client_id
#
# <vault_var> is a top-level key of the vault (the `vault_*` name, not the group_vars
# alias pointing at it). <sops/key/path> is the slash-separated path sops-nix uses, so
# it can be pasted from the matching `sops.secrets."..."` entry. The SOPS file is
# created from .sops.yaml's rules if it does not exist yet.
#
# Values travel decrypted vault -> shell variable -> pipe -> `sops set --value-stdin`,
# and are compared back the same way, so the only output is key names and verdicts.
# Never run this under `bash -x`: tracing would print the variable holding them.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

usage() {
  echo "Usage: $0 [--vault FILE] [--force] <sops-file> <vault_var>=<sops/key/path>..." >&2
  exit 2
}

VAULT_FILE=ansible/hosts/group_vars/apps/vault.yml
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --vault) [ $# -ge 2 ] || usage; VAULT_FILE=$2; shift 2 ;;
    --force) FORCE=1; shift ;;
    -*) usage ;;
    *) break ;;
  esac
done
[ $# -ge 2 ] || usage
SOPS_FILE=$1
shift

cd "$(git rev-parse --show-toplevel)"

for tool in ansible-vault sops yq; do
  command -v "$tool" >/dev/null || { echo "$tool not found — run this from the devshell." >&2; exit 1; }
done
[ -n "${ANSIBLE_VAULT_PASSPHRASE:-}" ] || {
  echo "ANSIBLE_VAULT_PASSPHRASE is not set — run 'just ansible-vault-setup' first." >&2
  exit 1
}
[ -f "$VAULT_FILE" ] || { echo "No vault at $VAULT_FILE." >&2; exit 1; }

# Parse every mapping up front, so a typo fails before anything is written.
VARS=()
INDEXES=()
for mapping in "$@"; do
  case "$mapping" in
    *=*) ;;
    *) echo "Not a <vault_var>=<sops/key/path> mapping: $mapping" >&2; exit 2 ;;
  esac
  var=${mapping%%=*}
  path=${mapping#*=}
  [[ "$var" =~ ^[A-Za-z0-9_]+$ ]] || { echo "Invalid vault variable name: $var" >&2; exit 2; }
  [[ "$path" =~ ^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$ ]] || { echo "Invalid sops key path: $path" >&2; exit 2; }
  index=""
  IFS=/ read -ra segments <<<"$path"
  for segment in "${segments[@]}"; do index+="[\"$segment\"]"; done
  VARS+=("$var")
  INDEXES+=("$index")
done

# Decrypted once, held only in this variable (never exported, so no child process
# inherits it in its environment) and fed to yq through a pipe from the printf
# builtin, which leaves nothing in any process's argv.
VAULT_JSON=$(ansible-vault view --vault-password-file ansible/vault-passphrase-client.sh "$VAULT_FILE" | yq -o=json -I=0 '.')
trap 'unset VAULT_JSON' EXIT

vault_value() { printf '%s' "$VAULT_JSON" | yq -p=json -o=json -I=0 ".[\"$1\"]"; }
# The same encoding read back from the SOPS file. `sops decrypt --extract` would be the
# obvious tool, but it prints scalars raw and without a final newline, so it cannot be
# compared byte-for-byte with yq's JSON. `.<index>` is valid yq for `["a"]["b"]` paths.
sops_value() { sops decrypt --output-type json "$SOPS_FILE" | yq -p=json -o=json -I=0 ".$1"; }

missing=0
for var in "${VARS[@]}"; do
  if [ "$(printf '%s' "$VAULT_JSON" | yq -p=json ".[\"$var\"] | (. != null)")" != "true" ]; then
    echo -e "${RED}✗${NC} $var is not set in $VAULT_FILE" >&2
    missing=1
  fi
done
[ "$missing" -eq 0 ] || exit 1

if [ ! -f "$SOPS_FILE" ]; then
  mkdir -p "$(dirname "$SOPS_FILE")"
  # Recipients come from whichever .sops.yaml rule matches the target path, exactly as
  # `sops <file>` would pick them for a new file.
  printf '{}\n' | sops encrypt --filename-override "$SOPS_FILE" --input-type yaml --output-type yaml /dev/stdin >"$SOPS_FILE.tmp"
  mv "$SOPS_FILE.tmp" "$SOPS_FILE"
  echo -e "${GREEN}+${NC} created $SOPS_FILE"
fi

# An existing key is only overwritten with --force: these files are the source of truth
# for the new host, and a stack may already have rotated a value on purpose.
if [ "$FORCE" -eq 0 ]; then
  conflict=0
  for i in "${!VARS[@]}"; do
    if sops decrypt --extract "${INDEXES[$i]}" "$SOPS_FILE" >/dev/null 2>&1 \
      && ! cmp -s <(vault_value "${VARS[$i]}") <(sops_value "${INDEXES[$i]}"); then
      echo -e "${RED}✗${NC} ${INDEXES[$i]} already holds a different value (pass --force to overwrite)" >&2
      conflict=1
    fi
  done
  [ "$conflict" -eq 0 ] || exit 1
fi

failed=0
for i in "${!VARS[@]}"; do
  var=${VARS[$i]}
  index=${INDEXES[$i]}
  vault_value "$var" | sops set --idempotent --value-stdin "$SOPS_FILE" "$index"
  # Read back through the same JSON encoding on both sides, so whitespace that is part
  # of a value (a trailing space, a final newline) counts, while formatting does not.
  if cmp -s <(vault_value "$var") <(sops_value "$index"); then
    echo -e "${GREEN}✓${NC} $var → ${BOLD}$index${NC}"
  else
    echo -e "${RED}✗${NC} $var → $index: value read back from $SOPS_FILE does not match" >&2
    failed=1
  fi
done
exit "$failed"
