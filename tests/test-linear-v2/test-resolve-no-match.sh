#!/usr/bin/env bash
# Rule (5): when all rules miss, resolve_project returns empty stdout, exit 0.
# The caller (cmd_assign_projects) substitutes the catchall and counts the event.
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

test_no_signals_returns_empty_exit_0() {
  linear_get_parent_project() { echo ""; }
  export -f linear_get_parent_project

  local body="Standalone issue with no project markers."
  local project rc
  project=$(resolve_project 500 "$body" ""); rc=$?
  assert_equal "$rc" "0" "exit 0 on no-match"
  assert_equal "$project" "" "empty stdout on no-match"
}

test_bad_gh_number_returns_exit_30() {
  local rc
  resolve_project "not-a-number" "body" "" 2>/dev/null; rc=$?
  assert_equal "$rc" "30" "non-numeric gh_number → exit 30"
}

test_no_match_is_not_catchall() {
  linear_get_parent_project() { echo ""; }
  export -f linear_get_parent_project

  local project
  project=$(resolve_project 501 "Standalone issue." "")
  local catchall
  catchall=$(taxonomy_catchall "$_SAFER_TAXO_PATH")
  # resolve_project returns empty; the CALLER provides the catchall
  if [[ "$project" == "$catchall" ]]; then
    echo "    FAIL: resolve_project emitted catchall (should return empty)"
    return 1
  fi
  assert_equal "$project" "" "no-match: resolver returns empty, not the catchall"
}

run_test "no signals → empty stdout, exit 0"  test_no_signals_returns_empty_exit_0
run_test "non-numeric gh_number → exit 30"    test_bad_gh_number_returns_exit_30
run_test "no-match does not emit catchall"     test_no_match_is_not_catchall

report
