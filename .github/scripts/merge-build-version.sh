#!/usr/bin/env bash
# Prints the npm version for a merge build of the repo in $1 (the current
# directory when there is none): X.Y.(Z+1)-next.N, where X.Y.Z is the version
# in package.json and N is the number of commits since the tag vX.Y.Z. That
# sorts above the last release and below the next one, and grows with every
# push. .github/workflows/publish.yml runs this on each push to main. The
# number is never committed.
set -euo pipefail

die() { echo "$*" >&2; exit 1; }

dir=${1:-.}
version=$(jq -r '.version // empty' "$dir/package.json")
[ -n "$version" ] || die "package.json has no version"
# Each part is 0 or has no leading zero, as semver and npm require; bash would
# also read a leading zero as octal.
part='(0|[1-9][0-9]*)'
[[ $version =~ ^$part\.$part\.$part$ ]] ||
  die "package.json version '$version' is not a release version (X.Y.Z)"
major=${BASH_REMATCH[1]} minor=${BASH_REMATCH[2]} patch=${BASH_REMATCH[3]}

# A shallow clone has only part of the history, so the count would be short.
[ "$(git -C "$dir" rev-parse --is-shallow-repository)" = false ] ||
  die "this clone is shallow, so the commits since v$version cannot all be counted; fetch the whole history (fetch-depth: 0)"

tag=refs/tags/v$version
git -C "$dir" rev-parse --quiet --verify "$tag" >/dev/null ||
  die "there is no tag v$version to count commits from; was it pushed?"
count=$(git -C "$dir" rev-list --count "$tag..HEAD")

echo "$major.$minor.$((patch + 1))-next.$count"
