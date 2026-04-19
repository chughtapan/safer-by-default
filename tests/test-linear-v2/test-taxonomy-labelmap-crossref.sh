#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"
PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
# shellcheck disable=SC1091
source "$PLUGIN_DIR/lib/safer-linear/taxonomy.sh"

test_labelmap_project_not_in_projects() {
  local tmp; tmp=$(mktemp --suffix=.yaml)
  cat > "$tmp" <<'YAML'
schemaVersion: 1
catchall: "SBD ops"
projects:
  - "SBD ops"
labelMap:
  - label: "some-label"
    project: "NonExistent project"
YAML
  local rc
  validate_taxonomy "$tmp" 2>/dev/null; rc=$?
  rm -f "$tmp"
  assert_equal "$rc" "12" "labelMap project not in projects → exit 12"
}

test_duplicate_label_in_labelmap() {
  local tmp; tmp=$(mktemp --suffix=.yaml)
  cat > "$tmp" <<'YAML'
schemaVersion: 1
catchall: "SBD ops"
projects:
  - "SBD ops"
  - "Tracking infra"
labelMap:
  - label: "safer:spike"
    project: "Tracking infra"
  - label: "safer:spike"
    project: "SBD ops"
YAML
  local rc
  validate_taxonomy "$tmp" 2>/dev/null; rc=$?
  rm -f "$tmp"
  assert_equal "$rc" "12" "duplicate label in labelMap → exit 12"
}

test_valid_labelmap_crossrefs() {
  local tmp; tmp=$(mktemp --suffix=.yaml)
  cat > "$tmp" <<'YAML'
schemaVersion: 1
catchall: "SBD ops"
projects:
  - "SBD ops"
  - "Tracking infra"
  - "Moltzap migration"
labelMap:
  - label: "safer:spike"
    project: "Tracking infra"
  - label: "moltzap-migration"
    project: "Moltzap migration"
YAML
  local rc
  validate_taxonomy "$tmp" 2>/dev/null; rc=$?
  rm -f "$tmp"
  assert_equal "$rc" "0" "valid labelMap cross-refs → exit 0"
}

test_labelmap_output_order_preserved() {
  local tmp; tmp=$(mktemp --suffix=.yaml)
  cat > "$tmp" <<'YAML'
schemaVersion: 1
catchall: "SBD ops"
projects:
  - "SBD ops"
  - "Tracking infra"
  - "Moltzap migration"
labelMap:
  - label: "first-label"
    project: "Tracking infra"
  - label: "second-label"
    project: "Moltzap migration"
YAML
  local map
  map=$(taxonomy_label_map "$tmp")
  rm -f "$tmp"
  local first_line; first_line=$(printf '%s\n' "$map" | head -1)
  assert_contains "$first_line" "first-label" "first labelMap entry appears first in output"
}

run_test "labelMap project not in projects → exit 12" test_labelmap_project_not_in_projects
run_test "duplicate label in labelMap → exit 12"       test_duplicate_label_in_labelmap
run_test "valid labelMap cross-refs → exit 0"          test_valid_labelmap_crossrefs
run_test "labelMap output order preserved"              test_labelmap_output_order_preserved

report
