#!/usr/bin/env bash
# Succeeds when publishing a merge build of the repo in $1 (the current
# directory when there is none) would move npm's `next` tag forward, and fails
# when the build `next` is on already contains this commit. That is what a
# re-run of an old run would be, or a run that started out of turn: without
# this, the older build would be published over the newer one.
# .github/workflows/publish.yml runs this just before it publishes a merge
# build.
set -euo pipefail

die() { echo "$*" >&2; exit 1; }

dir=${1:-.}
name=$(jq -r '.name // empty' "$dir/package.json")
[ -n "$name" ] || die "package.json has no name"

# npm prints nothing, and succeeds, when there is no such tag: the first merge
# build. A failure here is the registry not answering, which stops the publish.
on_next=$(npm view "$name" dist-tags.next)
[ -n "$on_next" ] || exit 0
commit=$(npm view "$name@$on_next" gitHead)
[ -n "$commit" ] || exit 0

# A commit this repo does not have cannot be ahead of this one, so only a
# plain "yes, it is an ancestor" refuses.
if git -C "$dir" merge-base --is-ancestor HEAD "$commit" 2>/dev/null; then
  die "next is on $on_next, built from $commit, which already contains this commit; not publishing an older build over it"
fi
