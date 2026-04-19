#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"
PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
# shellcheck disable=SC1091
source "$PLUGIN_DIR/lib/safer-linear/taxonomy.sh"

test_missing_file() {
  local rc
  validate_taxonomy "/tmp/does-not-exist-$$.yaml" 2>/dev/null; rc=$?
  assert_equal "$rc" "10" "missing file returns exit 10"
}

test_invalid_yaml() {
  local tmp; tmp=$(mktemp --suffix=.yaml)
  printf 'not: valid: yaml: {{{' > "$tmp"
  local rc
  validate_taxonomy "$tmp" 2>/dev/null; rc=$?
  rm -f "$tmp"
  assert_equal "$rc" "11" "non-YAML returns exit 11"
}

test_wrong_schema_version() {
  local tmp; tmp=$(mktemp --suffix=.yaml)
  cat > "$tmp" <<'YAML'
schemaVersion: 2
catchall: "SBD ops"
projects:
  - "SBD ops"
labelMap: []
YAML
  local rc
  validate_taxonomy "$tmp" 2>/dev/null; rc=$?
  rm -f "$tmp"
  assert_equal "$rc" "12" "wrong schemaVersion returns exit 12"
}

test_missing_catchall_key() {
  local tmp; tmp=$(mktemp --suffix=.yaml)
  cat > "$tmp" <<'YAML'
schemaVersion: 1
projects:
  - "SBD ops"
labelMap: []
YAML
  local rc
  validate_taxonomy "$tmp" 2>/dev/null; rc=$?
  rm -f "$tmp"
  assert_equal "$rc" "12" "missing catchall key returns exit 12"
}

test_catchall_not_in_projects() {
  local tmp; tmp=$(mktemp --suffix=.yaml)
  cat > "$tmp" <<'YAML'
schemaVersion: 1
catchall: "Missing project"
projects:
  - "SBD ops"
labelMap: []
YAML
  local rc
  validate_taxonomy "$tmp" 2>/dev/null; rc=$?
  rm -f "$tmp"
  assert_equal "$rc" "12" "catchall not in projects returns exit 12"
}

test_duplicate_project_names() {
  local tmp; tmp=$(mktemp --suffix=.yaml)
  cat > "$tmp" <<'YAML'
schemaVersion: 1
catchall: "SBD ops"
projects:
  - "SBD ops"
  - "SBD ops"
labelMap: []
YAML
  local rc
  validate_taxonomy "$tmp" 2>/dev/null; rc=$?
  rm -f "$tmp"
  assert_equal "$rc" "12" "duplicate projects returns exit 12"
}

test_valid_taxonomy_passes() {
  local rc
  validate_taxonomy "$PLUGIN_DIR/config/linear-taxonomy.yaml" 2>/dev/null; rc=$?
  assert_equal "$rc" "0" "valid taxonomy returns exit 0"
}

run_test "missing file → exit 10"              test_missing_file
run_test "invalid YAML → exit 11"              test_invalid_yaml
run_test "wrong schemaVersion → exit 12"       test_wrong_schema_version
run_test "missing catchall key → exit 12"      test_missing_catchall_key
run_test "catchall not in projects → exit 12"  test_catchall_not_in_projects
run_test "duplicate project names → exit 12"   test_duplicate_project_names
run_test "valid taxonomy → exit 0"             test_valid_taxonomy_passes

report
