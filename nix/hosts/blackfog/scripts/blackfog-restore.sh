# shellcheck shell=bash
#
# Restore this workstation's backup (../backup.nix), in place or into a staging directory.
#
# No shebang and no `set` line: this file is spliced into a writeShellApplication by
# ../backup.nix, which supplies both plus `set -euo pipefail`, and defines BACKUP_ROOT
# (the home directory), SNAPSHOT_HOST, SNAPSHOT_TAG and RESTIC (the generated restic
# wrapper) ahead of it.
#
# It restores the snapshot's BACKUP_ROOT subtree (`<id>:<root>`), not the whole snapshot
# into `/`. As a non-root user, the latter would try to restore the metadata of root-owned
# parents such as /home, and fail on them. The catch is that restic then matches
# --include patterns relative to that subtree, and an absolute path silently matches
# nothing, so the paths given here are translated rather than passed through.

usage() {
  cat <<EOF
Usage: ${SNAPSHOT_HOST}-restore [--snapshot ID] [--target DIR] [--dry-run] [--yes] [PATH...]

Restores the latest backup of $BACKUP_ROOT in place. Files whose content differs from the
snapshot are overwritten, even when the local copy is newer; files created since the
backup are left alone, and nothing is ever deleted.

  PATH...         restore only these files or directories (under $BACKUP_ROOT)
  --snapshot ID   restore that snapshot rather than the latest
  --target DIR    restore into DIR, laid out like $BACKUP_ROOT, rather than in place
  --dry-run       show what would change, then stop
  -y, --yes       do not ask for confirmation
EOF
}

snapshot=latest
target=$BACKUP_ROOT
dry_run=0
assume_yes=0
paths=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --snapshot)
      [ "$#" -ge 2 ] || { echo "${SNAPSHOT_HOST}-restore: --snapshot needs an ID" >&2; exit 2; }
      snapshot=$2; shift ;;
    --target)
      [ "$#" -ge 2 ] || { echo "${SNAPSHOT_HOST}-restore: --target needs a directory" >&2; exit 2; }
      target=$(realpath -m -s -- "$2"); shift ;;
    --dry-run) dry_run=1 ;;
    -y|--yes) assume_yes=1 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; paths+=("$@"); break ;;
    -*) echo "${SNAPSHOT_HOST}-restore: unknown option $1" >&2; usage >&2; exit 2 ;;
    *) paths+=("$1") ;;
  esac
  shift
done

# -s keeps paths as typed (no symlink resolution), which is how they were backed up.
includes=()
for path in ${paths[@]+"${paths[@]}"}; do
  abs=$(realpath -m -s -- "$path")
  case "$abs" in
    "$BACKUP_ROOT") includes=(); break ;; # the whole backup, same as no PATH at all
    "$BACKUP_ROOT"/*) includes+=(--include "${abs#"$BACKUP_ROOT"}") ;;
    *)
      echo "${SNAPSHOT_HOST}-restore: $abs is outside $BACKUP_ROOT, which is all this backup holds" >&2
      exit 2 ;;
  esac
done

# An unknown ID is not an error to restic (it prints a warning and returns []), so an
# empty result is checked for rather than relying on the exit code.
if [ "$snapshot" = latest ]; then
  snapshots=$("$RESTIC" snapshots --json --latest 1 --tag "$SNAPSHOT_TAG" --host "$SNAPSHOT_HOST")
else
  snapshots=$("$RESTIC" snapshots --json "$snapshot")
fi
id=$(jq -r 'max_by(.time) | .id // empty' <<<"$snapshots")
if [ -z "$id" ]; then
  echo "${SNAPSHOT_HOST}-restore: no snapshot found ($snapshot)" >&2
  exit 1
fi
taken=$(jq -r 'max_by(.time) | .time' <<<"$snapshots")
echo "Snapshot ${id:0:8}, taken $(date -d "$taken" '+%Y-%m-%d %H:%M')"
echo "Restoring into $target"
echo

restore_args=(
  "$id:$BACKUP_ROOT"
  --target "$target"
  --overwrite if-changed
  ${includes[@]+"${includes[@]}"}
)

# The preview is restic's own dry run. Its -vv output lists every entry as `unchanged`,
# `restored` or `updated`; only files that would actually be written are shown, with the
# list capped so a full disaster recovery does not scroll for minutes.
preview=$("$RESTIC" restore "${restore_args[@]}" --dry-run -vv)
shown=0
total=0
unchanged=0
while IFS= read -r line; do
  if [[ $line =~ ^(restored|updated)\ +(/.*)\ with\ size\ (.*)$ ]]; then
    total=$((total + 1))
    if [ "$total" -le 50 ]; then
      printf '  %-8s %s%s (%s)\n' "${BASH_REMATCH[1]}" "${target%/}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
      shown=$total
    fi
  elif [[ $line =~ ^unchanged\  ]]; then
    unchanged=$((unchanged + 1))
  fi
done <<<"$preview"

if [ "$total" -eq 0 ]; then
  if [ "$unchanged" -eq 0 ]; then
    # restic does not complain about an --include that matches nothing.
    echo "${SNAPSHOT_HOST}-restore: nothing in this snapshot matches the given path(s)" >&2
    exit 1
  fi
  echo "Nothing to restore: everything already matches the snapshot."
  exit 0
fi
if [ "$total" -gt "$shown" ]; then
  echo "  ... and $((total - shown)) more"
fi
echo
echo "$total file(s) to restore ('updated' overwrites a local file)."

if [ "$dry_run" -eq 1 ]; then
  exit 0
fi
if [ "$assume_yes" -eq 0 ]; then
  read -r -p "Proceed? [y/N] " answer
  case "$answer" in
    y|Y|yes) ;;
    *) echo "Aborted."; exit 1 ;;
  esac
fi

"$RESTIC" restore "${restore_args[@]}"
