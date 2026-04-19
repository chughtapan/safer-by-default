#!/usr/bin/env bash
# drift_report: when taxonomy matches live Linear exactly → exit 0, zero delta.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"
PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
# shellcheck disable=SC1091
source "$PLUGIN_DIR/lib/safer-linear/taxonomy.sh"
source "$PLUGIN_DIR/lib/safer-linear/linear-api.sh"
source "$PLUGIN_DIR/lib/safer-linear/drift.sh"

TAXO="$PLUGIN_DIR/config/linear-taxonomy.yaml"

_mock_linear_all_projects() {
  linear_list_projects() {
    printf '%s\n' '[
      {"id":"p1","name":"Tracking infra"},
      {"id":"p2","name":"SBD ops"},
      {"id":"p3","name":"Linear integration"},
      {"id":"p4","name":"Testing doctrine"},
      {"id":"p5","name":"Reentrance Tier-1"},
      {"id":"p6","name":"Community feedback agents"},
      {"id":"p7","name":"Moltzap migration"}
    ]'
  }
  export -f linear_list_projects
}

test_no_drift_exit_0() {
  _mock_linear_all_projects
  local rc
  drift_report "$TAXO" 2>/dev/null; rc=$?
  assert_equal "$rc" "0" "no drift → exit 0"
}

test_no_drift_summary_shows_zero_counts() {
  _mock_linear_all_projects
  local output
  output=$(drift_report "$TAXO" 2>/dev/null)
  assert_contains "$output" "missing_in_linear=0" "missing_in_linear=0 in summary"
  assert_contains "$output" "extra_in_linear=0"   "extra_in_linear=0 in summary"
}

test_no_drift_json_format() {
  _mock_linear_all_projects
  local output
  output=$(drift_report "$TAXO" --format=json 2>/dev/null)
  local drift_val
  drift_val=$(printf '%s\n' "$output" | jq -r '.drift')
  assert_equal "$drift_val" "false" "JSON drift field is false when no drift"
}

run_test "no drift → exit 0"                  test_no_drift_exit_0
run_test "summary shows missing=0 extra=0"    test_no_drift_summary_shows_zero_counts
run_test "JSON format drift=false"             test_no_drift_json_format

report
