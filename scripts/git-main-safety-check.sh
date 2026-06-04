#!/usr/bin/env bash
set -euo pipefail

# Git safety check script to ensure we're on main branch, clean, and in sync with upstream before running infra actions.
# Usage: git-main-safety-check.sh [warn|enforce]

# In "warn" mode (default), it will print warnings but allow execution. In "enforce" mode, it will exit with error if checks fail.
MODE="${1:-warn}"
# To avoid excessive network calls in "warn" mode (e.g. when used in direnv shellHook), we throttle git fetch to at most once per FETCH_TTL_SECONDS.
FETCH_TTL_SECONDS="${GIT_SAFETY_FETCH_TTL_SECONDS:-300}"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

print_warning() {
  echo
  echo -e "${RED}${BOLD}================================ GIT SAFETY WARNING ================================${NC}"
  printf '%b\n' "$1"
  echo -e "${RED}${BOLD}=====================================================================================${NC}"
  echo
}

print_info() {
  echo -e "${YELLOW}$1${NC}"
}

print_ok() {
  echo -e "${GREEN}$1${NC}"
}

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  exit 0
fi

git_dir="$(git rev-parse --git-dir)"

if [ -d "$git_dir/rebase-merge" ]; then
  print_info "Git rebase in progress: skipping automatic sync checks."
  exit 0
fi

if [ -d "$git_dir/rebase-apply" ]; then
  print_info "Git rebase/apply in progress: skipping automatic sync checks."
  exit 0
fi

if [ -f "$git_dir/MERGE_HEAD" ] || [ -f "$git_dir/CHERRY_PICK_HEAD" ] || [ -f "$git_dir/REVERT_HEAD" ]; then
  print_info "Git merge/cherry-pick/revert in progress: skipping automatic sync checks."
  exit 0
fi

branch="$(git symbolic-ref --short -q HEAD || echo DETACHED)"

status_porcelain="$(git status --porcelain)"
if [ -n "$status_porcelain" ]; then
  dirty=1
else
  dirty=0
fi

# In warn mode (e.g. direnv shellHook), throttle fetches to avoid network cost on every reload.
# Enforce mode always fetches to ensure the strict check uses fresh remote refs.
fetch_needed=1
fetch_stamp_file="$git_dir/git-safety-last-fetch-epoch"

if [ "$MODE" != "enforce" ]; then
  now_epoch="$(date +%s)"
  last_fetch_epoch=0

  if [ -f "$fetch_stamp_file" ]; then
    last_fetch_epoch="$(cat "$fetch_stamp_file" 2>/dev/null || echo 0)"
  fi

  case "$FETCH_TTL_SECONDS" in
    ''|*[!0-9]*)
      FETCH_TTL_SECONDS=300
      ;;
  esac

  case "$last_fetch_epoch" in
    ''|*[!0-9]*)
      last_fetch_epoch=0
      ;;
  esac

  if [ "$last_fetch_epoch" -gt 0 ] && [ $((now_epoch - last_fetch_epoch)) -lt "$FETCH_TTL_SECONDS" ]; then
    fetch_needed=0
  fi
fi

if [ "$fetch_needed" -eq 1 ]; then
  # Keep this non-disruptive: fetch only updates remote refs and does not touch worktree/history.
  git fetch --quiet --prune || true

  if [ "$MODE" != "enforce" ]; then
    printf '%s\n' "${now_epoch:-$(date +%s)}" > "$fetch_stamp_file" 2>/dev/null || true
  fi
fi

upstream=""
if upstream_ref="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"; then
  upstream="$upstream_ref"
fi

behind=0
ahead=0
if [ -n "$upstream" ]; then
  behind="$(git rev-list --count HEAD.."$upstream" 2>/dev/null || echo 0)"
  ahead="$(git rev-list --count "$upstream"..HEAD 2>/dev/null || echo 0)"
fi

messages=()
if [ "$branch" != "main" ]; then
  messages+=("- Current branch is '$branch' (expected 'main' for infra runs).")
fi
if [ "$dirty" -eq 1 ]; then
  messages+=("- Working tree has local changes (tracked or untracked files).")
fi
if [ "$ahead" -gt 0 ]; then
  messages+=("- You have $ahead local commit(s) not pushed to upstream.")
fi
if [ -n "$upstream" ] && [ "$behind" -gt 0 ]; then
  messages+=("- Branch is behind $upstream by $behind commit(s).")
fi
if [ -z "$upstream" ]; then
  messages+=("- No upstream branch configured for current HEAD.")
fi

if [ "${#messages[@]}" -eq 0 ]; then
  if [ "$MODE" = "enforce" ]; then
    print_ok "Git safety check passed: branch is clean and up to date."
  fi
  exit 0
fi

warning_body="Please review repository state before running infrastructure actions:\n"
for msg in "${messages[@]}"; do
  warning_body+="$msg\\n"
done
warning_body+="\nHelpful commands:\n"
warning_body+="- git status\n"
warning_body+="- git switch main\n"
warning_body+="- git pull --ff-only\n"
warning_body+="- git push\n"

if [ "$MODE" = "enforce" ] && [ "${ALLOW_UNSAFE_ANSIBLE_RUN:-0}" != "1" ]; then
  warning_body+="\nTo bypass once (not recommended): ALLOW_UNSAFE_ANSIBLE_RUN=1 just ansible-playbook ..."
  print_warning "$warning_body"
  exit 1
fi

print_warning "$warning_body"
exit 0
