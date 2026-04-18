#!/usr/bin/env bash
# Validates argument handling only; real transitions covered by integration test.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
BIN="$PLUGIN_DIR/bin/safer-transition-label"

test_requires_args() {
  local rc
  "$BIN" >/dev/null 2>&1; rc=$?
  assert_nonzero "$rc" "no args should fail"
  "$BIN" --issue 1 >/dev/null 2>&1; rc=$?
  assert_nonzero "$rc" "missing --from/--to should fail"
}

run_test "safer-transition-label requires --issue/--from/--to" test_requires_args
report
