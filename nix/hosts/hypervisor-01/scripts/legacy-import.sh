# shellcheck shell=bash
# legacy-import — copy legacy production's /mnt/storage groups off its two data disks.
# Wrapped by ../legacy-import.nix, which sets MANIFEST (the groups, disks and paths).
# Run as root, in screen: the media alone is ~10.6 TB.

usage() {
  cat <<'EOF'
Usage: legacy-import --list
       legacy-import --check  [--sources DIR[,DIR...]] [--target DIR] (--all | GROUP...)
       legacy-import [--dry-run] [--sources DIR[,DIR...]] [--target DIR] (--all | GROUP...)
       legacy-import --unmount

  --list           every group: what this tool copies, and what only prod-import has
  --check          per path: which disk holds it and how big it is, files present on
                   both disks, and whether bulk has room. Copies nothing.
  --dry-run        what rsync would copy, without copying
  --all            every group this tool copies, media last
  --sources        read from these directories instead of mounting the data disks
                   (each one laid out like a legacy /mnt/diskN); for the rehearsal
  --target         write under DIR instead of apps-01's bulk export; for the rehearsal
  --unmount        unmount the data disks and exit

Copies with rsync -aHAX --numeric-ids, then owns each target as prod-import does. Never
deletes anything in a target, and re-running resumes where a run stopped. The disks are
mounted read-only.
EOF
}

mode=run
dry_run=0
all=0
sources_arg=""
target=""
groups=()
while [ $# -gt 0 ]; do
  case "$1" in
    --list) mode=list ;;
    --check) mode=check ;;
    --unmount) mode=unmount ;;
    --dry-run) dry_run=1 ;;
    --all) all=1 ;;
    --sources)
      [ $# -ge 2 ] || { usage >&2; exit 2; }
      sources_arg=$2
      shift
      ;;
    --target)
      [ $# -ge 2 ] || { usage >&2; exit 2; }
      target=${2%/}
      shift
      ;;
    -h | --help) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) groups+=("$1") ;;
  esac
  shift
done

bulk_root=$(jq -r '.bulkRoot' "$MANIFEST")
mount_root=$(jq -r '.mountRoot' "$MANIFEST")

if [ "$mode" = list ]; then
  echo "Copied by legacy-import, off the data disks (in --all order):"
  while IFS=$'\t' read -r g loc; do
    if [ "$loc" = null ]; then fb="disks only: in no restic location"; else fb="fallback: prod-import $g"; fi
    printf '  %-20s %s\n' "$g" "$fb"
    jq -r --arg g "$g" '.groups[$g].rows[] | "      /mnt/storage/\(.from) -> \(.to)  \(.owner)"' "$MANIFEST"
  done < <(jq -r '.order[] as $g | "\($g)\t\(.groups[$g].location)"' "$MANIFEST")
  echo
  echo "From the legacy boot SSD, so only in restic (prod-import on apps-01):"
  jq -r '.prodImportOnly[] | "  \(.)"' "$MANIFEST"
  exit 0
fi

[ "$(id -u)" -eq 0 ] || { echo "Run as root." >&2; exit 1; }

if [ "$mode" = unmount ]; then
  while read -r name; do
    mp="$mount_root/$name"
    if mountpoint -q "$mp"; then umount "$mp" && echo "unmounted $mp"; fi
  done < <(jq -r '.disks[].name' "$MANIFEST")
  exit 0
fi

if [ "$all" -eq 1 ]; then
  mapfile -t groups < <(jq -r '.order[]' "$MANIFEST")
fi
[ "${#groups[@]}" -gt 0 ] || { usage >&2; exit 2; }
for g in "${groups[@]}"; do
  if ! jq -e --arg g "$g" '.groups | has($g)' "$MANIFEST" >/dev/null; then
    if jq -e --arg g "$g" '.prodImportOnly | index($g)' "$MANIFEST" >/dev/null; then
      echo "$g comes from the legacy boot SSD: only prod-import has it (on apps-01)." >&2
    else
      echo "Unknown group: $g (see --list)" >&2
    fi
    exit 2
  fi
done

# The rows' targets are under bulk_root; --target moves them elsewhere.
dest_root=${target:-$bulk_root}
# Created up front even for --check and --dry-run (empty, harmless), so the pool check
# below has a real path to resolve.
if [ -n "$target" ]; then
  mkdir -p "$target"
fi

# Refuse to write anywhere but the bulk pool: if it were not mounted, the copy would
# silently fill the root filesystem.
bulk_mnt=$(findmnt -no TARGET -T "$dest_root" 2>/dev/null || true)
if [ -z "$bulk_mnt" ] || [ "$bulk_mnt" = / ]; then
  echo "$dest_root is not on a mounted pool (it resolves to '${bulk_mnt:-nothing}'). Is /mnt/bulk mounted?" >&2
  exit 1
fi

sources=()
if [ -n "$sources_arg" ]; then
  IFS=, read -ra sources <<<"$sources_arg"
  for s in "${sources[@]}"; do
    [ -d "$s" ] || { echo "No such directory: $s" >&2; exit 1; }
  done
else
  while IFS=$'\t' read -r name device; do
    mp="$mount_root/$name"
    if ! mountpoint -q "$mp"; then
      [ -e "$device" ] || { echo "Data disk $name not found: $device" >&2; exit 1; }
      mkdir -p "$mp"
      mount -o ro "$device" "$mp"
      echo "mounted $device read-only on $mp"
    fi
    if ! findmnt -no OPTIONS "$mp" | tr , '\n' | grep -qx ro; then
      echo "$mp is mounted read-write; refusing. Remount it read-only first." >&2
      exit 1
    fi
    sources+=("$mp")
  done < <(jq -r '.disks[] | "\(.name)\t\(.device)"' "$MANIFEST")
  [ "${#sources[@]}" -gt 0 ] || { echo "No data disks configured on this host; use --sources." >&2; exit 1; }
fi

rows_of() {
  jq -r --arg g "$1" --arg b "$bulk_root" --arg d "$dest_root" \
    '.groups[$g].rows[] | "\(.from)\t\($d + (.to | ltrimstr($b)))\t\(.owner)"' "$MANIFEST"
}

if [ "$mode" = check ]; then
  total=0
  for g in "${groups[@]}"; do
    echo "== $g"
    while IFS=$'\t' read -r from to owner; do
      echo "  /mnt/storage/$from -> $to"
      present=()
      for s in "${sources[@]}"; do
        if [ -e "$s/$from" ]; then
          bytes=$(du -sb "$s/$from" | cut -f1)
          total=$((total + bytes))
          present+=("$s/$from")
          echo "    on $s: $(numfmt --to=iec "$bytes")"
        fi
      done
      if [ "${#present[@]}" -eq 0 ]; then
        echo "    NOT FOUND on any disk"
      elif [ "${#present[@]}" -gt 1 ]; then
        # mergerfs puts each file on one disk; a path on both would be overwritten by
        # the second copy. Listed so it can be looked at before the run.
        dups=$(comm -12 \
          <(cd "${present[0]}" && find . -type f | sort) \
          <(cd "${present[1]}" && find . -type f | sort) | wc -l)
        if [ "$dups" -gt 0 ]; then
          echo "    WARNING: $dups file(s) exist on both disks; the copy from the last disk wins:"
          comm -12 \
            <(cd "${present[0]}" && find . -type f | sort) \
            <(cd "${present[1]}" && find . -type f | sort) | head -n 10 | sed 's/^/      /'
        fi
      fi
    done < <(rows_of "$g")
  done
  avail=$(df --output=avail -B1 "$dest_root" | tail -n 1 | tr -d ' ')
  echo
  echo "To copy: $(numfmt --to=iec "$total"). Free on $dest_root: $(numfmt --to=iec "$avail")."
  if [ "$total" -gt "$avail" ]; then
    echo "NOT ENOUGH ROOM."
    exit 1
  fi
  exit 0
fi

results=()
status=0
for g in "${groups[@]}"; do
  echo "== $g"
  location=$(jq -r --arg g "$g" '.groups[$g].location' "$MANIFEST")
  while IFS=$'\t' read -r from to owner; do
    ok=1
    found=0
    for s in "${sources[@]}"; do
      [ -e "$s/$from" ] || continue
      found=1
      echo "  $s/$from -> $to"
      args=(-aHAX --numeric-ids --info=progress2)
      [ -n "$owner" ] && args+=("--chown=$owner")
      [ "$dry_run" -eq 1 ] && args+=(--dry-run)
      [ "$dry_run" -eq 1 ] || mkdir -p "$to"
      if ! rsync "${args[@]}" "$s/$from/" "$to/"; then
        ok=0
      fi
    done
    if [ "$found" -eq 0 ]; then
      ok=0
      echo "  /mnt/storage/$from: not found on any disk"
    fi
    if [ "$ok" -eq 1 ]; then
      results+=("ok    $g  $to")
    else
      status=1
      if [ "$location" = null ]; then
        results+=("FAIL  $g  $to  (disks only, no restic fallback: fix and re-run legacy-import $g)")
      else
        results+=("FAIL  $g  $to  (fallback, on apps-01: prod-import $g)")
      fi
    fi
  done < <(rows_of "$g")
done

echo
printf '%s\n' "${results[@]}"
exit "$status"
