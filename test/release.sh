# Tests for how a merge build is numbered and published: the script the
# publish workflow runs, and the workflow's own text. Sourced by test/run.sh.

NEXT_VERSION=$ROOT/.github/scripts/merge-build-version.sh
WORKFLOW=$ROOT/.github/workflows/publish.yml

# git in the throwaway package, as someone with a name: HOME is empty here.
pkg_git() { git -C "$TMP/pkg" -c user.name=t -c user.email=t@t "$@"; }

# Commit package.json at version $1 and tag it v$1, the way `npm version`
# does. `untagged` as $2 leaves the tag out.
bump_to() {
  printf '{ "name": "x", "version": "%s" }\n' "$1" > "$TMP/pkg/package.json"
  pkg_git add package.json
  pkg_git commit -q -m "$1"
  [ "${2:-}" = untagged ] || pkg_git tag -m "$1" "v$1"
}

# A repo at $TMP/pkg released at version $1.
release_repo() { git init -q -b main "$TMP/pkg"; bump_to "$@"; }

more_commits() {
  local i
  for i in $(seq "$1"); do pkg_git commit -q --allow-empty -m "change $i"; done
}

# Fail unless the script refuses the package and names $1 on stderr.
refuses_naming() {
  local out
  out=$("$NEXT_VERSION" "$TMP/pkg" 2>"$TMP/err") && fail "exited zero ($1)"
  [ -z "$out" ] || fail "printed a version anyway: $out"
  grep -qF -- "$1" "$TMP/err" || fail "did not name $1: $(cat "$TMP/err")"
}

merge_build_at_the_release_commit_is_next_0() {
  release_repo 0.4.0
  # No argument, from the repo's root: how the workflow runs it.
  local got; got=$(cd "$TMP/pkg" && "$NEXT_VERSION")
  [ "$got" = 0.4.1-next.0 ] || fail "got '$got'"
}

merge_build_counts_commits_since_the_tag() {
  release_repo 0.4.0
  more_commits 3
  local got; got=$("$NEXT_VERSION" "$TMP/pkg")
  [ "$got" = 0.4.1-next.3 ] || fail "got '$got'"
}

merge_build_counts_a_merged_branch_as_git_describe_does() {
  release_repo 0.4.0
  pkg_git checkout -q -b feat/x
  more_commits 2
  pkg_git checkout -q main
  pkg_git merge -q --no-ff -m "Merge pull request #1" feat/x
  # v0.4.0-3-g<hash>: the branch's two commits and the merge.
  local described got
  described=$(pkg_git describe --tags --long | cut -d- -f2)
  [ "$described" = 3 ] || fail "git describe counts $described, expected 3"
  got=$("$NEXT_VERSION" "$TMP/pkg")
  [ "$got" = "0.4.1-next.$described" ] || fail "got '$got'"
}

merge_build_counts_from_the_tag_package_json_names() {
  release_repo 0.3.0
  more_commits 2
  bump_to 0.4.0
  more_commits 1
  local got; got=$("$NEXT_VERSION" "$TMP/pkg")
  [ "$got" = 0.4.1-next.1 ] || fail "got '$got'"
}

merge_build_adds_one_as_a_number() {
  release_repo 1.9.9
  more_commits 10
  local got; got=$("$NEXT_VERSION" "$TMP/pkg")
  [ "$got" = 1.9.10-next.10 ] || fail "got '$got'"
}

merge_build_fails_without_the_release_tag() {
  release_repo 0.4.0 untagged
  refuses_naming v0.4.0
}

merge_build_refuses_a_version_that_is_not_a_release() {
  release_repo 0.4.1-next.2
  refuses_naming 0.4.1-next.2
  bump_to 0.4
  refuses_naming 0.4
  echo '{ "name": "x" }' > "$TMP/pkg/package.json"
  refuses_naming package.json
}

CASES="merge_build_at_the_release_commit_is_next_0
  merge_build_counts_commits_since_the_tag
  merge_build_counts_a_merged_branch_as_git_describe_does
  merge_build_counts_from_the_tag_package_json_names
  merge_build_adds_one_as_a_number
  merge_build_fails_without_the_release_tag
  merge_build_refuses_a_version_that_is_not_a_release"
