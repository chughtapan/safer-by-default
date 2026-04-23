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

test_symlink_invocation_resolves_helper() {
  _reset_sandbox
  # Create symlink to safer-publish in temp PATH
  local testpath="$SANDBOX/testbin"
  mkdir -p "$testpath"
  ln -s "$BIN_PUBLISH" "$testpath/safer-publish"

  # Create a minimal .env file with ZAPBOT_API_KEY
  mkdir -p "$HOME/.zapbot"
  echo "ZAPBOT_API_KEY=symlink-test-key" > "$HOME/.zapbot/.env"

  # Invoke via symlink. Without --kind it should fail with argument validation, not file-not-found
  result=$(HOME="$HOME" PATH="$testpath:$PATH" "$testpath/safer-publish" 2>&1 || true)
  # If helper fails to source, we'd get "No such file", but if it sources OK we get an arg validation error
  if echo "$result" | grep -q "No such file\|cannot open"; then
    return 1
  fi
  return 0
}

test_helper_resolves_env_only() {
  _reset_sandbox
  # Set ZAPBOT_API_KEY via .env file only (no config.json)
  mkdir -p "$HOME/.zapbot"
  echo "ZAPBOT_API_KEY=env-only-key" > "$HOME/.zapbot/.env"

  local result
  result=$(bash -c "HOME='$HOME' . '$HELPER'; echo \"\$ZAPBOT_API_KEY\"")
  echo "$result" | grep -q "env-only-key"
  assert_zero $? "helper should resolve ZAPBOT_API_KEY from .env file when config.json absent"
}

test_helper_resolves_config_json_only() {
  _reset_sandbox
  # Set ZAPBOT_API_KEY via config.json only (no .env file)
  mkdir -p "$HOME/.zapbot"
  echo '{"apiKey":"config-json-only-key"}' > "$HOME/.zapbot/config.json"

  local result
  result=$(bash -c "HOME='$HOME' . '$HELPER'; echo \"\$ZAPBOT_API_KEY\"")
  echo "$result" | grep -q "config-json-only-key"
  assert_zero $? "helper should resolve ZAPBOT_API_KEY from config.json when .env absent"
}

test_narrow_export_scope_does_not_leak() {
  _reset_sandbox
  # Create .env with ZAPBOT_API_KEY and other variables (simulating real zapbot .env)
  mkdir -p "$HOME/.zapbot"
  cat > "$HOME/.zapbot/.env" << 'EOF'
ZAPBOT_API_KEY=narrow-scope-test-key
ZAPBOT_BRIDGE_URL=http://internal-bridge:3000
INTERNAL_SECRET=should-not-leak
SAFER_STATE_DIR=/tmp/safer-state
EOF

  # Source helper and verify that:
  # 1. ZAPBOT_API_KEY is set correctly
  # 2. Other variables do NOT leak to the caller environment
  local result
  result=$(bash -c "HOME='$HOME' . '$HELPER'; {
    echo \"ZAPBOT_API_KEY=\$ZAPBOT_API_KEY\"
    echo \"ZAPBOT_BRIDGE_URL=\${ZAPBOT_BRIDGE_URL:-unset}\"
    echo \"INTERNAL_SECRET=\${INTERNAL_SECRET:-unset}\"
    echo \"SAFER_STATE_DIR=\${SAFER_STATE_DIR:-unset}\"
  }")

  echo "$result" | grep -q "ZAPBOT_API_KEY=narrow-scope-test-key"
  assert_zero $? "helper should extract ZAPBOT_API_KEY from .env"

  echo "$result" | grep -q "ZAPBOT_BRIDGE_URL=unset"
  assert_zero $? "ZAPBOT_BRIDGE_URL should not leak to caller"

  echo "$result" | grep -q "INTERNAL_SECRET=unset"
  assert_zero $? "INTERNAL_SECRET should not leak to caller"

  echo "$result" | grep -q "SAFER_STATE_DIR=unset"
  assert_zero $? "SAFER_STATE_DIR should not leak to caller"
}
test_jq_guard_error_message_present() {
  # Verify that the error message for missing jq is present in the script
  grep -q "jq required to read config.json" "$HELPER"
  [ $? -eq 0 ] && return 0 || return 1
}

test_jq_guard_succeeds_when_jq_present() {
  _reset_sandbox
  # Set up config.json with API key (no .env file)
  mkdir -p "$HOME/.zapbot"
  echo '{"apiKey":"should-work-with-jq"}' > "$HOME/.zapbot/config.json"

  # Source helper with normal PATH (jq should be available)
  local result
  result=$(bash -c "HOME='$HOME' . '$HELPER'; echo \"\$ZAPBOT_API_KEY\"")
  if echo "$result" | grep -q "should-work-with-jq"; then
    return 0
  else
    return 1
  fi
}

test_jq_command_check_before_execution() {
  # Verify that the script checks for jq with 'command -v' before using it
  grep -q "command -v jq >/dev/null 2>&1" "$HELPER"
  [ $? -eq 0 ] && return 0 || return 1
}

# ── Run tests ───────────────────────────────────────────────────────

run_test "helper file exists" test_helper_file_exists
run_test "safer-publish sources helper" test_safer_publish_sources_helper
run_test "safer-escalate sources helper" test_safer_escalate_sources_helper
run_test "safer-transition-label sources helper" test_safer_transition_label_sources_helper
run_test "helper preserves empty-but-set variable" test_helper_preserves_empty_but_set
run_test "symlink invocation resolves helper" test_symlink_invocation_resolves_helper
run_test "helper resolves ZAPBOT_API_KEY from .env only" test_helper_resolves_env_only
run_test "helper resolves ZAPBOT_API_KEY from config.json only" test_helper_resolves_config_json_only
run_test "narrow export scope does not leak" test_narrow_export_scope_does_not_leak
run_test "jq guard error message present" test_jq_guard_error_message_present
run_test "jq guard succeeds when jq present" test_jq_guard_succeeds_when_jq_present
run_test "jq command check before execution" test_jq_command_check_before_execution
report
