#!/usr/bin/env bash
# cli_main: unknown subcommand → exit 1, usage printed.
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

BIN="$PLUGIN_DIR/bin/safer-linear-setup"

test_unknown_subcommand_exit_1() {
  local rc
  cli_main "does-not-exist" 2>/dev/null; rc=$?
  assert_equal "$rc" "1" "unknown subcommand → exit 1"
}

test_unknown_subcommand_prints_error() {
  local output
  output=$(cli_main "does-not-exist" 2>&1 || true)
  assert_contains "$output" "ERROR" "error message emitted for unknown subcommand"
}

test_no_subcommand_shows_help() {
  local output rc
  output=$(cli_main 2>&1); rc=$?
  assert_equal "$rc" "0" "no subcommand defaults to help, exit 0"
  assert_contains "$output" "Usage:" "usage text printed"
}

test_help_subcommand() {
  local output
  output=$(cli_main help 2>&1)
  assert_contains "$output" "assign-projects" "help lists assign-projects subcommand"
  assert_contains "$output" "drift-report" "help lists drift-report subcommand"
  assert_contains "$output" "bootstrap-verify" "help lists bootstrap-verify subcommand"
}

test_bin_shim_routes_unknown_subcommand() {
  local rc
  "$BIN" unknown-cmd 2>/dev/null; rc=$?
  assert_equal "$rc" "1" "bin shim: unknown subcommand → exit 1"
}

run_test "unknown subcommand → exit 1"              test_unknown_subcommand_exit_1
run_test "unknown subcommand → ERROR message"       test_unknown_subcommand_prints_error
run_test "no subcommand → help, exit 0"             test_no_subcommand_shows_help
run_test "help subcommand lists all subcommands"    test_help_subcommand
run_test "bin shim: unknown → exit 1"               test_bin_shim_routes_unknown_subcommand

report
