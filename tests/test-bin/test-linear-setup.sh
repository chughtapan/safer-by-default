#!/usr/bin/env bash
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
BIN="$PLUGIN_DIR/bin/safer-linear-setup"

# Load script functions for testing
# shellcheck disable=SC1091
source "$BIN" 2>/dev/null || true

test_parent_ref_resolution() {
  local body="Parent: #999

This is a sub-issue."

  # Mock query_linear for this test; match by GH URL suffix used in attachment filter
  query_linear() {
    local query="$1"
    if echo "$query" | grep -q "issues/999"; then
      echo '{"data":{"issues":{"nodes":[{"id":"issue-999","project":{"id":"proj-moltzap","name":"Moltzap migration"}}]}}}'
    else
      echo '{"data":{"issues":{"nodes":[]}}}'
    fi
  }
  export -f query_linear

  # Test that parent ref resolution works
  local project
  project=$(resolve_project_for_issue 100 "$body" "")
  assert_equal "$project" "Moltzap migration" "parent ref resolves to correct project"
}

test_manual_override_wins() {
  local body="Linear-project: Moltzap migration
Parent: #888

This is a sub-issue."

  # Test that manual override takes precedence
  local project
  project=$(resolve_project_for_issue 100 "$body" "")
  assert_equal "$project" "Moltzap migration" "manual override wins"
}

test_catchall_fallback() {
  local body="This is a standalone issue with no parent or project declaration."
  local labels=""

  # Test that missing parent/project resolves to empty (catchall)
  local project
  project=$(resolve_project_for_issue 100 "$body" "$labels")
  assert_equal "$project" "" "issue with no parent resolves to empty for catchall"
}

test_label_mapping() {
  local body="Random issue body"
  local labels="safer:spike"

  # Mock query_linear to return empty for any query
  query_linear() {
    echo '{"data":{"issues":{"nodes":[]}}}'
  }
  export -f query_linear

  # Test that label mapping works
  local project
  project=$(resolve_project_for_issue 100 "$body" "$labels")
  assert_equal "$project" "Tracking infra" "safer:spike label maps to Tracking infra"
}

test_parent_heading_resolution() {
  local body="## Parent
#777

Some description."

  # Mock query_linear; match by GH URL suffix used in attachment filter
  query_linear() {
    local query="$1"
    if echo "$query" | grep -q "issues/777"; then
      echo '{"data":{"issues":{"nodes":[{"id":"issue-777","project":{"id":"proj-track","name":"Tracking infra"}}]}}}'
    else
      echo '{"data":{"issues":{"nodes":[]}}}'
    fi
  }
  export -f query_linear

  local project
  project=$(resolve_project_for_issue 200 "$body" "")
  assert_equal "$project" "Tracking infra" "parent heading ## Parent inference resolves to correct project"
}

test_catchall_assigned_in_loop() {
  export LINEAR_API_KEY="test-key"

  # Mock gh to return one issue with no project signals
  gh() {
    echo '[{"number":55,"body":"Standalone issue","labels":[]}]'
  }
  export -f gh

  # Mock Linear: issue not found in Linear (empty nodes) -> SKIP path
  query_linear() {
    echo '{"data":{"issues":{"nodes":[]}}}'
  }
  export -f query_linear

  local output
  output=$("$BIN" assign-projects --all 2>&1 || true)
  # resolve_project_for_issue returns empty -> main loop sets project="SBD ops" -> catchall++
  # query_linear_issue_by_gh_number returns empty -> SKIP (not found in Linear)
  # The DRY-RUN path would show "SBD ops"; the SKIP path shows "RESULT: catchall=1"
  assert_contains "$output" "catchall=1" "catchall counter incremented when no project signals match"
  assert_contains "$output" "RESULT:" "main loop completes and prints result line"
}

test_counter_increments_complete_loop() {
  export LINEAR_API_KEY="test-key"

  # Mock gh to return one issue
  gh() {
    echo '[{"number":10,"body":"Test issue","labels":[]}]'
  }
  export -f gh

  # Mock Linear: issue not found -> skipped (exercises ((++skipped)) after catchall)
  query_linear() {
    echo '{"data":{"issues":{"nodes":[]}}}'
  }
  export -f query_linear

  local output
  output=$("$BIN" assign-projects --all 2>&1 || true)
  # With the old ((x++)) bug under set -e, ((catchall++)) would return 0 (falsy) and kill the script.
  # The RESULT line only appears if all counter increments succeeded.
  assert_contains "$output" "RESULT:" "script completes without aborting on first counter increment"
}

test_idempotency_skips_already_assigned() {
  # Test idempotency by exercising the component functions directly via sourced BIN.
  # Running "$BIN" as a subprocess re-defines query_linear (overriding the mock),
  # so we test the decision logic through sourced helpers instead.

  # Mock query_linear in the current shell (works for sourced functions)
  query_linear() {
    local query="$1"
    if echo "$query" | grep -q "issues/99"; then
      echo '{"data":{"issues":{"nodes":[{"id":"lin-99","project":{"id":"proj-track","name":"Tracking infra"}}]}}}'
    else
      echo '{"data":{"issues":{"nodes":[]}}}'
    fi
  }
  export -f query_linear

  # safer:spike resolves to "Tracking infra" via label mapping (no API call)
  local project
  project=$(resolve_project_for_issue 99 "" "safer:spike")
  assert_equal "$project" "Tracking infra" "label resolves to Tracking infra"

  # get_issue_project returns current project from Linear (mocked above)
  local current_project
  current_project=$(get_issue_project 99)
  assert_equal "$current_project" "Tracking infra" "Linear reports issue already in Tracking infra"

  # Idempotency: current_project == project means the main loop would skip
  assert_equal "$project" "$current_project" "project matches current — issue would be skipped (idempotent)"
}

test_assign_projects_requires_api_key() {
  # Test that the subcommand validates API_KEY
  unset LINEAR_API_KEY || true
  local output
  output=$("$BIN" assign-projects --all 2>&1 || true)
  assert_contains "$output" "ERROR: LINEAR_API_KEY" "validates API key presence"
}

test_assign_projects_requires_flags() {
  # Test that either --all or --since is required
  export LINEAR_API_KEY="test-key"
  local output
  output=$("$BIN" assign-projects 2>&1 || true)
  assert_contains "$output" "ERROR" "requires --all or --since flag"
}

test_assign_projects_mutually_exclusive_flags() {
  # Test that --all and --since are mutually exclusive
  export LINEAR_API_KEY="test-key"
  local output
  output=$("$BIN" assign-projects --all --since 5m 2>&1 || true)
  assert_contains "$output" "mutually exclusive" "rejects both --all and --since"
}

test_since_format_validation() {
  export LINEAR_API_KEY="test-key"
  local output
  output=$("$BIN" assign-projects --since foo 2>&1 || true)
  assert_contains "$output" "ERROR: --since DURATION" "rejects invalid --since format"
}

# Run tests
run_test "parent ref resolution" test_parent_ref_resolution
run_test "manual override wins" test_manual_override_wins
run_test "catchall fallback" test_catchall_fallback
run_test "label mapping" test_label_mapping
run_test "parent heading resolution" test_parent_heading_resolution
run_test "catchall assigned in main loop" test_catchall_assigned_in_loop
run_test "counter increments complete loop" test_counter_increments_complete_loop
run_test "idempotency skips already assigned" test_idempotency_skips_already_assigned
run_test "assign-projects requires API key" test_assign_projects_requires_api_key
run_test "assign-projects requires flags" test_assign_projects_requires_flags
run_test "assign-projects mutually exclusive flags" test_assign_projects_mutually_exclusive_flags
run_test "--since format validation" test_since_format_validation

report
