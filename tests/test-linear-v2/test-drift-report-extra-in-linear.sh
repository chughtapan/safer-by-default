#!/usr/bin/env bash
# drift_report: Linear has a project not in taxonomy → exit 2, extra named.
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

test_extra_in_linear_exit_2() {
  # Linear has an extra "Zapbot cleanup" not in taxonomy
  linear_list_projects() {
    printf '%s\n' '[
      {"id":"p1","name":"Tracking infra"},
      {"id":"p2","name":"SBD ops"},
      {"id":"p3","name":"Linear integration"},
      {"id":"p4","name":"Testing doctrine"},
      {"id":"p5","name":"Reentrance Tier-1"},
      {"id":"p6","name":"Community feedback agents"},
      {"id":"p7","name":"Moltzap migration"},
      {"id":"p8","name":"Zapbot cleanup"}
    ]'
  }
  export -f linear_list_projects

  local rc
  drift_report "$TAXO" 2>/dev/null; rc=$?
  assert_equal "$rc" "2" "extra Linear project → exit 2"
}

test_extra_in_linear_named_in_output() {
  linear_list_projects() {
    printf '%s\n' '[
      {"id":"p1","name":"Tracking infra"},
      {"id":"p2","name":"SBD ops"},
      {"id":"p3","name":"Linear integration"},
      {"id":"p4","name":"Testing doctrine"},
      {"id":"p5","name":"Reentrance Tier-1"},
      {"id":"p6","name":"Community feedback agents"},
      {"id":"p7","name":"Moltzap migration"},
      {"id":"p8","name":"Zapbot cleanup"}
    ]'
  }
  export -f linear_list_projects

  local output
  output=$(drift_report "$TAXO" 2>/dev/null)
  assert_contains "$output" "in-linear-not-in-taxonomy" "output contains linear-side delta label"
  assert_contains "$output" "Zapbot cleanup" "extra project is named in output"
}

test_extra_in_linear_json_extra_array() {
  linear_list_projects() {
    printf '%s\n' '[
      {"id":"p1","name":"Tracking infra"},
      {"id":"p2","name":"SBD ops"},
      {"id":"p3","name":"Linear integration"},
      {"id":"p4","name":"Testing doctrine"},
      {"id":"p5","name":"Reentrance Tier-1"},
      {"id":"p6","name":"Community feedback agents"},
      {"id":"p7","name":"Moltzap migration"},
      {"id":"p8","name":"Zapbot cleanup"}
    ]'
  }
  export -f linear_list_projects

  local output
  output=$(drift_report "$TAXO" --format=json 2>/dev/null)
  local extra_count
  extra_count=$(printf '%s\n' "$output" | jq '.extraInLinear | length')
  if [[ "$extra_count" -lt 1 ]]; then
    printf '    FAIL: extraInLinear is empty\n'; return 1
  fi
  assert_contains "$(printf '%s\n' "$output" | jq -r '.extraInLinear[]')" "Zapbot cleanup" "JSON extraInLinear contains extra project"
}

run_test "extra Linear project → exit 2"            test_extra_in_linear_exit_2
run_test "extra project named in output"             test_extra_in_linear_named_in_output
run_test "JSON extraInLinear contains extra project" test_extra_in_linear_json_extra_array

report
