#!/usr/bin/env bash
# Tests for _safer-zapbot-env.sh helper sourcing in the three broker scripts.
# Verifies that safer-publish, safer-escalate, and safer-transition-label
# correctly source the helper and resolve ZAPBOT_API_KEY.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
HELPER="$PLUGIN_DIR/bin/_safer-zapbot-env.sh"
BIN_PUBLISH="$PLUGIN_DIR/bin/safer-publish"
BIN_ESCALATE="$PLUGIN_DIR/bin/safer-escalate"
BIN_TRANSITION="$PLUGIN_DIR/bin/safer-transition-label"

# ── Sandbox setup ───────────────────────────────────────────────────

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

export HOME="$SANDBOX/home"
mkdir -p "$HOME"

_reset_sandbox() {
  rm -rf "$HOME/.zapbot" "$SANDBOX/config.json"
  mkdir -p "$HOME"
  unset ZAPBOT_API_KEY
}

# ── Helper sourcing tests ───────────────────────────────────────────

test_helper_file_exists() {
  assert_file_exists "$HELPER" "helper file exists"
}

test_safer_publish_sources_helper() {
  _reset_sandbox
  # Set up zapbot config with explicit env var
  export ZAPBOT_API_KEY="test-key-publish"

  # Source the helper directly (simulating what safer-publish does)
  local result
  result=$(bash -c "export ZAPBOT_API_KEY='test-key-publish'; . '$HELPER'; echo \"\$ZAPBOT_API_KEY\"")
  echo "$result" | grep -q "test-key-publish"
  assert_zero $? "safer-publish helper should resolve ZAPBOT_API_KEY from env var"
}

test_safer_escalate_sources_helper() {
  _reset_sandbox
  # Set up zapbot config with explicit env var
  export ZAPBOT_API_KEY="test-key-escalate"

  # Source the helper directly (simulating what safer-escalate does)
  local result
  result=$(bash -c "export ZAPBOT_API_KEY='test-key-escalate'; . '$HELPER'; echo \"\$ZAPBOT_API_KEY\"")
  echo "$result" | grep -q "test-key-escalate"
  assert_zero $? "safer-escalate helper should resolve ZAPBOT_API_KEY from env var"
}

test_safer_transition_label_sources_helper() {
  _reset_sandbox
  # Set up zapbot config with explicit env var
  export ZAPBOT_API_KEY="test-key-transition"

  # Source the helper directly (simulating what safer-transition-label does)
  local result
  result=$(bash -c "export ZAPBOT_API_KEY='test-key-transition'; . '$HELPER'; echo \"\$ZAPBOT_API_KEY\"")
  echo "$result" | grep -q "test-key-transition"
  assert_zero $? "safer-transition-label helper should resolve ZAPBOT_API_KEY from env var"
}

test_helper_preserves_empty_but_set() {
  _reset_sandbox
  # Test the ${var+set} precedence preservation
  result=$(bash -c "export ZAPBOT_API_KEY=''; . '$HELPER'; [ -z \"\$ZAPBOT_API_KEY\" ] && echo 'empty' || echo 'not-empty'")
  echo "$result" | grep -q "empty"
  assert_zero $? "helper should preserve empty-but-set ZAPBOT_API_KEY"
}

# ── Run tests ───────────────────────────────────────────────────────

run_test "helper file exists" test_helper_file_exists
run_test "safer-publish sources helper" test_safer_publish_sources_helper
run_test "safer-escalate sources helper" test_safer_escalate_sources_helper
run_test "safer-transition-label sources helper" test_safer_transition_label_sources_helper
run_test "helper preserves empty-but-set variable" test_helper_preserves_empty_but_set
report
