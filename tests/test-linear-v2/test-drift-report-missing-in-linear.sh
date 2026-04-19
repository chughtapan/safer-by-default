#!/usr/bin/env bash
# drift_report: taxonomy has a project that Linear doesn't → exit 2, delta named.
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

test_missing_in_linear_exit_2() {
  # Linear is missing "Moltzap migration"
  linear_list_projects() {
    printf '%s\n' '[
      {"id":"p1","name":"Tracking infra"},
      {"id":"p2","name":"SBD ops"},
      {"id":"p3","name":"Linear integration"},
      {"id":"p4","name":"Testing doctrine"},
      {"id":"p5","name":"Reentrance Tier-1"},
      {"id":"p6","name":"Community feedback agents"}
    ]'
  }
  export -f linear_list_projects

  local rc
  drift_report "$TAXO" 2>/dev/null; rc=$?
  assert_equal "$rc" "2" "missing project → exit 2"
}

test_missing_in_linear_names_the_project() {
  linear_list_projects() {
    printf '%s\n' '[
      {"id":"p1","name":"Tracking infra"},
      {"id":"p2","name":"SBD ops"},
      {"id":"p3","name":"Linear integration"},
      {"id":"p4","name":"Testing doctrine"},
      {"id":"p5","name":"Reentrance Tier-1"},
      {"id":"p6","name":"Community feedback agents"}
    ]'
  }
  export -f linear_list_projects

  local output
  output=$(drift_report "$TAXO" 2>/dev/null)
  assert_contains "$output" "in-taxonomy-not-in-linear" "output contains taxonomy-side delta label"
  assert_contains "$output" "Moltzap migration" "missing project is named in output"
}

test_missing_in_linear_json_format() {
  linear_list_projects() {
    printf '%s\n' '[
      {"id":"p1","name":"SBD ops"}
    ]'
  }
  export -f linear_list_projects

  local output
  output=$(drift_report "$TAXO" --format=json 2>/dev/null)
  local drift_val
  drift_val=$(printf '%s\n' "$output" | jq -r '.drift')
  assert_equal "$drift_val" "true" "JSON drift=true when projects missing in Linear"
}

run_test "missing project in Linear → exit 2"       test_missing_in_linear_exit_2
run_test "missing project named in output"           test_missing_in_linear_names_the_project
run_test "JSON format: drift=true when missing"      test_missing_in_linear_json_format

report
