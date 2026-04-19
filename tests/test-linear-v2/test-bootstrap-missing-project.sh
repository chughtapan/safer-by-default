#!/usr/bin/env bash
# bootstrap_verify_preexisting: fail-loudly path.
# On first missing project: exit 42, stderr names the missing project.
# Q1 decision: require-preexisting; no auto-create.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"
PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
# shellcheck disable=SC1091
source "$PLUGIN_DIR/lib/safer-linear/taxonomy.sh"
source "$PLUGIN_DIR/lib/safer-linear/linear-api.sh"
source "$PLUGIN_DIR/lib/safer-linear/drift.sh"

TAXO="$PLUGIN_DIR/config/linear-taxonomy.yaml"

test_missing_project_exits_42() {
  # Linear missing "Moltzap migration"
  linear_list_projects() {
    printf '%s\n' '[
      {"id":"p1","name":"Tracking infra"},
      {"id":"p2","name":"SBD ops"},
      {"id":"p3","name":"Linear integration"},
      {"id":"p4","name":"Testing doctrine"},
      {"id":"p5","name":"Reentrance Tier-1"},
      {"id":"p6","name":"Community feedback agents"}
    ]'
  }
  export -f linear_list_projects

  local rc
  bootstrap_verify_preexisting "$TAXO" 2>/dev/null; rc=$?
  assert_equal "$rc" "42" "missing project → exit 42"
}

test_missing_project_names_it_on_stderr() {
  linear_list_projects() {
    printf '%s\n' '[{"id":"p1","name":"SBD ops"}]'
  }
  export -f linear_list_projects

  local stderr_out
  stderr_out=$(bootstrap_verify_preexisting "$TAXO" 2>&1 >/dev/null || true)
  assert_contains "$stderr_out" "BOOTSTRAP_MISSING_PROJECT" "stderr contains BOOTSTRAP_MISSING_PROJECT tag"
}

test_all_present_exits_0() {
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

  local rc
  bootstrap_verify_preexisting "$TAXO" 2>/dev/null; rc=$?
  assert_equal "$rc" "0" "all projects present → exit 0"
}

test_linear_failure_exits_41() {
  linear_list_projects() {
    printf 'LINEAR_NETWORK_ERROR: simulated\n' >&2; return 21
  }
  export -f linear_list_projects

  local rc
  bootstrap_verify_preexisting "$TAXO" 2>/dev/null; rc=$?
  assert_equal "$rc" "41" "Linear API failure → exit 41"
}

run_test "missing project → exit 42"          test_missing_project_exits_42
run_test "missing project named on stderr"     test_missing_project_names_it_on_stderr
run_test "all projects present → exit 0"       test_all_present_exits_0
run_test "Linear API failure → exit 41"        test_linear_failure_exits_41

report
