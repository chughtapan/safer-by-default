#!/usr/bin/env bash
# Validates argument handling; real gh calls covered by integration test.
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

run_test "safer-load-context requires --issue" test_requires_issue
report
