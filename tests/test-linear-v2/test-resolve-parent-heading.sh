#!/usr/bin/env bash
# Rule (3): ## Parent heading followed by #N is treated as parent-ref.
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

test_parent_heading_routes_to_parent_project() {
  linear_get_parent_project() {
    if [[ "$1" == "777" ]]; then echo "Tracking infra"; else echo ""; fi
  }
  export -f linear_get_parent_project

  local body="## Parent
#777

Sub-issue description."
  local project
  project=$(resolve_project 200 "$body" "")
  assert_equal "$project" "Tracking infra" "## Parent heading routes to parent's project"
}

test_parent_heading_beats_label_keyword() {
  linear_get_parent_project() { echo "Moltzap migration"; }
  export -f linear_get_parent_project

  local body="## Parent
#777"
  local project
  project=$(resolve_project 201 "$body" "safer:spec")
  assert_equal "$project" "Moltzap migration" "parent-heading beats label-keyword (rule 3 > rule 4)"
}

test_extract_parent_heading_extracts_number() {
  local body="## Parent
#888

Description."
  local num
  num=$(extract_parent_heading "$body")
  assert_equal "$num" "888" "## Parent heading number extracted correctly"
}

test_parent_heading_empty_parent_falls_through() {
  linear_get_parent_project() { echo ""; }
  export -f linear_get_parent_project

  local body="## Parent
#777"
  local project
  project=$(resolve_project 202 "$body" "safer:spike")
  assert_equal "$project" "Tracking infra" "empty heading parent → falls through to label-keyword"
}

run_test "## Parent heading routes to parent's project"  test_parent_heading_routes_to_parent_project
run_test "parent-heading beats label-keyword"           test_parent_heading_beats_label_keyword
run_test "extract parent heading number"                test_extract_parent_heading_extracts_number
run_test "empty heading parent falls through to label"  test_parent_heading_empty_parent_falls_through

report
