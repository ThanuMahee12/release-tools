#!/usr/bin/env bash
#
# simple_version.sh — cut a simple, monotonically-incrementing release tag.
#
# Versioning scheme: v1, v2, v3, ... (a single integer, no semver).
# Finds the highest existing vN tag, increments it, tags the current commit
# and pushes the tag to the remote. Semver-style tags (e.g. v0.0.17) are
# deliberately ignored so this can coexist with an older tagging scheme.
#
# Usage:
#   simple_version.sh [--remote <name>] [--prefix <str>] [--dry-run]
#
# Options / environment overrides:
#   --remote <name> | REMOTE   git remote to push to   (default: origin)
#   --prefix <str>  | PREFIX   tag prefix              (default: v)
#   --dry-run                   print the next tag but do not create/push it

set -euo pipefail

REMOTE="${REMOTE:-origin}"
PREFIX="${PREFIX:-v}"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --remote)  REMOTE="$2"; shift 2 ;;
        --prefix)  PREFIX="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1;   shift ;;
        -h|--help) grep '^#' "$0" | grep -v '^#!' | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
    esac
done

# Only consider tags of the exact form <PREFIX><integer> (e.g. v1, v2, v10).
# `grep` may match nothing (fresh repo), which would trip `pipefail`, so guard it.
LATEST_TAG=$(git tag --list "${PREFIX}[0-9]*" \
    | grep -E "^${PREFIX}[0-9]+$" \
    | sort -V \
    | tail -n 1 || true)

if [[ -z "$LATEST_TAG" ]]; then
    NEXT_VERSION=1
else
    CURRENT_VERSION="${LATEST_TAG#"$PREFIX"}"
    NEXT_VERSION=$((CURRENT_VERSION + 1))
fi

NEW_TAG="${PREFIX}${NEXT_VERSION}"

echo "Latest release : ${LATEST_TAG:-none}"
echo "New release    : $NEW_TAG"

# Preview only: report the next tag without touching the repo.
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] would create and push tag ${NEW_TAG}"
    exit 0
fi

# Refuse to tag a dirty tree.
if [[ -n "$(git status --porcelain)" ]]; then
    echo "ERROR: working tree is not clean." >&2
    exit 1
fi

# Never clobber an existing tag (e.g. a concurrent run got there first).
if git rev-parse -q --verify "refs/tags/${NEW_TAG}" >/dev/null; then
    echo "ERROR: tag ${NEW_TAG} already exists." >&2
    exit 1
fi

git tag -a "$NEW_TAG" -m "Release $NEW_TAG"
git push "$REMOTE" "$NEW_TAG"

echo "Release $NEW_TAG created successfully."
