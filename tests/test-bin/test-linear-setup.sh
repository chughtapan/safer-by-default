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

  # Mock query_linear for this test
  query_linear() {
    local query="$1"
    if echo "$query" | grep -q "searchableContent.*#999"; then
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

# Run tests
run_test "parent ref resolution" test_parent_ref_resolution
run_test "manual override wins" test_manual_override_wins
run_test "catchall fallback" test_catchall_fallback
run_test "label mapping" test_label_mapping
run_test "assign-projects requires API key" test_assign_projects_requires_api_key
run_test "assign-projects requires flags" test_assign_projects_requires_flags
run_test "assign-projects mutually exclusive flags" test_assign_projects_mutually_exclusive_flags

report
