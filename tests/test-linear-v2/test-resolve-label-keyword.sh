#!/usr/bin/env bash
# Rule (4): first label matching taxonomy.labelMap, file order, wins.
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

test_label_keyword_matches_safer_spike() {
  linear_get_parent_project() { echo ""; }
  export -f linear_get_parent_project

  local project
  project=$(resolve_project 400 "Some body." "safer:spike")
  assert_equal "$project" "Tracking infra" "safer:spike → Tracking infra"
}

test_label_keyword_matches_community_feedback() {
  linear_get_parent_project() { echo ""; }
  export -f linear_get_parent_project

  local project
  project=$(resolve_project 401 "Body." "community-feedback")
  assert_equal "$project" "Community feedback agents" "community-feedback → Community feedback agents"
}

test_label_keyword_matches_moltzap_migration() {
  linear_get_parent_project() { echo ""; }
  export -f linear_get_parent_project

  local project
  project=$(resolve_project 402 "Body." "moltzap-migration")
  assert_equal "$project" "Moltzap migration" "moltzap-migration label → Moltzap migration"
}

test_match_label_keyword_first_match_wins() {
  # taxonomy has safer:spike BEFORE community-feedback in file order
  # if both labels present, safer:spike should win
  local labels=$'safer:spike\ncommunity-feedback'
  local project
  project=$(match_label_keyword "$labels")
  assert_equal "$project" "Tracking infra" "first-match-wins: safer:spike before community-feedback"
}

test_unknown_label_returns_empty() {
  linear_get_parent_project() { echo ""; }
  export -f linear_get_parent_project

  local project
  project=$(resolve_project 403 "Body." "unknown-label")
  assert_equal "$project" "" "unknown label → no match (empty stdout)"
}

test_no_labels_returns_empty() {
  linear_get_parent_project() { echo ""; }
  export -f linear_get_parent_project

  local project
  project=$(resolve_project 404 "Body." "")
  assert_equal "$project" "" "no labels → no match (empty stdout)"
}

run_test "safer:spike → Tracking infra"                test_label_keyword_matches_safer_spike
run_test "community-feedback → Community feedback agents" test_label_keyword_matches_community_feedback
run_test "moltzap-migration label → Moltzap migration" test_label_keyword_matches_moltzap_migration
run_test "first-match-wins in labelMap order"          test_match_label_keyword_first_match_wins
run_test "unknown label → empty"                       test_unknown_label_returns_empty
run_test "no labels → empty"                           test_no_labels_returns_empty

report
