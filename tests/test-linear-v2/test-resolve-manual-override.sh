#!/usr/bin/env bash
# Rule (1) manual-override is highest priority; wins over parent-ref and labels.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"
PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
# shellcheck disable=SC1091
source "$PLUGIN_DIR/lib/safer-linear/taxonomy.sh"
source "$PLUGIN_DIR/lib/safer-linear/linear-api.sh"
source "$PLUGIN_DIR/lib/safer-linear/resolve.sh"

export _SAFER_TAXO_PATH="$PLUGIN_DIR/config/linear-taxonomy.yaml"

test_manual_override_wins_over_label() {
  linear_get_parent_project() { echo ""; }
  export -f linear_get_parent_project

  local body="Linear-project: Moltzap migration
Some body text."
  local project
  project=$(resolve_project 100 "$body" "safer:spike")
  assert_equal "$project" "Moltzap migration" "manual-override project name returned"
}

test_manual_override_wins_over_parent_ref() {
  linear_get_parent_project() { echo "Tracking infra"; }
  export -f linear_get_parent_project

  local body="Linear-project: Moltzap migration
Parent: #50
Some body text."
  local project
  project=$(resolve_project 100 "$body" "")
  assert_equal "$project" "Moltzap migration" "manual-override beats parent-ref rule"
}

test_extract_manual_override_trims_whitespace() {
  local body="Linear-project:   SBD ops   "
  local val
  val=$(extract_manual_override "$body")
  assert_equal "$val" "SBD ops" "leading/trailing whitespace trimmed"
}

test_extract_manual_override_strips_trailing_comment() {
  local body="Linear-project: Linear integration # set by orchestrate"
  local val
  val=$(extract_manual_override "$body")
  assert_equal "$val" "Linear integration" "trailing # comment stripped"
}

test_extract_manual_override_case_insensitive() {
  local body="linear-project: SBD ops"
  local val
  val=$(extract_manual_override "$body")
  assert_equal "$val" "SBD ops" "key match is case-insensitive"
}

test_no_override_returns_empty() {
  local body="No override here."
  local val
  val=$(extract_manual_override "$body")
  assert_equal "$val" "" "no override → empty stdout"
}

run_test "manual-override wins over label"      test_manual_override_wins_over_label
run_test "manual-override wins over parent-ref" test_manual_override_wins_over_parent_ref
run_test "extract trims whitespace"             test_extract_manual_override_trims_whitespace
run_test "extract strips trailing comment"      test_extract_manual_override_strips_trailing_comment
run_test "key match is case-insensitive"        test_extract_manual_override_case_insensitive
run_test "no override → empty stdout"           test_no_override_returns_empty

report
