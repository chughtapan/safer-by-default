#!/usr/bin/env bash
# Moltzap parent-link routing: sub-issues with Parent: #N pointing to a
# moltzap epic route to "Moltzap migration" via rule (2), NOT to
# "Testing doctrine" or "SBD ops" via label-keyword rule (4).
#
# This is the static-fixture spot-check for plan §7 traceability row
# "Moltzap sub-issues route correctly" and architect open question 1.
# The moltzap epic is represented as gh#50 in these fixtures.
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

# Mock: parent #50 is the moltzap epic, in "Moltzap migration"
_mock_parent_project() {
  linear_get_parent_project() {
    if [[ "$1" == "50" ]]; then
      echo "Moltzap migration"
    else
      echo ""
    fi
  }
  export -f linear_get_parent_project
}

test_moltzap_sub_with_parent_ref() {
  _mock_parent_project
  local body="Parent: #50

Moltzap sub-issue body — adds listener to Moltzap."
  # safer:spec label would route to "Testing doctrine" via rule 4 alone
  local project
  project=$(resolve_project 103 "$body" "safer:spec")
  assert_equal "$project" "Moltzap migration" "Parent: #50 → Moltzap migration (rule 2 wins over safer:spec)"
}

test_moltzap_sub_with_parent_heading() {
  _mock_parent_project
  local body="## Parent
#50

Moltzap sub-issue body."
  local project
  project=$(resolve_project 107 "$body" "safer:spec")
  assert_equal "$project" "Moltzap migration" "## Parent #50 → Moltzap migration (rule 3 wins over safer:spec)"
}

test_moltzap_sub_without_parent_uses_label() {
  # If a moltzap sub-issue has NO parent link, it falls back to label
  linear_get_parent_project() { echo ""; }
  export -f linear_get_parent_project

  local body="No parent link in this body."
  local project
  project=$(resolve_project 109 "$body" "moltzap-migration")
  assert_equal "$project" "Moltzap migration" "moltzap-migration label → Moltzap migration via rule 4"
}

test_moltzap_no_signals_reaches_no_match() {
  # Without parent link OR moltzap-migration label → no-match (caller will use catchall)
  linear_get_parent_project() { echo ""; }
  export -f linear_get_parent_project

  local body="Standalone issue with no moltzap signals."
  local project
  project=$(resolve_project 108 "$body" "")
  assert_equal "$project" "" "no moltzap signals → empty (catchall applied by caller)"
}

run_test "Moltzap sub w/ Parent: #N → Moltzap migration (rule 2)" test_moltzap_sub_with_parent_ref
run_test "Moltzap sub w/ ## Parent → Moltzap migration (rule 3)"  test_moltzap_sub_with_parent_heading
run_test "Moltzap sub w/ moltzap-migration label → rule 4"        test_moltzap_sub_without_parent_uses_label
run_test "No moltzap signals → no-match"                          test_moltzap_no_signals_reaches_no_match

report
