#!/usr/bin/env bash
# Rule (2) parent-ref: when parent has a project, it wins over label-keyword.
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

test_parent_ref_routes_to_parent_project() {
  linear_get_parent_project() {
    if [[ "$1" == "50" ]]; then echo "Moltzap migration"; else echo ""; fi
  }
  export -f linear_get_parent_project

  local body="Parent: #50

Sub-issue body."
  local project
  project=$(resolve_project 101 "$body" "")
  assert_equal "$project" "Moltzap migration" "parent-ref resolves parent's project"
}

test_parent_ref_beats_label_keyword() {
  linear_get_parent_project() {
    if [[ "$1" == "50" ]]; then echo "Moltzap migration"; else echo ""; fi
  }
  export -f linear_get_parent_project

  local body="Parent: #50
Sub-issue body."
  # safer:spike label would match "Tracking infra" via rule 4
  local project
  project=$(resolve_project 101 "$body" "safer:spike")
  assert_equal "$project" "Moltzap migration" "parent-ref beats label-keyword (rule 2 > rule 4)"
}

test_extract_parent_ref_extracts_number() {
  local body="Parent: #999

Body text."
  local num
  num=$(extract_parent_ref "$body")
  assert_equal "$num" "999" "parent-ref number extracted correctly"
}

test_extract_parent_ref_first_match() {
  local body="Parent: #100
Parent: #200"
  local num
  num=$(extract_parent_ref "$body")
  assert_equal "$num" "100" "first Parent: #N is used"
}

run_test "parent-ref resolves parent's project"      test_parent_ref_routes_to_parent_project
run_test "parent-ref beats label-keyword"            test_parent_ref_beats_label_keyword
run_test "extract parent-ref number"                 test_extract_parent_ref_extracts_number
run_test "extract parent-ref: first match wins"      test_extract_parent_ref_first_match

report
