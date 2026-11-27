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

# How it really happens: a release commit pushed without --follow-tags. The
# older tags are there, and counting from one of them would number the build
# as if the release had not happened.
merge_build_does_not_count_from_an_older_tag() {
  release_repo 0.3.0
  more_commits 2
  bump_to 0.4.0 untagged
  refuses_naming v0.4.0
}

# With the history cut short, the count stops where the clone does.
merge_build_fails_on_a_shallow_clone() {
  release_repo 0.4.0
  more_commits 3
  mv "$TMP/pkg" "$TMP/full"
  git clone -q --depth 1 "file://$TMP/full" "$TMP/pkg"
  pkg_git fetch -q --depth 1 origin 'refs/tags/v0.4.0:refs/tags/v0.4.0'
  refuses_naming shallow
}

merge_build_refuses_a_version_that_is_not_a_release() {
  release_repo 0.4.1-next.2
  refuses_naming 0.4.1-next.2
  bump_to 0.4
  refuses_naming 0.4
  echo '{ "name": "x" }' > "$TMP/pkg/package.json"
  refuses_naming 'has no version'
}

# npm never writes one, and bash would read 010 as eight.
merge_build_refuses_a_number_with_a_leading_zero() {
  release_repo 1.2.010
  refuses_naming 1.2.010
  bump_to 1.2.08
  refuses_naming 1.2.08
  bump_to 01.2.3
  refuses_naming 01.2.3
}

# --- next never moves backwards ---------------------------------------------

FORWARD=$ROOT/.github/scripts/next-moves-forward.sh

# A stand-in for npm that answers the two questions the script asks the
# registry, the way the registry answers them. `npm view <name>
# dist-tags.next` prints the version next is on ($1), or nothing when there is
# no such tag. `npm view <name>@<version> gitHead` prints the commit that
# version was built from ($2). Every call is logged.
stub_registry() {
  cat > "$TMP/bin/npm" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$TMP/npm-calls.log"
[ "\$1" = view ] || exit 2
case \$3 in
  dist-tags.next) [ -z "$1" ] || echo "$1" ;;
  gitHead) echo "$2" ;;
  *) exit 2 ;;
esac
EOF
  chmod +x "$TMP/bin/npm"
}
pkg_head() { pkg_git rev-parse HEAD; }

next_moves_forward_when_nothing_is_on_next() {
  release_repo 0.4.0
  stub_registry '' ''
  # No argument, from the repo's root: how the workflow runs it.
  (cd "$TMP/pkg" && "$FORWARD") 2>"$TMP/err" ||
    fail "refused the first merge build: $(cat "$TMP/err")"
  grep -qx 'view x dist-tags.next' "$TMP/npm-calls.log" ||
    fail "did not ask the registry which version next is on"
}

next_moves_forward_from_an_older_commit() {
  release_repo 0.4.0
  more_commits 1
  stub_registry 0.4.1-next.1 "$(pkg_head)"
  more_commits 2
  "$FORWARD" "$TMP/pkg" 2>"$TMP/err" || fail "refused a newer build: $(cat "$TMP/err")"
  grep -qx 'view x@0.4.1-next.1 gitHead' "$TMP/npm-calls.log" ||
    fail "did not ask which commit next was built from"
}

# What a re-run of an old run would do: its commit is behind the one next is on.
next_does_not_move_back_to_an_older_commit() {
  release_repo 0.4.0
  more_commits 3
  stub_registry 0.4.1-next.3 "$(pkg_head)"
  pkg_git checkout -q --detach HEAD~2
  "$FORWARD" "$TMP/pkg" >/dev/null 2>"$TMP/err" &&
    fail "let an older build replace 0.4.1-next.3"
  grep -qF '0.4.1-next.3' "$TMP/err" ||
    fail "did not name the build next is on: $(cat "$TMP/err")"
}

next_does_not_take_the_same_commit_twice() {
  release_repo 0.4.0
  more_commits 1
  stub_registry 0.4.1-next.1 "$(pkg_head)"
  "$FORWARD" "$TMP/pkg" >/dev/null 2>"$TMP/err" &&
    fail "published the commit next is already on"
  grep -qF '0.4.1-next.1' "$TMP/err" ||
    fail "did not name the build next is on: $(cat "$TMP/err")"
}

# A commit this repo does not have cannot be ahead of it. Refusing here would
# stop every merge build for good if main's history were ever rewritten.
next_moves_forward_past_a_commit_it_does_not_know() {
  release_repo 0.4.0
  stub_registry 0.4.1-next.9 0123456789abcdef0123456789abcdef01234567
  "$FORWARD" "$TMP/pkg" 2>"$TMP/err" || fail "refused: $(cat "$TMP/err")"
}

next_is_not_moved_when_the_registry_cannot_be_asked() {
  release_repo 0.4.0
  stub npm 1
  "$FORWARD" "$TMP/pkg" >/dev/null 2>&1 &&
    fail "went on without knowing where next is"
  [ -s "$TMP/npm-calls.log" ] || fail "never asked the registry"
}

# --- the workflow's own text ------------------------------------------------

# The workflow cannot be run before it is merged, so its text is pinned: the
# lines that decide what is published, when, and under which npm tag. `latest`
# is what every machine installs on its next update, so a merge build must
# never be published under it. A case here that fails after an edit to
# publish.yml is asking whether the edit was meant.

# The workflow without its comment lines.
workflow_code() { grep -v '^[[:space:]]*#' "$WORKFLOW"; }

# The top-level block that starts with the line $1, up to the next one.
workflow_block() {
  workflow_code | awk -v key="$1" '
    $0 == key { on = 1; print; next }
    on && /^[^[:space:]]/ { exit }
    on && NF'
}

# The lines of the step named $1, without their indentation.
workflow_step() {
  workflow_code | awk -v name="      - name: $1" '
    $0 == name { on = 1; print; next }
    on && /^      - / { exit }
    on' | sed 's/^[[:space:]]*//'
}

# Fail unless the step named $1 has each of the other arguments as a whole line.
step_has() {
  local step=$1 line
  shift
  for line in "$@"; do
    workflow_step "$step" | grep -qxF -- "$line" ||
      fail "the step '$step' has no line: $line"
  done
}

publish_workflow_publishes_in_two_places_only() {
  local want='run: npm publish --access public
npm publish --access public --tag next'
  [ "$(workflow_code | grep 'npm publish' | sed 's/^[[:space:]]*//')" = "$want" ] ||
    fail "the workflow's npm publish lines are not exactly these two: $want"
}

publish_workflow_runs_for_releases_and_pushes_to_main() {
  local want='on:
  release:
    types: [published]
  push:
    branches: [main]'
  [ "$(workflow_block on:)" = "$want" ] ||
    fail "the workflow's triggers are not exactly: $want"
}

# Waiting runs are kept, not dropped, so every push gets a build; and the two
# ways in wait separately, so a push never holds up or displaces a release.
publish_workflow_queues_runs_for_each_way_in() {
  local want='concurrency:
  group: publish-${{ github.event_name }}
  queue: max'
  [ "$(workflow_block concurrency:)" = "$want" ] ||
    fail "the workflow's concurrency block is not exactly: $want"
}

# Without the whole history and the tags, there is no release tag to count from.
publish_workflow_fetches_history_and_tags() {
  workflow_code | grep -Eq '^[[:space:]]+fetch-depth: 0([[:space:]]|$)' ||
    fail "the checkout does not set fetch-depth: 0"
}

publish_workflow_tests_before_it_publishes() {
  local tests publish
  tests=$(workflow_code | grep -n '^      - run: npm test$' | head -n 1 | cut -d: -f1)
  publish=$(workflow_code | grep -n 'npm publish' | head -n 1 | cut -d: -f1)
  [ -n "$tests" ] && [ -n "$publish" ] && [ "$tests" -lt "$publish" ] ||
    fail "npm test does not run, for every event, before the first npm publish"
}

publish_workflow_releases_only_a_stable_tagged_version() {
  step_has 'Check the release tag matches package.json' \
    "if: github.event_name == 'release'" \
    'if [ "v$version" != "$GITHUB_REF_NAME" ]; then' \
    '*-*) echo "$version is not a stable version; a release publishes to latest" >&2; exit 1 ;;'
  step_has 'Publish the release' \
    "if: github.event_name == 'release'" \
    'run: npm publish --access public'
}

publish_workflow_publishes_a_merge_build_only_as_next() {
  step_has 'Number the merge build' \
    "if: github.event_name == 'push'" \
    'version=$(.github/scripts/merge-build-version.sh)' \
    'npm version "$version" --no-git-tag-version'
  step_has 'Publish the merge build' \
    "if: github.event_name == 'push'" \
    '*-next.*) ;;' \
    '*) echo "Refusing to publish $version as a merge build" >&2; exit 1 ;;' \
    '.github/scripts/next-moves-forward.sh' \
    'npm publish --access public --tag next'
  # The check on next comes before the publish, not after it.
  local check publish
  check=$(workflow_step 'Publish the merge build' |
    grep -nxF '.github/scripts/next-moves-forward.sh' | cut -d: -f1)
  publish=$(workflow_step 'Publish the merge build' |
    grep -nxF 'npm publish --access public --tag next' | cut -d: -f1)
  [ -n "$check" ] && [ -n "$publish" ] && [ "$check" -lt "$publish" ] ||
    fail "next-moves-forward.sh does not run before the merge build is published"
}

CASES="merge_build_at_the_release_commit_is_next_0
  merge_build_counts_commits_since_the_tag
  merge_build_counts_a_merged_branch_as_git_describe_does
  merge_build_counts_from_the_tag_package_json_names
  merge_build_adds_one_as_a_number
  merge_build_fails_without_the_release_tag
  merge_build_does_not_count_from_an_older_tag
  merge_build_fails_on_a_shallow_clone
  merge_build_refuses_a_version_that_is_not_a_release
  merge_build_refuses_a_number_with_a_leading_zero
  next_moves_forward_when_nothing_is_on_next
  next_moves_forward_from_an_older_commit
  next_does_not_move_back_to_an_older_commit
  next_does_not_take_the_same_commit_twice
  next_moves_forward_past_a_commit_it_does_not_know
  next_is_not_moved_when_the_registry_cannot_be_asked
  publish_workflow_publishes_in_two_places_only
  publish_workflow_runs_for_releases_and_pushes_to_main
  publish_workflow_queues_runs_for_each_way_in
  publish_workflow_fetches_history_and_tags
  publish_workflow_tests_before_it_publishes
  publish_workflow_releases_only_a_stable_tagged_version
  publish_workflow_publishes_a_merge_build_only_as_next"
