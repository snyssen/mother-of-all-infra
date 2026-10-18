#!/usr/bin/env bash
# sops-update-keys-all.sh
# Re-encrypt every SOPS-managed secret file in the repo to whatever recipients
# .sops.yaml currently lists for it. Run this after adding or removing a key there —
# editing .sops.yaml alone changes nothing about files already encrypted.
#
# Usage: ./scripts/sops-update-keys-all.sh [--yes]

set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

ASSUME_YES=0
case "${1:-}" in
  --yes|-y) ASSUME_YES=1 ;;
  "") ;;
  *) echo "Usage: $0 [--yes]" >&2; exit 2 ;;
esac

cd "$(git rev-parse --show-toplevel)"
[ -f .sops.yaml ] || { echo "No .sops.yaml at the repo root." >&2; exit 1; }

# Which files are SOPS-managed is decided by .sops.yaml's own path_regex rules, so read
# them from there rather than hardcoding a glob: a rule added later is picked up with no
# change here. Matched against tracked files only — an untracked secret is not something
# to silently re-encrypt.
mapfile -t PATTERNS < <(sed -n 's/^[[:space:]]*-[[:space:]]*path_regex:[[:space:]]*//p' .sops.yaml)
if [ "${#PATTERNS[@]}" -eq 0 ]; then
  echo "No path_regex rules found in .sops.yaml." >&2
  exit 1
fi

FILES=()
while IFS= read -r f; do
  for re in "${PATTERNS[@]}"; do
    if printf '%s' "$f" | grep -qE "$re"; then FILES+=("$f"); break; fi
  done
done < <(git ls-files)

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "No tracked files match any rule in .sops.yaml — nothing to do."
  exit 0
fi

# Public keys this machine holds. Rotating a file means decrypting it first, so a file
# that lists none of these cannot be rotated from here however the keys are configured.
KEYFILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
MYKEYS=()
if [ -f "$KEYFILE" ]; then
  mapfile -t MYKEYS < <(age-keygen -y "$KEYFILE" 2>/dev/null || true)
fi

# pubkey -> anchor name, so "you need another machine" can say *which* one.
declare -A KEYNAME=()
while read -r name key; do
  [ -n "${key:-}" ] && KEYNAME["$key"]="$name"
done < <(sed -n 's/^[[:space:]]*-[[:space:]]*&\([A-Za-z0-9_]*\)[[:space:]]\+\(age1[a-z0-9]*\).*/\1 \2/p' .sops.yaml)

can_decrypt() {
  local file="$1" k
  for k in ${MYKEYS[@]+"${MYKEYS[@]}"}; do
    grep -q "$k" "$file" && return 0
  done
  return 1
}

# Name the recipients a file *does* have, for the message when we are not one of them.
recipients_of() {
  local file="$1" k
  while read -r k; do
    printf '%s ' "${KEYNAME[$k]:-$k}"
  done < <(grep -oE 'age1[a-z0-9]{50,}' "$file" | sort -u)
}

echo -e "${BOLD}SOPS files matching .sops.yaml (${#FILES[@]}):${NC}"
ROTATABLE=()
SKIPPED=()
for f in "${FILES[@]}"; do
  if can_decrypt "$f"; then
    echo -e "  ${GREEN}✓${NC} $f"
    ROTATABLE+=("$f")
  else
    echo -e "  ${YELLOW}−${NC} $f ${YELLOW}(no key for it on this machine; held by: $(recipients_of "$f"))${NC}"
    SKIPPED+=("$f")
  fi
done

if [ "${#ROTATABLE[@]}" -eq 0 ]; then
  echo -e "\n${RED}None of these can be decrypted on this machine.${NC}" >&2
  exit 1
fi

if [ "${#SKIPPED[@]}" -gt 0 ]; then
  echo
  echo -e "${YELLOW}${#SKIPPED[@]} file(s) will be left untouched — rotate them from a machine that holds one of their keys.${NC}"
fi

if [ "$ASSUME_YES" -ne 1 ]; then
  echo
  read -r -p "Re-encrypt ${#ROTATABLE[@]} file(s) to the recipients in .sops.yaml? [y/N] " reply
  case "$reply" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Aborted."; exit 1 ;;
  esac
fi

echo
STATUS=0
for f in "${ROTATABLE[@]}"; do
  # -y here is sops' own per-file prompt, not ours: we asked once above, and the point
  # of this script is not answering it ten times.
  if sops updatekeys -y "$f" >/dev/null 2>&1; then
    echo -e "  ${GREEN}ok${NC}    $f"
  else
    echo -e "  ${RED}FAIL${NC}  $f"
    # Re-run visibly so the reason is on screen rather than swallowed above.
    sops updatekeys -y "$f" 2>&1 | sed 's/^/        /' || true
    STATUS=1
  fi
done

echo
if [ "$STATUS" -eq 0 ]; then
  echo -e "${GREEN}Done.${NC} ${#ROTATABLE[@]} file(s) re-encrypted."
else
  echo -e "${RED}Some files failed to update.${NC}" >&2
fi
if [ "${#SKIPPED[@]}" -gt 0 ]; then
  printf '%s\n' "Still to do elsewhere: ${SKIPPED[*]}"
fi
echo "Review with: git diff --stat"
exit "$STATUS"
