#!/usr/bin/env bash
set -Eeuo pipefail

# One-line bootstrap: downloads this repository and runs install.sh.
#
# Share this one-liner with your community:
#   curl -fsSL https://raw.githubusercontent.com/Chebaleomkar/macos-look/main/bootstrap.sh | bash
#
# To point it elsewhere, set MACOS_LOOK_REPO="owner/repo" or edit REPO_OWNER.
REPO_OWNER="${MACOS_LOOK_REPO:-Chebaleomkar/macos-look}"
BRANCH="${MACOS_LOOK_BRANCH:-main}"

if [[ "$REPO_OWNER" == *YOUR_GITHUB_USER* ]]; then
    printf 'bootstrap.sh is not configured yet.\n' >&2
    printf 'Set MACOS_LOOK_REPO="you/macos-look" or edit REPO_OWNER.\n' >&2
    exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

printf 'Downloading %s (%s)...\n' "$REPO_OWNER" "$BRANCH"
curl -fsSL --retry 3 "https://github.com/${REPO_OWNER}/archive/refs/heads/${BRANCH}.tar.gz" |
    tar -xz -C "$TMP" --strip-components=1

exec bash "$TMP/install.sh" "$@"
