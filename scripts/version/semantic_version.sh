#!/usr/bin/env bash
#
# semantic_version.sh - cut the next semantic version tag (vMAJOR.MINOR.PATCH)
# from the Conventional Commits since the last semver tag.
#
# Bump rules (highest wins):
#   BREAKING CHANGE: in body, or a type with "!" (feat!:, fix(api)!:) -> major
#   feat:                                                           -> minor
#   fix:, perf:                                                     -> patch
#   anything else                                                   -> no release
#
# Tags that are not semver (v1, v2, ...) are ignored, so this can coexist with
# simple_version.sh.
#
# Usage:
#   semantic_version.sh [--dry-run] [--no-push] [--remote <name>] [--prefix <str>]
#
# Environment overrides: REMOTE, PREFIX.

set -euo pipefail

REMOTE="${REMOTE:-origin}"
PREFIX="${PREFIX:-v}"
DRY_RUN=0
PUSH=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --no-push) PUSH=0 ;;
        --remote)  REMOTE="$2"; shift ;;
        --prefix)  PREFIX="$2"; shift ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

# Latest semver tag reachable from HEAD, e.g. v1.4.2. Empty if none.
semver_re="^${PREFIX}[0-9]+\.[0-9]+\.[0-9]+$"
last_tag="$(git tag --merged HEAD --sort=-v:refname | grep -E "$semver_re" | head -n1 || true)"

if [[ -n "$last_tag" ]]; then
    range="${last_tag}..HEAD"
    IFS=. read -r major minor patch <<< "${last_tag#"$PREFIX"}"
else
    range="HEAD"
    major=0; minor=1; patch=0
fi

# Collect the bump level from every commit in the range.
bump=0   # 0 none, 1 patch, 2 minor, 3 major
re_breaking='^[a-z]+(\([^)]*\))?!:'
re_feat='^feat(\([^)]*\))?:'
re_fix='^(fix|perf)(\([^)]*\))?:'
while IFS= read -r -d $'\x1e' record; do
    [[ -z "${record//[$'\n\r ']/}" ]] && continue
    subject="${record%%$'\n'*}"
    body="${record#*$'\n'}"
    if [[ "$subject" =~ $re_breaking ]] || grep -q '^BREAKING CHANGE:' <<< "$body"; then
        level=3
    elif [[ "$subject" =~ $re_feat ]]; then
        level=2
    elif [[ "$subject" =~ $re_fix ]]; then
        level=1
    else
        level=0
    fi
    (( level > bump )) && bump=$level
done < <(git log --format='%s%n%b%x1e' "$range")

if [[ $bump -eq 0 ]]; then
    echo "no releasable commits since ${last_tag:-the beginning} - nothing to tag"
    exit 0
fi

# A first release stays at 0.1.0 unless a breaking change moves it to 1.0.0.
if [[ -z "$last_tag" && $bump -eq 3 ]]; then
    major=1; minor=0; patch=0
elif [[ -z "$last_tag" ]]; then
    : # keep 0.1.0
else
    case $bump in
        3) major=$((major+1)); minor=0; patch=0 ;;
        2) minor=$((minor+1)); patch=0 ;;
        1) patch=$((patch+1)) ;;
    esac
fi

next="${PREFIX}${major}.${minor}.${patch}"
if git rev-parse -q --verify "refs/tags/$next" >/dev/null; then
    echo "tag $next already exists" >&2
    exit 1
fi

case $bump in 3) kind=major ;; 2) kind=minor ;; *) kind=patch ;; esac
echo "next release: $next ($kind, from ${last_tag:-no semver tag})"

if [[ $DRY_RUN -eq 1 ]]; then
    echo "dry run - no tag created"
    exit 0
fi

git tag -a "$next" -m "Release $next"
echo "tagged $next"
if [[ $PUSH -eq 1 ]]; then
    git push "$REMOTE" "$next"
    echo "pushed $next to $REMOTE"
fi
