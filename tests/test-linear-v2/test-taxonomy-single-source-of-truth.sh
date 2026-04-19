#!/usr/bin/env bash
# Verifies that project names from the taxonomy do not appear as hard-coded
# string literals in bin/ or lib/ (outside the YAML file itself). Covers
# the spec invariant: "no second hard-coded list" (plan §7 traceability).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"
PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
# shellcheck disable=SC1091
source "$PLUGIN_DIR/lib/safer-linear/taxonomy.sh"

TAXO="$PLUGIN_DIR/config/linear-taxonomy.yaml"

test_bin_is_shim_not_taxonomy() {
  local bin_content
  bin_content=$(cat "$PLUGIN_DIR/bin/safer-linear-setup")
  # The v1 hard-coded project names in map_labels_to_project.
  # v2 bin is a 4-line shim with no project names.
  local rc=0
  local projects
  projects=$(taxonomy_projects "$TAXO")
  while IFS= read -r project; do
    [[ -z "$project" ]] && continue
    if printf '%s\n' "$bin_content" | grep -qF "$project"; then
      printf '    project name %q found in bin/safer-linear-setup\n' "$project"
      rc=1
    fi
  done <<< "$projects"
  return $rc
}

test_lib_modules_do_not_hardcode_project_names() {
  local rc=0
  local projects
  projects=$(taxonomy_projects "$TAXO")
  # Check lib files that contain logic (not taxonomy.sh which just parses)
  local files=(
    "$PLUGIN_DIR/lib/safer-linear/cli.sh"
    "$PLUGIN_DIR/lib/safer-linear/resolve.sh"
    "$PLUGIN_DIR/lib/safer-linear/drift.sh"
    "$PLUGIN_DIR/lib/safer-linear/linear-api.sh"
  )
  while IFS= read -r project; do
    [[ -z "$project" ]] && continue
    for f in "${files[@]}"; do
      if grep -qF "$project" "$f" 2>/dev/null; then
        printf '    project name %q found in %s\n' "$project" "$(basename "$f")"
        rc=1
      fi
    done
  done <<< "$projects"
  return $rc
}

test_taxonomy_yaml_is_readable() {
  local count
  count=$(taxonomy_projects "$TAXO" | wc -l)
  if [[ "$count" -lt 1 ]]; then
    echo "    taxonomy has no projects"
    return 1
  fi
  return 0
}

run_test "bin/safer-linear-setup contains no hard-coded project names" test_bin_is_shim_not_taxonomy
run_test "lib modules contain no hard-coded project names"             test_lib_modules_do_not_hardcode_project_names
run_test "taxonomy.yaml is readable and has projects"                  test_taxonomy_yaml_is_readable

report
