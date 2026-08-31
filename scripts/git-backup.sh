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

git add -A

git commit -m "Automated NixOS config backup"

git push

