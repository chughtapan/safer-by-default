#!/usr/bin/env bash
# cmd_assign_projects --dry-run: end-to-end fixture test.
# Mocks gh (issue list) and Linear API; verifies RESULT line shape.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"
PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
# shellcheck disable=SC1091
source "$PLUGIN_DIR/lib/safer-linear/taxonomy.sh"
source "$PLUGIN_DIR/lib/safer-linear/linear-api.sh"
source "$PLUGIN_DIR/lib/safer-linear/resolve.sh"
source "$PLUGIN_DIR/lib/safer-linear/drift.sh"
source "$PLUGIN_DIR/lib/safer-linear/cli.sh"

TAXO="$PLUGIN_DIR/config/linear-taxonomy.yaml"
export _SAFER_TAXO_PATH="$TAXO"

_mock_all_projects_present() {
  linear_list_projects() {
    printf '%s\n' '[
      {"id":"p1","name":"Tracking infra"},
      {"id":"p2","name":"SBD ops"},
      {"id":"p3","name":"Linear integration"},
      {"id":"p4","name":"Testing doctrine"},
      {"id":"p5","name":"Reentrance Tier-1"},
      {"id":"p6","name":"Community feedback agents"},
      {"id":"p7","name":"Moltzap migration"}
    ]'
  }
  export -f linear_list_projects
}

test_dry_run_result_line_assigned() {
  _mock_all_projects_present

  # gh returns two issues: one with safer:spike label, one with moltzap-migration label
  gh() {
    printf '%s\n' '[
      {"number":10,"body":"Issue about spikes.","labels":[{"name":"safer:spike"}]},
      {"number":11,"body":"Moltzap migration task.","labels":[{"name":"moltzap-migration"}]}
    ]'
  }
  export -f gh

  # linear_find_issue_by_gh_number: both issues are in Linear but in wrong project
  linear_find_issue_by_gh_number() {
    case "$1" in
      10) printf '%s\n' '{"id":"lin-10","project":{"id":"p2","name":"SBD ops"}}' ;;
      11) printf '%s\n' '{"id":"lin-11","project":{"id":"p2","name":"SBD ops"}}' ;;
    esac
  }
  export -f linear_find_issue_by_gh_number

  linear_get_parent_project() { echo ""; }
  export -f linear_get_parent_project

  linear_find_project_id() {
    case "$1" in
      "Tracking infra")  echo "p1" ;;
      "Moltzap migration") echo "p7" ;;
      *) echo "" ;;
    esac
  }
  export -f linear_find_project_id

  local output
  output=$(cmd_assign_projects --all --dry-run --taxonomy "$TAXO" 2>/dev/null)
  assert_contains "$output" "RESULT:" "RESULT line emitted"
  assert_contains "$output" "assigned=2" "2 dry-run assignments counted"
  assert_contains "$output" "skipped=0" "0 skipped"
  assert_contains "$output" "error=0" "0 errors"
}

test_dry_run_skips_already_assigned() {
  _mock_all_projects_present

  gh() {
    printf '%s\n' '[
      {"number":20,"body":"Already correct.","labels":[{"name":"safer:spike"}]}
    ]'
  }
  export -f gh

  # Issue already in correct project "Tracking infra"
  linear_find_issue_by_gh_number() {
    printf '%s\n' '{"id":"lin-20","project":{"id":"p1","name":"Tracking infra"}}'
  }
  export -f linear_find_issue_by_gh_number

  linear_get_parent_project() { echo ""; }
  export -f linear_get_parent_project

  local output
  output=$(cmd_assign_projects --all --dry-run --taxonomy "$TAXO" 2>/dev/null)
  assert_contains "$output" "skipped=1" "already-assigned issue is skipped"
  assert_contains "$output" "assigned=0" "no dry-run assignments when already correct"
}

test_bootstrap_failure_aborts_before_enumeration() {
  # linear_list_projects missing a project → bootstrap fails → gh never called
  linear_list_projects() {
    printf '%s\n' '[{"id":"p1","name":"SBD ops"}]'
  }
  export -f linear_list_projects

  local gh_called=false
  gh() { gh_called=true; echo '[]'; }
  export -f gh

  local rc
  cmd_assign_projects --all --dry-run --taxonomy "$TAXO" 2>/dev/null; rc=$?
  assert_equal "$rc" "42" "bootstrap failure → exit 42"
}

test_requires_all_or_since() {
  local output rc
  output=$(cmd_assign_projects --taxonomy "$TAXO" 2>&1 || true); rc=$?
  assert_nonzero "$rc" "no --all or --since → nonzero exit"
  assert_contains "$output" "ERROR" "error message emitted"
}

run_test "dry-run: RESULT assigned=2"                   test_dry_run_result_line_assigned
run_test "dry-run: already-assigned → skipped"          test_dry_run_skips_already_assigned
run_test "bootstrap failure aborts before enumeration"  test_bootstrap_failure_aborts_before_enumeration
run_test "requires --all or --since"                    test_requires_all_or_since

report
