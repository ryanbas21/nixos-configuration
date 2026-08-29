#!/usr/bin/env bash
set -euo pipefail

REPO="/home/batman/programming/nixos"

cd "$REPO"

# Don't do anything if there are no changes.
if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    exit 0
fi

git add -A

git commit -m "Automated NixOS config backup"

git push

