#!/usr/bin/env bash
# Tests for safer-linear-setup v2. Ported from v1 to use v2 module APIs.
# Each test covers the same behavior as the original; function names map
# to v2 equivalents (resolve_project, linear_get_parent_project, etc.).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
BIN="$PLUGIN_DIR/bin/safer-linear-setup"
TAXO="$PLUGIN_DIR/config/linear-taxonomy.yaml"

# shellcheck disable=SC1091
source "$PLUGIN_DIR/lib/safer-linear/taxonomy.sh"
source "$PLUGIN_DIR/lib/safer-linear/linear-api.sh"
source "$PLUGIN_DIR/lib/safer-linear/resolve.sh"
source "$PLUGIN_DIR/lib/safer-linear/drift.sh"
source "$PLUGIN_DIR/lib/safer-linear/cli.sh"

export _SAFER_TAXO_PATH="$TAXO"

# Helper: mock curl to handle projects-list and issue-lookup queries.
# Used by subprocess tests; curl is not redefined by lib files so the mock sticks.
_mock_curl_linear() {
  curl() {
    local data="" out_file=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -d) data="$2"; shift 2 ;;
        -o) out_file="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    local body
    # Detect projects-list query (from bootstrap + linear_list_projects)
    if printf '%s' "$data" | jq -r '.query' 2>/dev/null | grep -q "projects("; then
      body='{"data":{"projects":{"nodes":[
        {"id":"p1","name":"Tracking infra"},
        {"id":"p2","name":"SBD ops"},
        {"id":"p3","name":"Linear integration"},
        {"id":"p4","name":"Testing doctrine"},
        {"id":"p5","name":"Reentrance Tier-1"},
        {"id":"p6","name":"Community feedback agents"},
        {"id":"p7","name":"Moltzap migration"}
      ]}}}'
    else
      body='{"data":{"issues":{"nodes":[]}}}'
    fi
    [[ -n "$out_file" ]] && printf '%s\n' "$body" > "$out_file"
    printf '200'
  }
  export -f curl
}

test_parent_ref_resolution() {
  linear_get_parent_project() {
    if [[ "$1" == "999" ]]; then echo "Moltzap migration"; else echo ""; fi
  }
  export -f linear_get_parent_project

  local body="Parent: #999

This is a sub-issue."
  local project
  project=$(resolve_project 100 "$body" "")
  assert_equal "$project" "Moltzap migration" "parent ref resolves to correct project"
}

test_manual_override_wins() {
  linear_get_parent_project() { echo "Tracking infra"; }
  export -f linear_get_parent_project

  local body="Linear-project: Moltzap migration
Parent: #888

This is a sub-issue."
  local project
  project=$(resolve_project 100 "$body" "")
  assert_equal "$project" "Moltzap migration" "manual override wins"
}

test_catchall_fallback() {
  linear_get_parent_project() { echo ""; }
  export -f linear_get_parent_project

  local body="This is a standalone issue with no parent or project declaration."
  local project
  project=$(resolve_project 100 "$body" "")
  assert_equal "$project" "" "issue with no parent resolves to empty for catchall"
}

test_label_mapping() {
  linear_get_parent_project() { echo ""; }
  export -f linear_get_parent_project

  local project
  project=$(resolve_project 100 "Random issue body" "safer:spike")
  assert_equal "$project" "Tracking infra" "safer:spike label maps to Tracking infra"
}

test_parent_heading_resolution() {
  linear_get_parent_project() {
    if [[ "$1" == "777" ]]; then echo "Tracking infra"; else echo ""; fi
  }
  export -f linear_get_parent_project

  local body="## Parent
#777

Some description."
  local project
  project=$(resolve_project 200 "$body" "")
  assert_equal "$project" "Tracking infra" "parent heading ## Parent inference resolves to correct project"
}

test_catchall_assigned_in_loop() {
  export LINEAR_API_KEY="test-key"

  # Mock gh to return a standalone issue
  gh() {
    printf '%s\n' '[{"number":55,"body":"Standalone issue","labels":[]}]'
  }
  export -f gh

  # Mock curl (subprocess-safe: curl is never redefined by sourced lib files)
  _mock_curl_linear

  local output
  output=$("$BIN" assign-projects --all --taxonomy "$TAXO" 2>&1 || true)
  assert_contains "$output" "catchall=1" "catchall counter incremented when no project signals match"
  assert_contains "$output" "RESULT:" "main loop completes and prints result line"
}

test_counter_increments_complete_loop() {
  export LINEAR_API_KEY="test-key"

  gh() {
    printf '%s\n' '[{"number":10,"body":"Test issue","labels":[]}]'
  }
  export -f gh

  _mock_curl_linear

  local output
  output=$("$BIN" assign-projects --all --taxonomy "$TAXO" 2>&1 || true)
  assert_contains "$output" "RESULT:" "script completes without aborting on first counter increment"
}

test_idempotency_skips_already_assigned() {
  linear_get_parent_project() { echo ""; }
  export -f linear_get_parent_project

  local project
  project=$(resolve_project 99 "" "safer:spike")
  assert_equal "$project" "Tracking infra" "label resolves to Tracking infra"

  local linear_issue='{"id":"lin-99","project":{"id":"p1","name":"Tracking infra"}}'
  local current_project
  current_project=$(printf '%s\n' "$linear_issue" | jq -r '.project.name // ""')
  assert_equal "$current_project" "Tracking infra" "Linear reports issue already in Tracking infra"
  assert_equal "$project" "$current_project" "project matches current — issue would be skipped (idempotent)"
}

test_assign_projects_requires_api_key() {
  unset LINEAR_API_KEY || true
  local output
  output=$("$BIN" assign-projects --all --taxonomy "$TAXO" 2>&1 || true)
  assert_contains "$output" "LINEAR_API_KEY" "validates API key presence"
}

test_assign_projects_requires_flags() {
  export LINEAR_API_KEY="test-key"
  local output
  output=$("$BIN" assign-projects --taxonomy "$TAXO" 2>&1 || true)
  assert_contains "$output" "ERROR" "requires --all or --since flag"
}

test_assign_projects_mutually_exclusive_flags() {
  export LINEAR_API_KEY="test-key"
  local output
  output=$("$BIN" assign-projects --all --since 5m --taxonomy "$TAXO" 2>&1 || true)
  assert_contains "$output" "mutually exclusive" "rejects both --all and --since"
}

test_since_format_validation() {
  export LINEAR_API_KEY="test-key"
  local output
  output=$("$BIN" assign-projects --since foo --taxonomy "$TAXO" 2>&1 || true)
  assert_contains "$output" "ERROR: --since DURATION" "rejects invalid --since format"
}

test_authorization_header_no_bearer_prefix() {
  export LINEAR_API_KEY="lin_api_test123"
  local header_file
  header_file=$(mktemp)
  # shellcheck disable=SC2317
  curl() {
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == -H && "${2:-}" == Authorization:* ]]; then
        printf '%s\n' "${2#Authorization: }" > "$header_file"
        shift 2; continue
      fi
      if [[ "$1" == -o && -n "${2:-}" ]]; then
        printf '{"data":{"ok":true}}\n' > "$2"
        shift 2; continue
      fi
      shift
    done
    printf '200'
  }
  export -f curl

  linear_graphql 'query { test }' >/dev/null 2>/dev/null

  if [[ ! -s "$header_file" ]]; then
    rm -f "$header_file"
    printf 'Authorization header not captured\n'
    return 1
  fi

  local auth_value
  auth_value=$(cat "$header_file")
  rm -f "$header_file"

  if printf '%s' "$auth_value" | grep -q "Bearer "; then
    printf 'Authorization header contains Bearer prefix: %s\n' "$auth_value"
    return 1
  fi
  assert_equal "$auth_value" "lin_api_test123" "Authorization header is raw API key, no Bearer prefix"
}

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
run_test "Authorization header has no Bearer prefix" test_authorization_header_no_bearer_prefix

report
