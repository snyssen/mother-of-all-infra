# shellcheck shell=bash
#
# Forgets every snapshot older than a cutoff, across whole repositories: Backrest's own
# snapshots and anything else written there (autorestic's, chiefly), which no plan's
# retention will ever touch.
#
# Spliced into a writeShellApplication by forget.nix, exactly like restore.sh: no
# shebang, no `set` line, and everything the Nix config knows arrives in the JSON
# manifest at $MANIFEST. $HOME is pre-set to Backrest's own restic cache directory.
#
# The manifest's shape:
#   { "command": "<name>",
#     "repos": { "<repo>": { "uri":…, "passwordFile":…, "env": {VAR: file} } } }

CMD="$(jq -r '.command' "$MANIFEST")"
mapfile -t ALL_REPOS < <(jq -r '.repos | keys[]' "$MANIFEST")

usage() {
  cat <<EOF
Usage: $CMD --before WHEN [options]

Forgets every snapshot taken before WHEN, whoever made it, in: ${ALL_REPOS[*]}

Forgetting frees no space by itself; the repository's scheduled prune does that.

  --before WHEN     the cutoff. Accepts anything date(1) understands: 2026-07-01,
                    "2026-07-01 14:00", "6 months ago". A bare date means the *start*
                    of that day, so --before 2026-07-01 keeps everything from the 1st.
  --tag TAG         only consider snapshots with TAG; passed to restic as-is:
                      --tag ar:location:nextcloud
                          snapshots tagged ar:location:nextcloud
                      --tag ar:location:nextcloud --tag ar:location:tv
                          tagged either one (repeating the flag ORs)
                      --tag plan:photos,created-by:apps-01
                          tagged both (a comma inside one flag ANDs)
  --host HOST       only consider snapshots from HOST (e.g. snyssen.be)
  --dry-run         list what would be forgotten, change nothing
  -y, --yes         skip the confirmation prompt
EOF
}

# The same repo-id -> credentials mapping restore.sh uses, from this manifest instead.
load_repo_env() {
  local r="$1" pair
  RESTIC_REPOSITORY="$(jq -r --arg r "$r" '.repos[$r].uri' "$MANIFEST")"
  RESTIC_PASSWORD_FILE="$(jq -r --arg r "$r" '.repos[$r].passwordFile' "$MANIFEST")"
  export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE
  while IFS= read -r pair; do
    export "${pair%%=*}=$(cat "${pair#*=}")"
  done < <(jq -r --arg r "$r" '.repos[$r].env | to_entries[] | "\(.key)=\(.value)"' "$MANIFEST")
}

# --- argument parsing ---------------------------------------------------------------

before_arg=""
filter=()
dry_run=0
assume_yes=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --before)
      [ "$#" -ge 2 ] || { echo "$CMD: --before needs a date or time" >&2; exit 2; }
      before_arg="$2"; shift ;;
    --tag|--host)
      [ "$#" -ge 2 ] || { echo "$CMD: $1 needs a value" >&2; exit 2; }
      filter+=("$1" "$2"); shift ;;
    --dry-run) dry_run=1 ;;
    -y|--yes)  assume_yes=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "$CMD: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$before_arg" ]; then
  echo "$CMD: --before is required" >&2
  usage >&2
  exit 2
fi
if ! cutoff="$(date -d "$before_arg" +%s 2>/dev/null)"; then
  echo "$CMD: could not understand --before '$before_arg'" >&2
  exit 2
fi
# A cutoff in the future forgets everything -- never what a typo meant.
if [ "$cutoff" -gt "$(date +%s)" ]; then
  echo "$CMD: --before $(date -d "@$cutoff" '+%Y-%m-%d %H:%M:%S %z') is in the future" >&2
  exit 2
fi
# Always print the instant it resolved to, as restore.sh does for --at.
echo "Forgetting snapshots taken before $(date -d "@$cutoff" '+%Y-%m-%d %H:%M:%S %z')"

if [ "$(id -u)" -ne 0 ]; then
  echo "$CMD: must run as root -- the repository passwords are root-only sops secrets" >&2
  exit 1
fi

# --- phase 1: select, per repo --------------------------------------------------------

declare -A forget_ids=()
total=0

for r in "${ALL_REPOS[@]}"; do
  load_repo_env "$r"
  echo
  echo "$r ($RESTIC_REPOSITORY):"

  snapjson="$(restic snapshots --no-lock --json ${filter[@]+"${filter[@]}"})"
  # "<epoch>\t<id>\t<time>\t<host>\t<tags>", oldest first. Epochs via date(1), for the
  # reason restore.sh gives: restic's RFC3339 with nanoseconds defeats jq's date
  # parsing, and comparing the strings would misorder snapshots across a DST change.
  snaptable="$(
    paste \
      <(jq -r '.[].time' <<<"$snapjson" | date -f - +%s) \
      <(jq -r '.[] | [.id, .time[0:19], .hostname, (.tags // [] | join(","))] | @tsv' <<<"$snapjson") \
    | sort -n
  )"

  selection="$(awk -F'\t' -v c="$cutoff" '$1 < c' <<<"$snaptable")"
  ids="$(cut -f2 <<<"$selection")"
  n="$(grep -c . <<<"$ids" || true)"

  if [ "$n" -eq 0 ]; then
    echo "  nothing before the cutoff"
  else
    awk -F'\t' '{ printf "  %s  %s  %-12s %s\n", substr($2, 1, 8), $3, $4, $5 }' <<<"$selection"
    forget_ids["$r"]="$ids"
  fi
  total=$(( total + n ))
done

echo
echo "$total snapshot(s) to forget."
if [ "$total" -eq 0 ]; then
  exit 0
fi
if [ "$dry_run" -eq 1 ]; then
  echo "$CMD: --dry-run, nothing forgotten."
  exit 0
fi
if [ "$assume_yes" -ne 1 ]; then
  read -r -p "Forget the above? This cannot be undone. [y/N] " reply
  case "$reply" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Aborted."; exit 1 ;;
  esac
fi

# --- phase 2: forget --------------------------------------------------------------------
# forget needs an exclusive lock, so it waits out a running backup, check or prune
# rather than failing outright. xargs batches the ids, so no command line overflows.

status=0
for r in "${!forget_ids[@]}"; do
  load_repo_env "$r"
  echo
  echo "Forgetting in $r..."
  if ! xargs restic forget --retry-lock 30m <<<"${forget_ids[$r]}"; then
    echo "$CMD: forget FAILED in $r" >&2
    status=1
  fi
done

echo
echo "Space comes back with each repository's next scheduled prune, or one started from"
echo "its page in Backrest. Backrest's snapshot list catches up when it next indexes the repo."
exit "$status"
