#!/usr/bin/env bash
set -Eeuo pipefail

# Usage: ./sync-and-push.sh [branch]
BRANCH="${1:-main}"
CHART_PATH="helm/flaskapp/Chart.yaml"

# 1) Ensure we are inside a git repo
git rev-parse --is-inside-work-tree >/dev/null

echo "== Sync with origin/$BRANCH =="

# 2) Fetch latest refs
git fetch origin

# 3) Commit any uncommitted local changes
if [[ -n "$(git status --porcelain)" ]]; then
  echo ">> Local changes detected – committing them"
  git add -A
  git commit -m "chore: local sync via sync-and-push"
fi

# 4) Rebase on top of origin/BRANCH
echo "== Rebase on top of origin/$BRANCH =="
if ! git pull --rebase --autostash origin "$BRANCH"; then
  echo "!! Rebase reported conflicts. Trying to resolve $CHART_PATH by keeping LOCAL (ours)…"
  # If Chart.yaml is conflicted – keep the local version (ours)
  if git ls-files -u | awk '{print $4}' | grep -xq "$CHART_PATH"; then
    git checkout --ours "$CHART_PATH"
    git add "$CHART_PATH"
    git rebase --continue || true
  fi
fi

# 5) Abort if conflicts remain
if [[ -n "$(git ls-files -u)" ]]; then
  echo "❌ Unresolved merge conflicts remain."
  echo "   Fix them and run: git rebase --continue"
  exit 1
fi

# 6) Push
echo "== Pushing to origin/$BRANCH =="
git push origin HEAD:"$BRANCH"

echo "✅ Done. HEAD is now at: $(git rev-parse --short=7 HEAD) on branch $(git rev-parse --abbrev-ref HEAD)"

