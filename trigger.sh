#!/usr/bin/env bash
set -euo pipefail

# --- Settings ---
REMOTE=${REMOTE:-origin}
BRANCH=${BRANCH:-main}
FILE="helm/flaskapp/values.yaml"

# --- Guards ---
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "Not inside a git repo"; exit 1;
}

# Ensure we are on the target branch and up to date BEFORE editing
git fetch "$REMOTE" --prune
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git switch -q "$BRANCH"
else
  # create local branch tracking remote if missing
  git checkout -q -B "$BRANCH" "$REMOTE/$BRANCH"
fi
git pull --rebase --autostash "$REMOTE" "$BRANCH"

# --- Make a tiny, harmless change to trigger CI ---
printf "# trigger %s\n" "$(date)" >> "$FILE"

# Stage & commit
git add "$FILE"
# If nothing to commit, exit gracefully
if git diff --cached --quiet; then
  echo "Nothing to commit."
else
  git commit -m "chore(helm): trigger helm publish"
fi

# --- Push logic ---
# Prefer the user's 'git spush' alias if it exists; otherwise do a safe push with fallback
if git config --get alias.spush >/dev/null 2>&1; then
  # Uses your pre-defined alias that fetches/rebases and pushes with lease
  git spush
else
  # Try a normal push first
  if ! git push "$REMOTE" "HEAD:$BRANCH"; then
    echo "Regular push rejected; rebasing and pushing with lease..."
    git pull --rebase --autostash "$REMOTE" "$BRANCH"
    git push --force-with-lease "$REMOTE" "HEAD:$BRANCH"
  fi
fi

echo "Trigger pushed successfully."

