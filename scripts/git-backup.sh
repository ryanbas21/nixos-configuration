#!/usr/bin/env bash
set -euo pipefail

# The repo root defaults to the parent of this script's own directory
# (the script lives at <repo>/scripts/git-backup.sh); pass a checkout
# path as $1 to back up a different clone.
REPO="${1:-$(cd "$(dirname "$(realpath "$0")")/.." && pwd)}"

cd "$REPO"

# Don't do anything if there are no changes.
if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    exit 0
fi

# The timer is Persistent=true, so it fires the moment the machine boots
# — possibly before DNS is up. Wait (up to 5 min) instead of failing.
for _ in $(seq 1 30); do
    getent hosts github.com >/dev/null 2>&1 && break
    sleep 10
done

git add -A

git commit -m "Automated NixOS config backup"

# Another machine may have pushed in the meantime; rebase our automated
# commit on top instead of letting the push fail on a diverged remote.
git pull --rebase --autostash

git push

