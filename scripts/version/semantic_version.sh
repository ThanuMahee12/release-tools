#!/usr/bin/env bash
#
# semantic_version.sh - cut the next version tag (MAJOR.MINOR.PATCH, no prefix)
# from the Conventional Commits since the last version tag.
#
# Bump rules (highest wins):
#   BREAKING CHANGE: in body, or a "!" after the type   -> major   (1.0.0, 2.0.0)
#   feat:, refactor:, chore:                            -> minor   (0.2.0 -> 0.3.0)
#   fix:, hotfix:, bugfix:, perf:                       -> patch   (0.2.0 -> 0.2.1)
#   anything else                                       -> no release
#
# Patch rolls over: when a patch bump would reach 10, the minor is bumped
# instead and the patch resets to 0 (0.2.9 + fix -> 0.3.0).
#
# Tags that are not version numbers (v1, v2, ...) are ignored, so this can
# coexist with simple_version.sh.
#
# Usage:
#   semantic_version.sh [--dry-run] [--no-push] [--remote <name>] [--prefix <str>]
#
# Environment overrides: REMOTE, PREFIX (default empty: tags look like 0.2.0).

set -euo pipefail

REMOTE="${REMOTE:-origin}"
PREFIX="${PREFIX:-}"
DRY_RUN=0
PUSH=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --no-push) PUSH=0 ;;
        --remote)  REMOTE="$2"; shift ;;
        --prefix)  PREFIX="$2"; shift ;;
        -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

# Latest version tag reachable from HEAD, e.g. 0.2.1. Empty if none.
version_re="^${PREFIX}[0-9]+\.[0-9]+\.[0-9]+$"
last_tag="$(git tag --merged HEAD --sort=-v:refname | grep -E "$version_re" | head -n1 || true)"

if [[ -n "$last_tag" ]]; then
    range="${last_tag}..HEAD"
    IFS=. read -r major minor patch <<< "${last_tag#"$PREFIX"}"
else
    range="HEAD"
    major=0; minor=1; patch=0
fi

re_breaking='^[a-z]+(\([^)]*\))?!:'
re_minor='^(feat|refactor|chore)(\([^)]*\))?:'
re_patch='^(fix|hotfix|bugfix|perf)(\([^)]*\))?:'

# Collect the bump level from every commit in the range.
bump=0   # 0 none, 1 patch, 2 minor, 3 major
while IFS= read -r -d $'\x1e' record; do
    [[ -z "${record//[$'\n\r ']/}" ]] && continue
    subject="${record%%$'\n'*}"
    body="${record#*$'\n'}"
    if [[ "$subject" =~ $re_breaking ]] || grep -q '^BREAKING CHANGE:' <<< "$body"; then
        level=3
    elif [[ "$subject" =~ $re_minor ]]; then
        level=2
    elif [[ "$subject" =~ $re_patch ]]; then
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

if [[ -z "$last_tag" ]]; then
    # First release: stays 0.1.0, or 1.0.0 if the first change is breaking.
    [[ $bump -eq 3 ]] && { major=1; minor=0; patch=0; }
else
    case $bump in
        3) major=$((major+1)); minor=0; patch=0 ;;
        2) minor=$((minor+1)); patch=0 ;;
        1) patch=$((patch+1))
           if [[ $patch -ge 10 ]]; then minor=$((minor+1)); patch=0; fi ;;
    esac
fi

next="${PREFIX}${major}.${minor}.${patch}"
if git rev-parse -q --verify "refs/tags/$next" >/dev/null; then
    echo "tag $next already exists" >&2
    exit 1
fi

case $bump in 3) kind=major ;; 2) kind=minor ;; *) kind=patch ;; esac
echo "next release: $next ($kind, from ${last_tag:-no version tag})"

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
