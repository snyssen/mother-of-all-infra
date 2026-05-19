#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-warn}"

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

if [ -n "$(git rev-parse --git-path rebase-merge 2>/dev/null || true)" ] && [ -d "$(git rev-parse --git-path rebase-merge)" ]; then
  print_info "Git rebase in progress: skipping automatic sync checks."
  exit 0
fi

if [ -n "$(git rev-parse --git-path rebase-apply 2>/dev/null || true)" ] && [ -d "$(git rev-parse --git-path rebase-apply)" ]; then
  print_info "Git rebase/apply in progress: skipping automatic sync checks."
  exit 0
fi

if [ -f "$(git rev-parse --git-path MERGE_HEAD)" ] || [ -f "$(git rev-parse --git-path CHERRY_PICK_HEAD)" ] || [ -f "$(git rev-parse --git-path REVERT_HEAD)" ]; then
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

# Keep this non-disruptive: fetch only updates remote refs and does not touch worktree/history.
git fetch --quiet --prune || true

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
