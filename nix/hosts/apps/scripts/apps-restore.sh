# shellcheck shell=bash
#
# Disaster recovery in one command.
#
# No shebang and no `set` line: this file is spliced into a writeShellApplication by
# ../backrest.nix, which supplies both plus `set -euo pipefail`.
#
# Deliberately a thin wrapper rather than a module feature: both halves stay
# independently runnable, which is what you want when one of them fails halfway through
# a real recovery. See the runbook in docs/backups.md for the full sequence — in
# particular, boot with docker.service and backrest.service masked before running this.
#
# backrest-restore and postgres-restore both come from environment.systemPackages (the
# backrest module and the databases stack respectively), so they resolve from PATH
# rather than by store path — which also keeps this wrapper from having to reach across
# into another stack's module.

# --at is forwarded to both halves on purpose: they mean the same thing by it (the
# newest snapshot / dump at or before that instant), and restoring files from one date
# while loading databases from another would produce a system state that never existed.
args=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run|-y|--yes) args+=("$1") ;;
    --at)
      [ "$#" -ge 2 ] || { echo "apps-restore: --at needs a date or time" >&2; exit 2; }
      args+=(--at "$2"); shift ;;
    *)
      echo "apps-restore: only --at, --dry-run and --yes are accepted here;" >&2
      echo "  run backrest-restore / postgres-restore directly for anything finer" >&2
      echo "  (restoring a subset of groups or databases, a different repo, and so on)." >&2
      exit 2 ;;
  esac
  shift
done

echo "==> Restoring files from the backup repository"
backrest-restore --all ${args[@]+"${args[@]}"}

echo
echo "==> Loading the Postgres dumps that restore just put back"
postgres-restore --all ${args[@]+"${args[@]}"}
