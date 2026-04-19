#!/usr/bin/env bash
# Validates argument handling and key code branches with a mock gh.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
BIN="$PLUGIN_DIR/bin/safer-load-context"

test_requires_issue() {
  local rc
  "$BIN" >/dev/null 2>&1; rc=$?
  assert_nonzero "$rc" "no --issue should fail"
}

test_gh_not_installed() {
  local fake_path out rc
  fake_path=$(mktemp -d)
  ln -s "$(command -v bash)" "$fake_path/bash"
  out=$(PATH="$fake_path" "$BIN" --issue 1 2>&1); rc=$?
  rm -rf "$fake_path"
  assert_nonzero "$rc" "no gh → nonzero exit"
  assert_contains "$out" "gh not installed" "error mentions gh"
}

test_gh_failure_returns_json_error() {
  local fake out rc
  fake=$(mock_gh_dir 1 "api rate limit exceeded")
  out=$(PATH="$fake:$PATH" "$BIN" --issue 1 2>&1); rc=$?
  rm -rf "$fake"
  assert_nonzero "$rc" "gh failure → nonzero exit"
  assert_contains "$out" '"error"' "JSON error key present"
}

test_success_no_parent() {
  local fake out rc
  fake=$(mock_gh_dir 0 '{"number":42,"title":"t","body":"","labels":[],"comments":[],"state":"OPEN","url":"u"}')
  out=$(PATH="$fake:$PATH" "$BIN" --issue 42 2>&1); rc=$?
  rm -rf "$fake"
  assert_zero "$rc" "gh success → exit 0"
  assert_contains "$out" '"number"' "issue JSON present"
}

test_parent_not_found_in_body() {
  local fake out rc
  fake=$(mock_gh_dir 0 '{"number":5,"title":"t","body":"no parent ref here","labels":[],"comments":[],"state":"OPEN","url":"u"}')
  out=$(PATH="$fake:$PATH" "$BIN" --issue 5 --parent 2>&1); rc=$?
  rm -rf "$fake"
  assert_zero "$rc" "no parent ref → exit 0"
  assert_contains "$out" '"parent":null' "parent is null when not in body"
}

test_parent_found_in_body() {
  local fake out rc
  # gh will be called twice (once for issue, once for parent); both return same stub
  fake=$(mock_gh_dir 0 '{"number":10,"title":"parent","body":"Parent: #10","labels":[],"comments":[],"state":"OPEN","url":"u"}')
  out=$(PATH="$fake:$PATH" "$BIN" --issue 99 --parent 2>&1); rc=$?
  rm -rf "$fake"
  assert_zero "$rc" "parent found → exit 0"
  assert_contains "$out" '"parent"' "parent key in output"
  assert_contains "$out" '"issue"' "issue key in output"
}

test_repo_flag_accepted() {
  local fake out rc
  fake=$(mock_gh_dir 0 '{"number":1,"title":"t","body":"","labels":[],"comments":[],"state":"OPEN","url":"u"}')
  out=$(PATH="$fake:$PATH" "$BIN" --issue 1 --repo org/repo 2>&1); rc=$?
  rm -rf "$fake"
  assert_zero "$rc" "--repo accepted without error"
}

run_test "safer-load-context requires --issue" test_requires_issue
run_test "safer-load-context: gh not installed → JSON error" test_gh_not_installed
run_test "safer-load-context: gh failure → JSON error, nonzero exit" test_gh_failure_returns_json_error
run_test "safer-load-context: success without --parent → issue JSON" test_success_no_parent
run_test "safer-load-context: --parent with no ref in body → parent:null" test_parent_not_found_in_body
run_test "safer-load-context: --parent with ref in body → parent populated" test_parent_found_in_body
run_test "safer-load-context: --repo flag accepted" test_repo_flag_accepted
report
