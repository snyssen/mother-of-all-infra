#!/usr/bin/env bash
# update-ansible-vault-pass.sh
# Safely add or replace ANSIBLE_VAULT_PASSPHRASE in .envrc.private
# Usage: ./update-ansible-vault-pass.sh

set -euo pipefail

TARGET=".envrc.private"
VAR="ANSIBLE_VAULT_PASSPHRASE"

# Regex for detecting an export line for the variable
EXPORT_GREP='^[[:space:]]*export[[:space:]]+'"$VAR"'[[:space:]]*='

file_exists=false
has_export=false

if [[ -f "$TARGET" ]]; then
  file_exists=true
  if grep -Eq "$EXPORT_GREP" "$TARGET"; then
    has_export=true
  fi
fi

if $file_exists && $has_export; then
  read -r -p "$TARGET already contains an exported $VAR. Do you want to update it? [y/N] " confirm
  case "$confirm" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Aborting: $VAR not changed."; exit 0 ;;
  esac
fi

# Prompt for the password (hidden input) — single prompt only
read -r -s -p "Enter Ansible vault password: " pass
echo

# Escape single quotes for safe single-quoted shell literal
escaped_pass=$(printf '%s' "$pass" | sed "s/'/'\"'\"'/g")

new_line="export $VAR='$escaped_pass'"

# Ensure file exists (create if necessary)
if [[ ! -f "$TARGET" ]]; then
  echo "Creating $TARGET"
  touch "$TARGET"
  chmod 600 "$TARGET"
fi

# Replace existing export line if present, otherwise append
if grep -Eq "$EXPORT_GREP" "$TARGET"; then
  # Replace in-place without creating a backup
  sed -E -i "s|^[[:space:]]*export[[:space:]]+ANSIBLE_VAULT_PASSPHRASE[[:space:]]*=.*|$new_line|" "$TARGET"
  echo "Replaced existing $VAR in $TARGET."
else
  # Append to file with a newline separator
  {
    printf '\n'
    printf '%s\n' "$new_line"
  } >> "$TARGET"
  echo "Appended $VAR to $TARGET."
fi

# Lock down permissions
chmod 600 "$TARGET" || true

echo "Done."
