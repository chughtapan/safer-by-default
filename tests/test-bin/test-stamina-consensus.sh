#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
MOD="$PLUGIN_DIR/skills/stamina/consensus.mjs"

# consensus.mjs is the canonical Phase-4 reducer; dispatch.workflow.js inlines a mirror.
# Its --selftest exercises every row of the consensus table and exits non-zero on a mismatch.
test_selftest_passes() {
  local out rc
  out=$(node "$MOD" --selftest 2>&1); rc=$?
  assert_equal "$rc" "0" "selftest exit code" || { echo "$out"; return 1; }
  assert_contains "$out" "cases passed" "selftest output"
}

run_test "stamina consensus reducer selftest" test_selftest_passes
report
