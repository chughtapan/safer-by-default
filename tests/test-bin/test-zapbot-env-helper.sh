#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
HELPER="$PLUGIN_DIR/bin/_safer-zapbot-env.sh"

# ── Sandbox setup ───────────────────────────────────────────────────

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

export HOME="$SANDBOX/home"
mkdir -p "$HOME/.zapbot"

_reset_sandbox() {
  rm -rf "$HOME/.zapbot"
  mkdir -p "$HOME/.zapbot"
  unset ZAPBOT_API_KEY 2>/dev/null || true
}

# ── Tests ───────────────────────────────────────────────────────────

test_helper_file_exists() {
  assert_file_exists "$HELPER" "helper file exists"
}

# C1: config.json apiKey string → exported
test_config_json_string_exported() {
  _reset_sandbox
  echo '{"apiKey":"test-api-key"}' > "$HOME/.zapbot/config.json"
  local result
  result=$(bash -c "HOME='$HOME' . '$HELPER'; echo \"\$ZAPBOT_API_KEY\"")
  echo "$result" | grep -q "test-api-key"
  assert_zero $? "helper should export apiKey string from config.json"
}

# C2: config.json apiKey missing → loud exit with error
test_config_json_missing_apikey_loud_fail() {
  _reset_sandbox
  echo '{"other":"value"}' > "$HOME/.zapbot/config.json"
  bash -c "HOME='$HOME' . '$HELPER'" 2>/dev/null
  local rc=$?
  assert_nonzero $rc "helper should exit nonzero when apiKey missing from config.json"
}

# C3: config.json apiKey non-string type → loud exit with error
test_config_json_apikey_non_string_loud_fail() {
  _reset_sandbox
  echo '{"apiKey":42}' > "$HOME/.zapbot/config.json"
  bash -c "HOME='$HOME' . '$HELPER'" 2>/dev/null
  local rc=$?
  assert_nonzero $rc "helper should exit nonzero when apiKey is not a string"
}

# C4: config.json apiKey empty string → loud exit with error
test_config_json_apikey_empty_string_loud_fail() {
  _reset_sandbox
  echo '{"apiKey":""}' > "$HOME/.zapbot/config.json"
  bash -c "HOME='$HOME' . '$HELPER'" 2>/dev/null
  local rc=$?
  assert_nonzero $rc "helper should exit nonzero when apiKey is an empty string"
}

# C5: jq missing + config.json present → loud exit with "jq required" error
test_jq_missing_loud_fail() {
  _reset_sandbox
  echo '{"apiKey":"test-key"}' > "$HOME/.zapbot/config.json"
  local tmpbin
  tmpbin=$(mktemp -d)
  HOME="$HOME" PATH="$tmpbin" /bin/bash << TESTEOF >/dev/null 2>&1
. '$HELPER'
TESTEOF
  local rc=$?
  rm -rf "$tmpbin"
  assert_nonzero $rc "helper should exit nonzero when jq is missing"
}

# C6: config.json missing → loud exit with "not found" error
test_config_json_missing_loud_fail() {
  _reset_sandbox
  rm -rf "$HOME/.zapbot/config.json"
  bash -c "HOME='$HOME' . '$HELPER'" 2>/dev/null
  local rc=$?
  assert_nonzero $rc "helper should exit nonzero when config.json not found"
}

# C7: config.json malformed JSON → loud exit (jq exits nonzero)
test_config_json_malformed_loud_fail() {
  _reset_sandbox
  echo '{invalid json}' > "$HOME/.zapbot/config.json"
  bash -c "HOME='$HOME' . '$HELPER'" 2>/dev/null
  local rc=$?
  assert_nonzero $rc "helper should exit nonzero when config.json is malformed"
}

# NEW: pre-existing ZAPBOT_API_KEY gets OVERWRITTEN by config.json value
test_explicit_env_overwritten_by_config_json() {
  _reset_sandbox
  echo '{"apiKey":"config-json-value"}' > "$HOME/.zapbot/config.json"
  local result
  result=$(HOME="$HOME" ZAPBOT_API_KEY='old-value' /bin/bash << TESTEOF
. '$HELPER'
echo "\$ZAPBOT_API_KEY"
TESTEOF
)
  echo "$result" | grep -q "config-json-value"
  assert_zero $? "helper should overwrite pre-existing ZAPBOT_API_KEY with config.json value"
}

# Verify error messages are loud (go to stderr)
test_error_messages_to_stderr() {
  _reset_sandbox
  echo '{"other":"value"}' > "$HOME/.zapbot/config.json"
  local result
  result=$(bash -c "HOME='$HOME' . '$HELPER' 2>&1")
  echo "$result" | grep -q "apiKey missing or not a non-empty string"
  assert_zero $? "helper should output descriptive error message to stderr"
}

# ── Run tests ───────────────────────────────────────────────────────

run_test "helper file exists" test_helper_file_exists
run_test "C1: config.json apiKey string exported" test_config_json_string_exported
run_test "C2: config.json apiKey missing loud fail" test_config_json_missing_apikey_loud_fail
run_test "C3: config.json apiKey non-string loud fail" test_config_json_apikey_non_string_loud_fail
run_test "C4: config.json apiKey empty string loud fail" test_config_json_apikey_empty_string_loud_fail
run_test "C5: jq missing loud fail" test_jq_missing_loud_fail
run_test "C6: config.json missing loud fail" test_config_json_missing_loud_fail
run_test "C7: config.json malformed loud fail" test_config_json_malformed_loud_fail
run_test "explicit env overwritten by config.json" test_explicit_env_overwritten_by_config_json
run_test "error messages to stderr" test_error_messages_to_stderr
report
