#!/usr/bin/env bash
# Rule (2) fallthrough semantics: parent marker present but parent has no
# project → rule (2) is NOT a match → fall through to rule (3), then (4).
# This is the concern from sbd#120 pinned in plan §5.
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

test_empty_parent_project_falls_through_to_label() {
  # Parent: #50 is in Linear but has no project (empty_project = non-match)
  linear_get_parent_project() { echo ""; }
  export -f linear_get_parent_project

  local body="Parent: #50

Sub-issue with empty parent project."
  # safer:spike → "Tracking infra" via rule 4
  local project
  project=$(resolve_project 101 "$body" "safer:spike")
  assert_equal "$project" "Tracking infra" "empty parent → falls through to label-keyword"
}

test_empty_parent_project_falls_through_to_no_match() {
  # Parent: #50 has no project; no label match either → no-match (empty)
  linear_get_parent_project() { echo ""; }
  export -f linear_get_parent_project

  local body="Parent: #50

Sub-issue body."
  local project
  project=$(resolve_project 102 "$body" "")
  assert_equal "$project" "" "empty parent + no labels → no-match (empty stdout)"
}

test_linear_error_on_parent_lookup_returns_32() {
  # Transient Linear API failure must NOT fall through — must return 32
  linear_get_parent_project() { printf 'LINEAR_NETWORK_ERROR: simulated\n' >&2; return 21; }
  export -f linear_get_parent_project

  local body="Parent: #50
Sub-issue body."
  local rc
  resolve_project 103 "$body" "" 2>/dev/null; rc=$?
  assert_equal "$rc" "32" "transient Linear error on parent lookup → exit 32 (no fallthrough)"
}

run_test "empty parent project falls through to label-keyword"  test_empty_parent_project_falls_through_to_label
run_test "empty parent + no labels → no-match"                  test_empty_parent_project_falls_through_to_no_match
run_test "Linear API error on parent lookup → exit 32"          test_linear_error_on_parent_lookup_returns_32

report
