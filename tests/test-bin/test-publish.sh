#!/usr/bin/env bash
# Integration-test safer-publish only validates argument handling.
# Real gh calls would require a test repo + cleanup; covered in the
# end-to-end integration test instead.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
BIN="$PLUGIN_DIR/bin/safer-publish"

test_requires_kind() {
  local rc
  "$BIN" >/dev/null 2>&1; rc=$?
  assert_nonzero "$rc" "no --kind should fail"
}

test_validates_kind() {
  local rc
  "$BIN" --kind nonsense >/dev/null 2>&1; rc=$?
  assert_nonzero "$rc" "unknown --kind should fail"
}

test_requires_title_for_epic() {
  local rc
  "$BIN" --kind epic >/dev/null 2>&1; rc=$?
  assert_nonzero "$rc" "epic without --title should fail"
}

test_requires_issue_for_comment() {
  local rc
  "$BIN" --kind comment --body "hi" >/dev/null 2>&1; rc=$?
  assert_nonzero "$rc" "comment without --issue should fail"
}

test_rejects_missing_body_file() {
  local rc
  "$BIN" --kind issue --title "t" --body-file /does/not/exist.md >/dev/null 2>&1; rc=$?
  assert_nonzero "$rc" "missing --body-file should fail"
}

run_test "safer-publish requires --kind" test_requires_kind
run_test "safer-publish rejects unknown --kind" test_validates_kind
run_test "safer-publish epic requires --title" test_requires_title_for_epic
run_test "safer-publish comment requires --issue" test_requires_issue_for_comment
run_test "safer-publish rejects missing body-file" test_rejects_missing_body_file
report
