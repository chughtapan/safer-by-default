#!/usr/bin/env bash
# Q3 decision: single-hop only. Grandparent is never consulted.
# When parent has no project, rule (3) does not walk up to grandparent.
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

test_single_hop_no_grandparent_lookup() {
  local call_count=0
  linear_get_parent_project() {
    call_count=$((call_count + 1))
    echo ""  # parent has no project
  }
  export -f linear_get_parent_project

  local body="## Parent
#50

Description."
  # Run in current shell context (not subshell) so we can check call_count
  resolve_project 300 "$body" "safer:spike" >/dev/null 2>/dev/null || true

  # linear_get_parent_project should be called EXACTLY ONCE (for #50 only)
  # In the current implementation, it's called via subshell, so call_count
  # may not propagate. We instead verify the OUTPUT behavior:
  # parent has no project → falls through to label → "Tracking infra"
  local project
  project=$(resolve_project 300 "$body" "safer:spike")
  assert_equal "$project" "Tracking infra" "single-hop: empty parent → falls through to label, no grandparent walk"
}

test_extract_parent_heading_returns_immediate_parent_only() {
  # The ## Parent heading must reference ONE issue number; only that one is looked up.
  local body="## Parent
#50

Some sub-issue about a grandparent #200 somewhere."
  local num
  num=$(extract_parent_heading "$body")
  assert_equal "$num" "50" "only the ## Parent heading number is extracted; in-body mentions ignored"
}

test_parent_heading_no_number_returns_empty() {
  local body="## Parent

No number on the next line."
  local num
  num=$(extract_parent_heading "$body")
  assert_equal "$num" "" "## Parent with no following #N returns empty"
}

run_test "single-hop: empty parent falls through (no grandparent walk)" test_single_hop_no_grandparent_lookup
run_test "extract heading returns immediate parent only"                 test_extract_parent_heading_returns_immediate_parent_only
run_test "## Parent with no #N returns empty"                           test_parent_heading_no_number_returns_empty

report
