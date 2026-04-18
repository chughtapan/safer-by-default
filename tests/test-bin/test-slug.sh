#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
BIN="$PLUGIN_DIR/bin/safer-slug"

test_in_repo() {
  (cd "$PLUGIN_DIR" && out=$("$BIN")) >/dev/null 2>&1 || true
  out=$(cd "$PLUGIN_DIR" && "$BIN")
  assert_matches "$out" '^SLUG=[a-zA-Z0-9._-]+'
}

test_outside_repo() {
  local tmp
  tmp=$(mktemp -d)
  local out
  out=$(cd "$tmp" && "$BIN" 2>/dev/null)
  rm -rf "$tmp"
  assert_matches "$out" '^SLUG=(unknown|[a-zA-Z0-9._-]+)$'
}

run_test "safer-slug runs in a git repo" test_in_repo
run_test "safer-slug handles missing remote" test_outside_repo
report
