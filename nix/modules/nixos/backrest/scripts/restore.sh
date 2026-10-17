# shellcheck shell=bash
#
# Restores restic snapshots onto this host.
#
# No shebang and no `set` line: this file is spliced into a writeShellApplication by
# restore.nix, which supplies both plus `set -euo pipefail`. Everything the Nix config
# knows arrives in the JSON manifest at $MANIFEST, so nothing in here is generated —
# which is the point. $HOME is also pre-set, to Backrest's own restic cache directory.
#
# The manifest's shape:
#   { "command": "<name>",
#     "groups": { "<group>": { "repo":  { "uri":…, "passwordFile":…, "env": {VAR: file} },
#                              "snapshotFilter": [restic flags…],
#                              "stopUnits":      [unit…],
#                              "paths":          [ {from, to, owner|null}… ] } } }

CMD="$(jq -r '.command' "$MANIFEST")"
mapfile -t ALL_GROUPS < <(jq -r '.groups | keys[]' "$MANIFEST")

usage() {
  cat <<EOF
Usage: $CMD [--all | <group>...] [options]

Restores restic snapshots onto this host. A group is one backup plan (or one legacy
autorestic location) and resolves to exactly one snapshot; several groups may be named
at once and are processed in the order given, under a single preflight and a single
confirmation.

Groups: ${ALL_GROUPS[*]}

  --all            every group listed above
  --list           print the group names, one per line, and exit
  --at WHEN        restore each group's state as of WHEN, instead of its latest
                   snapshot. Accepts anything date(1) understands: 2026-10-01,
                   "2026-10-01 14:00", "3 days ago", yesterday. A bare date means the
                   *end* of that day, so --at 2026-10-01 restores the last snapshot
                   taken on the 1st rather than the one from the night before.
  --check          only verify each group resolves to a snapshot that actually
                   contains every configured path. Fast, no sizing, no writes --
                   this is the cheap check worth running on a schedule.
  --dry-run        resolve and size everything, write nothing
  -y, --yes        skip the confirmation prompt
  --force          continue even if the capacity preflight says it will not fit
  --keep-stopped   leave the units this restore stopped stopped, instead of starting
                   them again at the end. For looking at restored data before the
                   application does -- it may migrate or rewrite it on first start --
                   or for running several restores without the stack flapping between
                   them. The units are still stopped beforehand either way; what is
                   named at the end is what to start when you are satisfied.
  --repo-uri URI   override the repository URI, keeping the same credentials -- for
                   falling back to the off-site copy when the on-site server is
                   unreachable
EOF
}

# --- manifest accessors -----------------------------------------------------------
# Each sets the globals the rest of the script reads. Kept as one jq call per concern
# rather than one per field: these run once per group, not per path.

group_setup() {
  local g="$1"
  REPO_URI="$(jq -r --arg g "$g" '.groups[$g].repo.uri' "$MANIFEST")"
  REPO_PASSWORD_FILE="$(jq -r --arg g "$g" '.groups[$g].repo.passwordFile' "$MANIFEST")"
  mapfile -t REPO_ENV < <(jq -r --arg g "$g" '.groups[$g].repo.env | to_entries[] | "\(.key)=\(.value)"' "$MANIFEST")
  mapfile -t SNAPSHOT_FILTER < <(jq -r --arg g "$g" '.groups[$g].snapshotFilter[]' "$MANIFEST")
  mapfile -t STOP_UNITS < <(jq -r --arg g "$g" '.groups[$g].stopUnits[]' "$MANIFEST")
  # from/to/owner are tab-separated; these paths come from the Nix config, which has
  # no business containing tabs or newlines.
  mapfile -t PATH_ROWS < <(jq -r --arg g "$g" '.groups[$g].paths[] | [.from, .to, (.owner // "")] | @tsv' "$MANIFEST")
}

load_repo_env() {
  export RESTIC_REPOSITORY="${repo_uri_override:-$REPO_URI}"
  export RESTIC_PASSWORD_FILE="$REPO_PASSWORD_FILE"
  local pair
  for pair in ${REPO_ENV[@]+"${REPO_ENV[@]}"}; do
    export "${pair%%=*}=$(cat "${pair#*=}")"
  done
}

# --- small helpers ------------------------------------------------------------------

# Targets routinely do not exist yet (restic creates them), so resolve df against the
# nearest existing ancestor instead.
nearest_existing() {
  local p="$1"
  while [ ! -e "$p" ]; do p="$(dirname "$p")"; done
  printf '%s' "$p"
}
# No -P: GNU df rejects it alongside --output ("options -P and --output are mutually
# exclusive"), and --output already gives one clean column.
df_mount() { df --output=target "$(nearest_existing "$1")" | tail -1; }
# -B1 asks for bytes outright rather than scaling df's default 1K blocks. The default
# unit honours $BLOCK_SIZE/$DF_BLOCK_SIZE from the environment, so a multiplying version
# would silently misreport free space by whatever factor happened to be set -- in a
# check whose entire job is deciding whether a restore fits.
df_avail() { df --output=avail -B1 "$(nearest_existing "$1")" | tail -1; }
human() { numfmt --to=iec-i --suffix=B "$1"; }

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

# --- argument parsing ---------------------------------------------------------------

mode=restore
dry_run=0
assume_yes=0
force=0
keep_stopped=0
repo_uri_override=""
at_arg=""
selected=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --all)     selected=("${ALL_GROUPS[@]}") ;;
    --list)    printf '%s\n' "${ALL_GROUPS[@]}"; exit 0 ;;
    --check)   mode=check ;;
    --dry-run) dry_run=1 ;;
    -y|--yes)  assume_yes=1 ;;
    --force)   force=1 ;;
    --keep-stopped) keep_stopped=1 ;;
    --at)
      [ "$#" -ge 2 ] || { echo "$CMD: --at needs a date or time" >&2; exit 2; }
      at_arg="$2"; shift ;;
    --repo-uri)
      [ "$#" -ge 2 ] || { echo "$CMD: --repo-uri needs a value" >&2; exit 2; }
      repo_uri_override="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "$CMD: unknown option '$1'" >&2; usage >&2; exit 2 ;;
    *)  selected+=("$1") ;;
  esac
  shift
done

if [ "${#selected[@]}" -eq 0 ]; then
  echo "$CMD: nothing selected -- name one or more groups, or pass --all" >&2
  usage >&2
  exit 2
fi
for g in "${selected[@]}"; do
  known=0
  for k in "${ALL_GROUPS[@]}"; do
    if [ "$g" = "$k" ]; then known=1; break; fi
  done
  if [ "$known" -ne 1 ]; then echo "$CMD: unknown group '$g'" >&2; exit 2; fi
done
at_epoch=""
if [ -n "$at_arg" ]; then
  if [[ "$at_arg" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    # A bare date means the end of that day. Backups run in the small hours, so
    # interpreting it as midnight would quietly hand back the *previous* day's
    # snapshot -- the opposite of what "restore from the 1st" means to anyone.
    at_parse="$at_arg 23:59:59"
  else
    at_parse="$at_arg"
  fi
  if ! at_epoch="$(date -d "$at_parse" +%s 2>/dev/null)"; then
    echo "$CMD: could not understand --at '$at_arg'" >&2
    exit 2
  fi
  # Always print the instant it resolved to: "as of some date" is far too easy to be
  # subtly wrong about, and this is the only place to catch it.
  echo "Restoring each group's state as of $(date -d "@$at_epoch" '+%Y-%m-%d %H:%M:%S %z')"
fi

# After argument validation, so a typo in --at is reported as the usage error it is
# rather than being masked by a permission complaint.
if [ "$(id -u)" -ne 0 ]; then
  echo "$CMD: must run as root -- restores write files owned by many different uids" >&2
  exit 1
fi

# --- phase 1: resolve one snapshot per group ----------------------------------------

declare -A snap_of=()
entry_group=(); entry_snap=(); entry_from=(); entry_to=(); entry_owner=(); entry_bytes=()
missing_groups=()
problems=0

echo "Resolving snapshots..."
for g in "${selected[@]}"; do
  group_setup "$g"
  load_repo_env

  snapjson="$(restic snapshots --no-lock --json "${SNAPSHOT_FILTER[@]}")"
  # "<epoch>\t<id>\t<time>", oldest first. The epochs come from one date(1) pass over
  # every timestamp: restic emits RFC3339 with a real UTC offset and nanoseconds, which
  # jq's own date parsing rejects, and comparing those strings lexically would silently
  # misorder snapshots either side of a DST change.
  snaptable="$(
    paste \
      <(jq -r '.[].time' <<<"$snapjson" | date -f - +%s) \
      <(jq -r '.[] | "\(.id)\t\(.time[0:19])"' <<<"$snapjson") \
    | sort -n
  )"

  if [ -n "$at_epoch" ]; then
    snapline="$(awk -F'\t' -v c="$at_epoch" '$1 <= c' <<<"$snaptable" | tail -1)"
  else
    snapline="$(tail -1 <<<"$snaptable")"
  fi

  if [ -z "$snapline" ]; then
    oldest="$(head -1 <<<"$snaptable" | cut -f3)"
    if [ -n "$oldest" ]; then
      printf '  %-20s no snapshot at or before that time (oldest available: %s)\n' "$g" "$oldest" >&2
    else
      printf '  %-20s no snapshots at all matching %s\n' "$g" "${SNAPSHOT_FILTER[*]}" >&2
    fi
    missing_groups+=("$g")
    problems=1
    continue
  fi

  snap_epoch="$(cut -f1 <<<"$snapline")"
  snap="$(cut -f2 <<<"$snapline")"
  snap_time="$(cut -f3 <<<"$snapline")"
  snap_of["$g"]="$snap"

  # With --at, show how far back of the requested instant each group actually landed.
  # Groups do not all back up successfully on the same days, so one of them silently
  # resolving to a much older snapshot is the realistic failure here -- make it visible
  # rather than guessing at a policy for it.
  if [ -n "$at_epoch" ]; then
    skew=$(( at_epoch - snap_epoch ))
    marker=" "
    [ "$skew" -gt 172800 ] && marker="!"
    printf '  %s %-20s %s  %s  (%s before)\n' \
      "$marker" "$g" "${snap:0:8}" "$snap_time" "$(human_duration "$skew")"
  else
    printf '    %-20s %s  %s\n' "$g" "${snap:0:8}" "$snap_time"
  fi

  # A root present in the snapshot but with nothing configured to receive it means a
  # path was dropped from the config. The restore would then "succeed" while silently
  # leaving that data behind -- the one failure mode that looks exactly like success.
  mapfile -t snaproots < <(jq -r --arg id "$snap" '.[] | select(.id == $id) | .paths[]?' <<<"$snapjson")
  for root in ${snaproots[@]+"${snaproots[@]}"}; do
    covered=0
    for row in ${PATH_ROWS[@]+"${PATH_ROWS[@]}"}; do
      from="${row%%$'\t'*}"
      case "$from" in "$root"|"$root"/*) covered=1; break ;; esac
    done
    if [ "$covered" -eq 0 ]; then
      printf '  %-20s WARNING: snapshot contains %s, nothing configured to restore it\n' "$g" "$root" >&2
    fi
  done

  for row in ${PATH_ROWS[@]+"${PATH_ROWS[@]}"}; do
    IFS=$'\t' read -r from to owner <<<"$row"

    if [ "$mode" = check ]; then
      # restic ls exits 0 even when the path is absent from the snapshot -- it just
      # prints the snapshot header and no node records (verified against the real
      # repository). So count node records; trusting the exit status would make this
      # check silently pass on a missing path, which is worse than having no check.
      n="$(restic ls --no-lock --json "$snap" "$from" 2>/dev/null \
           | grep -c '"struct_type":"node"' || true)"
      if [ "$n" -gt 0 ]; then
        printf '      ok       %s\n' "$from"
      else
        printf '      MISSING  %s\n' "$from" >&2
        problems=1
      fi
      continue
    fi

    # Sizing is a real --dry-run restore: identical code path to the restore itself (so
    # it cannot disagree with it), honours the subpath, and writes nothing. `restic
    # stats` looks like the right tool and is not -- it rejects the snapshot:subfolder
    # syntax outright and then reports on the whole snapshot instead.
    bytes="$(restic restore "$snap:$from" --target "$to" --dry-run --no-lock --json 2>/dev/null \
             | jq -r 'select(.message_type=="summary") | .total_bytes' | tail -1 || true)"
    if [ -z "$bytes" ]; then
      printf '      FAILED to size %s\n' "$from" >&2
      problems=1
      continue
    fi
    entry_group+=("$g"); entry_snap+=("$snap"); entry_from+=("$from")
    entry_to+=("$to");   entry_owner+=("$owner"); entry_bytes+=("$bytes")
  done
done

if [ "${#missing_groups[@]}" -gt 0 ]; then
  echo >&2
  echo "$CMD: no usable snapshot for: ${missing_groups[*]}" >&2
  if [ -n "$at_epoch" ]; then
    echo "  Pick a later --at, or name only the groups that do have one." >&2
  fi
  exit 1
fi

if [ "$mode" = check ]; then
  if [ "$problems" -ne 0 ]; then
    echo "$CMD: check FAILED" >&2
    exit 1
  fi
  echo "$CMD: every group resolves to a snapshot containing all configured paths."
  exit 0
fi
if [ "${#entry_to[@]}" -eq 0 ]; then
  echo "$CMD: nothing to restore" >&2
  exit 1
fi

# --- phase 2: capacity preflight, per filesystem -------------------------------------
# Per filesystem, not in total: / and /mnt/bulk are independent budgets here, and a
# combined figure would happily hide one of them overflowing.

declare -A fs_need=()
for i in "${!entry_to[@]}"; do
  fs="$(df_mount "${entry_to[$i]}")"
  fs_need["$fs"]=$(( ${fs_need["$fs"]:-0} + ${entry_bytes[$i]} ))
done

printf '\n%-20s %-9s %11s  %s\n' GROUP SNAPSHOT SIZE TARGET
for i in "${!entry_to[@]}"; do
  printf '%-20s %-9s %11s  %s\n' \
    "${entry_group[$i]}" "${entry_snap[$i]:0:8}" \
    "$(human "${entry_bytes[$i]}")" "${entry_to[$i]}"
done

echo
short=0
for fs in "${!fs_need[@]}"; do
  need="${fs_need[$fs]}"
  avail="$(df_avail "$fs")"
  printf '%-16s needs %11s, has %11s free\n' "$fs" "$(human "$need")" "$(human "$avail")"
  if [ "$need" -gt "$avail" ]; then short=1; fi
done
if [ "$short" -ne 0 ]; then
  echo "$CMD: not enough free space." >&2
  echo "  (Re-running over already-restored data over-counts: a dry run cannot see what is already on disk.)" >&2
  if [ "$force" -ne 1 ]; then exit 1; fi
  echo "$CMD: --force given, continuing anyway." >&2
fi

if [ "$dry_run" -eq 1 ]; then
  echo
  echo "$CMD: --dry-run, nothing written."
  exit "$problems"
fi
if [ "$assume_yes" -ne 1 ]; then
  echo
  read -r -p "Restore the above onto this host? [y/N] " reply
  case "$reply" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Aborted."; exit 1 ;;
  esac
fi

# --- phase 3: restore -----------------------------------------------------------------
# Backrest must not be running while data is rewritten underneath it: its schedules
# would back up the empty or half-restored state over the good snapshots, and retention
# would then start forgetting the originals -- a recovery rehearsal that destroys the
# real backups. Deliberately not restarted at the end; that is the operator's call,
# after verifying.
if systemctl is-active --quiet backrest.service; then
  echo "Stopping backrest.service."
  systemctl stop backrest.service
fi

results=()
left_stopped=(backrest.service)
status=0
for g in "${selected[@]}"; do
  snap="${snap_of[$g]:-}"
  if [ -z "$snap" ]; then continue; fi
  group_setup "$g"
  load_repo_env

  restarts=()
  for u in ${STOP_UNITS[@]+"${STOP_UNITS[@]}"}; do
    if systemctl is-active --quiet "$u"; then
      echo "  stopping $u"
      systemctl stop "$u"
      if [ "$keep_stopped" -eq 1 ]; then
        left_stopped+=("$u")
      else
        restarts+=("$u")
      fi
    fi
  done

  for row in ${PATH_ROWS[@]+"${PATH_ROWS[@]}"}; do
    IFS=$'\t' read -r from to owner <<<"$row"
    echo "  restoring $from -> $to"
    # No --delete, ever: it would remove anything in the target that is not in the
    # snapshot, which on a live host is indistinguishable from data loss.
    if restic restore "$snap:$from" --target "$to" --sparse; then
      if [ -n "$owner" ]; then
        # Recursive on purpose: systemd-tmpfiles `d` rules re-assert the top-level
        # directory's ownership on every activation but never touch its contents, so a
        # shallow chown leaves a correct-looking directory full of wrongly-owned files.
        chown -R "$owner" "$to"
      fi
      results+=("ok    $g  $to")
    else
      results+=("FAIL  $g  $to")
      status=1
    fi
  done

  for u in ${restarts[@]+"${restarts[@]}"}; do
    echo "  starting $u"
    systemctl start "$u" || status=1
  done
done

echo
printf '%s\n' ${results[@]+"${results[@]}"}
echo
echo "Left stopped on purpose: ${left_stopped[*]}"
echo "Verify the restore, then: systemctl start ${left_stopped[*]}"
exit "$status"
