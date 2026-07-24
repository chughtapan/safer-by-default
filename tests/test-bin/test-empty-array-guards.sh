#!/usr/bin/env bash
# Regression: optional-flag arrays (REPO_FLAG, body_args, label_args,
# SAFER_RESIDUAL_ARGS) must expand safely when empty. On bash 3.2 under
# `set -u`, expanding an empty array as "${arr[@]}" aborts with
# "unbound variable"; the bin scripts guard every such site with
# ${arr[@]+"${arr[@]}"}. Each case invokes an affected script WITHOUT its
# optional flags and asserts the abort message never surfaces.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
BIN_DIR="$PLUGIN_DIR/bin"

UNBOUND="unbound variable"

# assert_not_contains <haystack> <needle> [label] — inverse of assert_contains.
assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="${3:-not contains}"
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    echo "    FAIL ($label)"
    echo "      unexpected substring: $needle"
    echo "      actual: $haystack"
    return 1
  fi
  return 0
}

# isolated_home — a HOME staged with the minimal ~/.zapbot/config.json the
# zapbot-env helper requires. Combined with --attribute-to-user, safer-publish
# resolves to plain-gh "user" mode and reaches its dispatch (no broker).
isolated_home() {
  local h
  h=$(mktemp -d)
  mkdir -p "$h/.zapbot"
  printf '{"apiKey": "test-key"}' > "$h/.zapbot/config.json"
  echo "$h"
}

test_transition_label_no_repo() {
  # safer-transition-label sources the zapbot-env helper, which requires a
  # staged config.json; isolate HOME so the test reaches the REPO_FLAG guard.
  local home fake out rc
  home=$(isolated_home)
  fake=$(mock_gh_dir 0 "")
  out=$(HOME="$home" PATH="$fake:$PATH" "$BIN_DIR/safer-transition-label" \
    --issue 1 --from a --to b 2>&1); rc=$?
  rm -rf "$fake" "$home"
  assert_not_contains "$out" "$UNBOUND" "no unbound-variable abort" || return 1
  assert_zero "$rc" "empty REPO_FLAG → exit 0" || return 1
  assert_contains "$out" "TRANSITIONED" "transition succeeds"
}

test_load_context_no_repo() {
  local fake out rc
  fake=$(mock_gh_dir 0 '{"number":1,"title":"t","body":"","labels":[],"comments":[],"state":"OPEN","url":"u"}')
  out=$(PATH="$fake:$PATH" "$BIN_DIR/safer-load-context" --issue 1 2>&1); rc=$?
  rm -rf "$fake"
  assert_not_contains "$out" "$UNBOUND" "no unbound-variable abort" || return 1
  assert_zero "$rc" "empty REPO_FLAG → exit 0"
}

test_diff_scope_no_repo() {
  local fake out rc
  fake=$(mock_gh_dir 0 'diff --git a/x b/x')
  out=$(PATH="$fake:$PATH" "$BIN_DIR/safer-diff-scope" --pr 1 2>&1); rc=$?
  rm -rf "$fake"
  assert_not_contains "$out" "$UNBOUND" "no unbound-variable abort" || return 1
  assert_zero "$rc" "empty REPO_FLAG on --pr path → exit 0"
}

test_publish_residual_args_guard() {
  # Only an identity flag: SAFER_RESIDUAL_ARGS ends up empty and is expanded
  # at `set -- ...` before arg validation runs.
  local home out rc
  home=$(isolated_home)
  out=$(HOME="$home" "$BIN_DIR/safer-publish" --attribute-to-user 2>&1); rc=$?
  rm -rf "$home"
  assert_not_contains "$out" "$UNBOUND" "empty SAFER_RESIDUAL_ARGS guarded" || return 1
  # Missing --kind is the expected failure here, not an array abort.
  assert_nonzero "$rc" "missing --kind still errors"
}

test_publish_issue_create_no_repo_no_labels() {
  local home fake out rc
  home=$(isolated_home)
  fake=$(mock_gh_dir 0 'https://github.com/o/r/issues/1')
  out=$(HOME="$home" PATH="$fake:$PATH" "$BIN_DIR/safer-publish" \
    --attribute-to-user --kind issue --title T --body B 2>&1); rc=$?
  rm -rf "$fake" "$home"
  assert_not_contains "$out" "$UNBOUND" "empty REPO_FLAG/label_args guarded" || return 1
  assert_zero "$rc" "issue create without --repo/--label → exit 0"
}

test_publish_comment_no_repo_no_body() {
  local home fake out rc
  home=$(isolated_home)
  fake=$(mock_gh_dir 0 'https://github.com/o/r/issues/5#comment')
  out=$(HOME="$home" PATH="$fake:$PATH" "$BIN_DIR/safer-publish" \
    --attribute-to-user --kind comment --issue 5 2>&1); rc=$?
  rm -rf "$fake" "$home"
  assert_not_contains "$out" "$UNBOUND" "empty REPO_FLAG/body_args guarded" || return 1
  assert_zero "$rc" "comment without --repo/--body → exit 0"
}

run_test "safer-transition-label: no --repo → no unbound abort" test_transition_label_no_repo
run_test "safer-load-context: no --repo → no unbound abort" test_load_context_no_repo
run_test "safer-diff-scope: --pr without --repo → no unbound abort" test_diff_scope_no_repo
run_test "safer-publish: empty residual args → no unbound abort" test_publish_residual_args_guard
run_test "safer-publish: issue create without --repo/--label → no unbound abort" test_publish_issue_create_no_repo_no_labels
run_test "safer-publish: comment without --repo/--body → no unbound abort" test_publish_comment_no_repo_no_body
report
