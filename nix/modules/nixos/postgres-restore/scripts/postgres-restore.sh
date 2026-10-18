# shellcheck shell=bash
#
# Loads PostgreSQL dumps back into their databases.
#
# No shebang and no `set` line: this file is spliced into a writeShellApplication by
# ../default.nix, which supplies both plus `set -euo pipefail`. Everything the Nix
# config knows arrives in the JSON manifest at $MANIFEST.
#
# This is the other half of a restore: `backrest-restore` puts the dump *files* back,
# but a directory of dumps is not a database.
#
# Databases live in more than one PostgreSQL instance — most share the central cluster,
# but Immich (and later Dawarich and Mobilizon) run their own because they need
# extensions the central one does not have. That is an implementation detail of those
# stacks, not something worth making the operator track: a database name selects its
# instance here, and the command reaches the right container on its own.
#
# The manifest's shape:
#   { "command": "postgres-restore",
#     "instances": {
#       "<instance>": { "project":…, "composeFile":…, "envFile":…, "service":…,
#                       "dbHost":…, "dumpDir":…,
#                       "databases": { "<db>": "<PASSWORD_ENV_VAR>" } } } }

CMD="$(jq -r '.command' "$MANIFEST")"

# Tiers prodrigestivill/postgres-backup-local writes into, *least* to most specific —
# the order doubles as a tie-break rank below. All four are searched rather than just
# daily/: the tiers have different depths, so an older --at can only be satisfied from
# weekly/ or monthly/. On the production dumps, daily/ holds a week while monthly/
# reaches back six months.
TIERS=(monthly weekly last daily)

# Two jq passes, then everything is in memory: one for the instances, one for the
# database -> (instance, password variable) mapping.
declare -A INST_PROJECT INST_COMPOSE INST_ENV INST_SERVICE INST_DBHOST INST_DUMPDIR
while IFS=$'\t' read -r name project compose env service dbhost dumpdir; do
  INST_PROJECT["$name"]="$project"
  INST_COMPOSE["$name"]="$compose"
  INST_ENV["$name"]="$env"
  INST_SERVICE["$name"]="$service"
  INST_DBHOST["$name"]="$dbhost"
  INST_DUMPDIR["$name"]="$dumpdir"
done < <(jq -r '.instances | to_entries[]
                | [.key, .value.project, .value.composeFile, .value.envFile,
                   .value.service, .value.dbHost, .value.dumpDir] | @tsv' "$MANIFEST")

declare -A DB_INSTANCE DB_VAR
while IFS=$'\t' read -r db inst var; do
  DB_INSTANCE["$db"]="$inst"
  DB_VAR["$db"]="$var"
done < <(jq -r '.instances | to_entries[] | .key as $i
                | .value.databases | to_entries[] | [.key, $i, .value] | @tsv' "$MANIFEST")

mapfile -t ALL_DBS < <(printf '%s\n' "${!DB_INSTANCE[@]}" | sort)

from_override=""
dry_run=0
assume_yes=0
at_arg=""
selected=()

usage() {
  cat <<EOF
Usage: $CMD [--all | <database>...] [options]

Loads PostgreSQL dumps back with pg_restore. Databases with no dump in the source
directory are skipped and reported, so this works unchanged against a dump directory
holding databases this host does not have.

Each database knows which PostgreSQL instance it belongs to, so there is nothing to
select beyond the database itself.

Databases: ${ALL_DBS[*]}

  --all            every database listed above
  --list           print the database names, one per line, and exit
  --instances      print each instance and the databases it serves, and exit
  --from DIR       read dumps from DIR instead of each instance's own dump directory.
                   Applies to every selected database, so it only makes sense when
                   restoring databases from a single staging directory -- e.g. after
                   \`prod-import immich\` staged Immich's dumps on their own.
  --at WHEN        restore each database as of WHEN, instead of its newest dump.
                   Accepts anything date(1) understands: 2026-10-01, "2026-10-01 14:00",
                   "3 days ago", yesterday. A bare date means the *end* of that day.
                   All backup tiers are searched, so this reaches as far back as
                   retention kept anything -- months, not just the last week.
  --dry-run        report which dump each database would be restored from
  -y, --yes        skip the confirmation prompt

This is destructive: pg_restore runs with --clean --if-exists, so existing objects in
the target databases are dropped and recreated.
EOF
}

# Same shape and semantics as the backrest module's restore.sh, deliberately: the two
# commands are run back to back during a recovery and a --at that meant different
# things in each would be a trap. Duplicated rather than shared because factoring a
# dozen lines of date handling into a cross-module library costs more than it saves.
human_duration() {
  local s="$1" d h m
  d=$(( s / 86400 )); s=$(( s % 86400 ))
  h=$(( s / 3600 ));  s=$(( s % 3600 ))
  m=$(( s / 60 ))
  if   [ "$d" -gt 0 ]; then printf '%dd%dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf '%dh%dm' "$h" "$m"
  else                      printf '%dm' "$m"
  fi
}

# "<mtime>\t<tier rank>\t<tier>/<file>" for one database, oldest first.
#
# Selection is by mtime, not by the date in the filename: daily/ names carry a date but
# no time, weekly/ names are ISO week numbers, and monthly/ names are year-months — all
# of which would have to be mapped back to an instant. The mtime is simply when the
# dump was written, uniform across tiers, and restic preserves it on restore.
#
# -type f matters: every tier also holds a <db>-latest.sql.gz symlink whose own mtime is
# fractionally newer than the file it points at, so including symlinks would make
# "newest" always resolve to a link rather than a real dump.
dump_rows() {
  local db="$1" dir="$2" tier rank=0
  for tier in "${TIERS[@]}"; do
    if [ -d "$dir/$tier" ]; then
      find "$dir/$tier" -maxdepth 1 -type f -name "$db-*.sql.gz" \
        -printf "%T@\t$rank\t$tier/%f\n" 2>/dev/null || true
    fi
    rank=$(( rank + 1 ))
  done | sort -k1,1n -k2,2n
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --all)  selected=("${ALL_DBS[@]}") ;;
    --list) printf '%s\n' "${ALL_DBS[@]}"; exit 0 ;;
    --instances)
      for i in $(printf '%s\n' "${!INST_PROJECT[@]}" | sort); do
        printf '%-12s %s\n' "$i" "$(
          for d in "${ALL_DBS[@]}"; do
            [ "${DB_INSTANCE[$d]}" = "$i" ] && printf '%s ' "$d"
          done
        )"
      done
      exit 0 ;;
    --from)
      [ "$#" -ge 2 ] || { echo "$CMD: --from needs a directory" >&2; exit 2; }
      from_override="$2"; shift ;;
    --at)
      [ "$#" -ge 2 ] || { echo "$CMD: --at needs a date or time" >&2; exit 2; }
      at_arg="$2"; shift ;;
    --dry-run) dry_run=1 ;;
    -y|--yes)  assume_yes=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "$CMD: unknown option '$1'" >&2; usage >&2; exit 2 ;;
    *)  selected+=("$1") ;;
  esac
  shift
done

if [ "${#selected[@]}" -eq 0 ]; then
  echo "$CMD: nothing selected -- name one or more databases, or pass --all" >&2
  usage >&2
  exit 2
fi
for db in "${selected[@]}"; do
  if [ -z "${DB_INSTANCE[$db]:-}" ]; then
    echo "$CMD: '$db' is not one of this host's databases" >&2
    exit 2
  fi
done

at_epoch=""
if [ -n "$at_arg" ]; then
  if [[ "$at_arg" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    # A bare date means the end of that day. Dumps are taken through the night and
    # again every four hours, so midnight would quietly skip back a day.
    at_parse="$at_arg 23:59:59"
  else
    at_parse="$at_arg"
  fi
  if ! at_epoch="$(date -d "$at_parse" +%s 2>/dev/null)"; then
    echo "$CMD: could not understand --at '$at_arg'" >&2
    exit 2
  fi
  echo "Restoring each database as of $(date -d "@$at_epoch" '+%Y-%m-%d %H:%M:%S %z')"
fi

# After argument validation, so a typo in --at is reported as the usage error it is
# rather than being masked by a permission complaint.
if [ "$(id -u)" -ne 0 ]; then
  echo "$CMD: must run as root (the database passwords are root-only)" >&2
  exit 1
fi

# Pair each database with the dump it would use before touching anything, so the
# confirmation below shows the real plan rather than a promise.
plan_db=(); plan_dump=(); plan_dir=(); too_old=()
for db in "${selected[@]}"; do
  inst="${DB_INSTANCE[$db]}"
  dir="${from_override:-${INST_DUMPDIR[$inst]}}"

  rows="$(dump_rows "$db" "$dir")"
  if [ -z "$rows" ]; then
    # No dump at all. Expected and fine: this is what lets the command run unchanged
    # against a production dump directory full of databases this host does not have.
    printf '    %-20s skipped -- no dump under %s\n' "$db" "$dir"
    continue
  fi

  if [ -n "$at_epoch" ]; then
    row="$(awk -F'\t' -v c="$at_epoch" '$1 <= c' <<<"$rows" | tail -1)"
  else
    row="$(tail -1 <<<"$rows")"
  fi

  if [ -z "$row" ]; then
    # Dumps exist, but all of them are newer than the requested time. Unlike "no dump
    # at all" this is not something to quietly skip: it means the --at is wrong for
    # this selection, and restoring the rest while silently dropping this database
    # would leave the cluster in a state that never existed.
    oldest_row="$(head -1 <<<"$rows")"
    printf '  ! %-20s nothing at or before that time (oldest: %s, %s)\n' \
      "$db" \
      "$(cut -f3 <<<"$oldest_row")" \
      "$(date -d "@${oldest_row%%$'\t'*}" '+%Y-%m-%d %H:%M')"
    too_old+=("$db")
    continue
  fi

  epoch="${row%%$'\t'*}"
  dump="$(cut -f3 <<<"$row")"
  when="$(date -d "@$epoch" '+%Y-%m-%d %H:%M')"

  if [ -n "$at_epoch" ]; then
    # Tiers thin out with age, so an older --at routinely lands further back than asked
    # -- show how far, and flag anything beyond a couple of days.
    skew=$(( at_epoch - ${epoch%.*} ))
    marker=" "
    [ "$skew" -gt 172800 ] && marker="!"
    printf '  %s %-20s %-10s %s  %-34s (%s before)\n' \
      "$marker" "$db" "$inst" "$when" "$dump" "$(human_duration "$skew")"
  else
    printf '    %-20s %-10s %s  %s\n' "$db" "$inst" "$when" "$dump"
  fi
  plan_db+=("$db"); plan_dump+=("$dump"); plan_dir+=("$dir")
done

if [ "${#too_old[@]}" -gt 0 ]; then
  echo >&2
  echo "$CMD: no dump at or before that time for: ${too_old[*]}" >&2
  echo "  Pick a later --at, or name only the databases that have one." >&2
  exit 1
fi
if [ "${#plan_db[@]}" -eq 0 ]; then
  echo "$CMD: no dumps found for any selected database" >&2
  exit 1
fi
if [ "$dry_run" -eq 1 ]; then
  echo
  echo "$CMD: --dry-run, nothing restored."
  exit 0
fi
if [ "$assume_yes" -ne 1 ]; then
  echo
  echo "pg_restore runs with --clean --if-exists: existing objects in the"
  echo "databases listed above will be dropped and recreated."
  read -r -p "Proceed? [y/N] " reply
  case "$reply" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Aborted."; exit 1 ;;
  esac
fi

status=0
for i in "${!plan_db[@]}"; do
  db="${plan_db[$i]}"
  dump="${plan_dump[$i]}"
  dir="${plan_dir[$i]}"
  inst="${DB_INSTANCE[$db]}"

  echo "==> $db ($inst: $dump)"
  # Everything below runs in a subshell so each instance's environment file is sourced
  # in isolation: the files define overlapping names (POSTGRES_PASSWORD and friends),
  # and leaking one instance's values into another's compose interpolation is exactly
  # the kind of bug that would only surface as a confusing authentication failure.
  #
  # Sourcing serves two purposes at once: it gives docker compose the variables its own
  # interpolation needs, and it is where the database password comes from -- so the
  # password is only ever an environment lookup, never an argument.
  #
  # Connect as the database's own role, not the superuser: with --no-owner every
  # restored object ends up owned by whoever connected, and restoring as postgres would
  # leave the application with no privileges on its own tables.
  #
  # `compose run` with an ad-hoc mount rather than `exec` into the running sidecar:
  # --from may point outside the directory that sidecar has mounted (that is the whole
  # point of the legacy-prod staging paths). The containers have no container_name:
  # either, so they can only be addressed through compose anyway.
  #
  # The dumps are PostgreSQL custom-format archives despite the .sql.gz name
  # (POSTGRES_EXTRA_OPTS="--format c"), so pg_restore reads them directly.
  if (
    set -a
    # shellcheck disable=SC1090
    . "${INST_ENV[$inst]}"
    set +a
    var="${DB_VAR[$db]}"
    pw="${!var:-}"
    if [ -z "$pw" ]; then
      echo "  $db: no password in $var" >&2
      exit 1
    fi
    docker compose --project-name "${INST_PROJECT[$inst]}" -f "${INST_COMPOSE[$inst]}" \
      run --rm \
      -v "$dir:/restore:ro" \
      -e "PGPASSWORD=$pw" \
      --entrypoint pg_restore \
      "${INST_SERVICE[$inst]}" \
      --no-privileges --no-owner --clean --if-exists \
      -h "${INST_DBHOST[$inst]}" -U "$db" -d "$db" "/restore/$dump"
  ); then
    echo "  $db: ok"
  else
    echo "  $db: pg_restore exited non-zero" >&2
    status=1
  fi
done

if [ "$status" -ne 0 ]; then
  echo
  echo "One or more databases reported errors. Note pg_restore also exits non-zero for" >&2
  echo "warnings it ignored (extensions it could not create, for instance), so read the" >&2
  echo "output above before assuming data is missing." >&2
fi
exit "$status"
