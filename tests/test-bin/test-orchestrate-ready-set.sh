#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
MOD="$PLUGIN_DIR/skills/orchestrate/ready-set.mjs"

# ready-set.mjs is the canonical dispatch-wave DAG resolver; dispatch-wave.workflow.js inlines a
# mirror. Its --selftest exercises the dependency gate (deps done, parked/in-flight rows excluded,
# #TBD placeholder unsatisfied) and exits non-zero on a mismatch.
test_selftest_passes() {
  local out rc
  out=$(node "$MOD" --selftest 2>&1); rc=$?
  assert_equal "$rc" "0" "selftest exit code" || { echo "$out"; return 1; }
  assert_contains "$out" "cases passed" "selftest output"
}

run_test "orchestrate ready-set resolver selftest" test_selftest_passes
report
