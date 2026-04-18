#!/usr/bin/env bash
# Unit tests for bin/safer-publish bot-token routing (spec #15, design #19).
# Covers: detect_zapbot, resolve_bridge_url, fetch_broker_token,
# verify_attribution, resolve_identity_mode, handle_fallback_flags, plus the
# three integration branches (strict fail, user-fallback warn, bot success).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
BIN="$PLUGIN_DIR/bin/safer-publish"

# ── Sandbox setup ───────────────────────────────────────────────────

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

export HOME="$SANDBOX/home"
mkdir -p "$HOME"

# Mock bin on PATH for curl + gh stubs. Preserve real PATH for jq, mktemp, etc.
export MOCK_BIN="$SANDBOX/mock-bin"
mkdir -p "$MOCK_BIN"
ORIG_PATH="$PATH"
export PATH="$MOCK_BIN:$PATH"

# Scratchpad the mocks use to record calls.
export MOCK_LOG="$SANDBOX/mock.log"

_reset_sandbox() {
  rm -rf "$HOME"
  mkdir -p "$HOME"
  rm -f "$MOCK_LOG"
  rm -f "$MOCK_BIN/curl" "$MOCK_BIN/gh"
  unset ZAPBOT_API_KEY ZAPBOT_BRIDGE_URL
}

# Install a curl stub. $1 = status code, $2 = body.
_mock_curl() {
  local status="$1" body="$2"
  cat > "$MOCK_BIN/curl" <<EOF
#!/usr/bin/env bash
# Parse -o <outfile> so the caller gets the body.
outfile=""
args=("\$@")
for i in "\${!args[@]}"; do
  if [ "\${args[\$i]}" = "-o" ]; then
    outfile="\${args[\$((i+1))]}"
  fi
done
echo "curl \$*" >> "$MOCK_LOG"
if [ -n "\$outfile" ]; then
  printf '%s' '$body' > "\$outfile"
fi
printf '%s' '$status'
exit 0
EOF
  chmod +x "$MOCK_BIN/curl"
}

# Install a curl stub that simulates TCP failure (status "000", rc nonzero).
_mock_curl_tcp_fail() {
  cat > "$MOCK_BIN/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >> "$MOCK_LOG"
printf '000'
exit 7
EOF
  chmod +x "$MOCK_BIN/curl"
}

# Install a gh stub. $1 = stdout text to echo, $2 = exit code (default 0).
_mock_gh() {
  local out="$1" rc="${2:-0}"
  cat > "$MOCK_BIN/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$*" >> "$MOCK_LOG"
# Pass-through for 'gh api <path> --jq .user.type' — echo whatever was staged
# in MOCK_USER_TYPE (default: "Bot").
for a in "\$@"; do
  if [ "\$a" = "api" ]; then
    echo "\${MOCK_USER_TYPE:-Bot}"
    exit 0
  fi
done
printf '%s\n' '$out'
exit $rc
EOF
  chmod +x "$MOCK_BIN/gh"
}

_source_publish() {
  # shellcheck disable=SC1090
  SAFER_PUBLISH_SOURCE=1 source "$BIN"
}

# ── detect_zapbot ───────────────────────────────────────────────────

test_detect_zapbot_env() {
  _reset_sandbox
  touch "$HOME/.zapbot/.env" 2>/dev/null || { mkdir -p "$HOME/.zapbot" && touch "$HOME/.zapbot/.env"; }
  _source_publish
  detect_zapbot
  assert_equal "$ZAPBOT_DETECTED" "1" "detect .env"
}

test_detect_zapbot_config_json() {
  _reset_sandbox
  mkdir -p "$HOME/.zapbot"
  echo '{}' > "$HOME/.zapbot/config.json"
  _source_publish
  detect_zapbot
  assert_equal "$ZAPBOT_DETECTED" "1" "detect config.json"
}

test_detect_zapbot_absent() {
  _reset_sandbox
  _source_publish
  detect_zapbot
  assert_equal "$ZAPBOT_DETECTED" "0" "no zapbot → 0"
}

# ── resolve_bridge_url ──────────────────────────────────────────────

test_resolve_bridge_default() {
  _reset_sandbox
  _source_publish
  cd "$SANDBOX"
  local url
  url=$(resolve_bridge_url)
  assert_equal "$url" "http://localhost:3000" "default URL"
}

test_resolve_bridge_env_override() {
  _reset_sandbox
  export ZAPBOT_BRIDGE_URL="http://otherhost:9000"
  _source_publish
  cd "$SANDBOX"
  local url
  url=$(resolve_bridge_url)
  unset ZAPBOT_BRIDGE_URL
  assert_equal "$url" "http://otherhost:9000" "env override"
}

test_resolve_bridge_yaml_beats_env() {
  _reset_sandbox
  export ZAPBOT_BRIDGE_URL="http://env-host:9000"
  local dir="$SANDBOX/yaml-dir"
  mkdir -p "$dir"
  echo "bridge_url: http://yaml-host:8080" > "$dir/agent-orchestrator.yaml"
  _source_publish
  cd "$dir"
  local url
  url=$(resolve_bridge_url)
  unset ZAPBOT_BRIDGE_URL
  cd "$SANDBOX"
  assert_equal "$url" "http://yaml-host:8080" "yaml beats env"
}

# ── fetch_broker_token ──────────────────────────────────────────────

test_fetch_token_happy_path() {
  _reset_sandbox
  export ZAPBOT_API_KEY="test-key"
  _mock_curl 200 '{"token":"ghs_abc123","expires_at":"2026-04-18T01:00:00Z"}'
  _source_publish
  local token rc
  token=$(fetch_broker_token "http://localhost:3000"); rc=$?
  assert_equal "$rc" "0" "ok rc" || return 1
  assert_equal "$token" "ghs_abc123" "token extracted"
}

test_fetch_token_tcp_fail_returns_10() {
  _reset_sandbox
  export ZAPBOT_API_KEY="test-key"
  _mock_curl_tcp_fail
  _source_publish
  local err rc
  err=$(fetch_broker_token "http://localhost:3000" 2>&1 >/dev/null); rc=$?
  assert_equal "$rc" "10" "TCP fail rc" || return 1
  assert_contains "$err" "connection_refused" "TCP stderr"
}

test_fetch_token_401_returns_11() {
  _reset_sandbox
  export ZAPBOT_API_KEY="test-key"
  _mock_curl 401 '{"error":{"type":"unauthorized","message":"x","status":401}}'
  _source_publish
  local rc
  fetch_broker_token "http://localhost:3000" 2>/dev/null >/dev/null; rc=$?
  assert_equal "$rc" "11" "401 rc"
}

test_fetch_token_409_returns_12() {
  _reset_sandbox
  export ZAPBOT_API_KEY="test-key"
  _mock_curl 409 '{"error":"app_not_configured","message":"x"}'
  _source_publish
  local rc
  fetch_broker_token "http://localhost:3000" 2>/dev/null >/dev/null; rc=$?
  assert_equal "$rc" "12" "409 rc"
}

test_fetch_token_500_returns_13() {
  _reset_sandbox
  export ZAPBOT_API_KEY="test-key"
  _mock_curl 503 '{"error":"internal_error","message":"x"}'
  _source_publish
  local rc
  fetch_broker_token "http://localhost:3000" 2>/dev/null >/dev/null; rc=$?
  assert_equal "$rc" "13" "5xx rc"
}

test_fetch_token_schema_invalid_returns_14() {
  _reset_sandbox
  export ZAPBOT_API_KEY="test-key"
  _mock_curl 200 '{"wrong":"shape"}'
  _source_publish
  local err rc
  err=$(fetch_broker_token "http://localhost:3000" 2>&1 >/dev/null); rc=$?
  assert_equal "$rc" "14" "schema rc" || return 1
  assert_contains "$err" "schema_invalid" "schema stderr"
}

# ── handle_fallback_flags ───────────────────────────────────────────

test_flags_default_both_zero() {
  _reset_sandbox
  _source_publish
  handle_fallback_flags --kind issue --title t
  assert_equal "$SAFER_ALLOW_PAT_FALLBACK" "0" "default pat=0" || return 1
  assert_equal "$SAFER_ATTRIBUTE_TO_USER" "0" "default user=0" || return 1
  assert_equal "${SAFER_RESIDUAL_ARGS[0]}" "--kind" "residual[0]" || return 1
  assert_equal "${SAFER_RESIDUAL_ARGS[1]}" "issue" "residual[1]" || return 1
  assert_equal "${#SAFER_RESIDUAL_ARGS[@]}" "4" "4 residual"
}

test_flags_pat_consumed() {
  _reset_sandbox
  _source_publish
  handle_fallback_flags --allow-pat-fallback --kind issue
  assert_equal "$SAFER_ALLOW_PAT_FALLBACK" "1" "pat set" || return 1
  assert_equal "${#SAFER_RESIDUAL_ARGS[@]}" "2" "flag stripped"
}

test_flags_attribute_consumed() {
  _reset_sandbox
  _source_publish
  handle_fallback_flags --attribute-to-user --kind comment
  assert_equal "$SAFER_ATTRIBUTE_TO_USER" "1" "user attr set"
}

test_flags_both_together_returns_22() {
  _reset_sandbox
  _source_publish
  local rc err
  err=$(handle_fallback_flags --allow-pat-fallback --attribute-to-user 2>&1); rc=$?
  assert_equal "$rc" "22" "conflict rc" || return 1
  assert_contains "$err" "mutually exclusive" "stderr"
}

# ── resolve_identity_mode ───────────────────────────────────────────

test_mode_no_detection_user() {
  _reset_sandbox
  _source_publish
  ZAPBOT_DETECTED=0
  SAFER_ATTRIBUTE_TO_USER=0
  SAFER_ALLOW_PAT_FALLBACK=0
  local m
  m=$(resolve_identity_mode "na")
  assert_equal "$m" "user" "D=0 → user"
}

test_mode_detected_bot_hit() {
  _reset_sandbox
  _source_publish
  ZAPBOT_DETECTED=1
  SAFER_ATTRIBUTE_TO_USER=0
  SAFER_ALLOW_PAT_FALLBACK=0
  local m
  m=$(resolve_identity_mode "hit")
  assert_equal "$m" "bot" "D=1 hit → bot"
}

test_mode_detected_miss_strict_fail() {
  _reset_sandbox
  _source_publish
  ZAPBOT_DETECTED=1
  SAFER_ATTRIBUTE_TO_USER=0
  SAFER_ALLOW_PAT_FALLBACK=0
  local m
  m=$(resolve_identity_mode "miss")
  assert_equal "$m" "strict-fail" "D=1 miss strict → fail"
}

test_mode_detected_miss_allow_pat() {
  _reset_sandbox
  _source_publish
  ZAPBOT_DETECTED=1
  SAFER_ATTRIBUTE_TO_USER=0
  SAFER_ALLOW_PAT_FALLBACK=1
  local m
  m=$(resolve_identity_mode "miss")
  assert_equal "$m" "user-fallback" "D=1 miss + F=1 → user-fallback"
}

test_mode_attribute_to_user_forces_user() {
  _reset_sandbox
  _source_publish
  ZAPBOT_DETECTED=1
  SAFER_ATTRIBUTE_TO_USER=1
  SAFER_ALLOW_PAT_FALLBACK=0
  local m
  m=$(resolve_identity_mode "hit")
  assert_equal "$m" "user" "U=1 → user"
}

# ── verify_attribution ──────────────────────────────────────────────

test_verify_attribution_bot_passes() {
  _reset_sandbox
  export MOCK_USER_TYPE="Bot"
  _mock_gh "unused"
  _source_publish
  local rc
  verify_attribution "https://github.com/o/r/issues/5" >/dev/null 2>&1; rc=$?
  assert_equal "$rc" "0" "bot passes"
}

test_verify_attribution_user_fails_20() {
  _reset_sandbox
  export MOCK_USER_TYPE="User"
  _mock_gh "unused"
  _source_publish
  local rc err
  err=$(verify_attribution "https://github.com/o/r/issues/5" 2>&1); rc=$?
  assert_equal "$rc" "20" "user type fails" || return 1
  assert_contains "$err" "attribution verify failed" "stderr msg"
}

# ── End-to-end flow: no zapbot → runs gh directly, no broker call ───

test_e2e_no_zapbot_user_silent() {
  _reset_sandbox
  _mock_gh "https://github.com/o/r/issues/42"
  local out rc
  out=$("$BIN" --kind comment --issue 42 --body "hi" 2>&1); rc=$?
  assert_equal "$rc" "0" "exit ok" || return 1
  assert_contains "$out" "https://github.com/o/r/issues/42" "resource url echoed" || return 1
  # No curl should have been invoked (broker path skipped).
  if [ -f "$MOCK_LOG" ] && grep -q "^curl" "$MOCK_LOG"; then
    echo "    FAIL: unexpected broker call when zapbot absent"
    return 1
  fi
  return 0
}

# ── End-to-end: zapbot detected + broker hit → bot mode + verify ────

test_e2e_bot_success_exports_gh_token() {
  _reset_sandbox
  mkdir -p "$HOME/.zapbot"
  touch "$HOME/.zapbot/.env"
  export ZAPBOT_API_KEY="test-key"
  export MOCK_USER_TYPE="Bot"
  _mock_curl 200 '{"token":"ghs_botsecret","expires_at":"2026-04-18T01:00:00Z"}'
  _mock_gh "https://github.com/o/r/issues/7"
  local out rc
  out=$("$BIN" --kind comment --issue 7 --body "hi" 2>&1); rc=$?
  assert_equal "$rc" "0" "bot mode success" || return 1
  # Broker was called.
  assert_contains "$(cat "$MOCK_LOG")" "curl" "broker invoked" || return 1
  # verify_attribution was called (gh api ...).
  assert_contains "$(cat "$MOCK_LOG")" "api " "verify_attribution called" || return 1
  return 0
}

# ── End-to-end: zapbot detected + broker TCP fail + strict → exit 10 ─

test_e2e_strict_fail_exits_10_with_ux_block() {
  _reset_sandbox
  mkdir -p "$HOME/.zapbot"
  touch "$HOME/.zapbot/.env"
  export ZAPBOT_API_KEY="test-key"
  _mock_curl_tcp_fail
  _mock_gh "unused"
  local out rc
  out=$("$BIN" --kind comment --issue 7 --body "hi" 2>&1); rc=$?
  assert_equal "$rc" "10" "strict exit 10" || return 1
  assert_contains "$out" "cannot reach zapbot token broker" "UX header" || return 1
  assert_contains "$out" "allow-pat-fallback" "hint mentions flag" || return 1
  # gh must not have been invoked (strict failure halts before gh).
  if [ -f "$MOCK_LOG" ] && grep -q "^gh " "$MOCK_LOG"; then
    echo "    FAIL: gh was invoked during strict failure"
    return 1
  fi
  return 0
}

# ── End-to-end: zapbot detected + broker 401 + --allow-pat-fallback ─

test_e2e_user_fallback_warns_and_proceeds() {
  _reset_sandbox
  mkdir -p "$HOME/.zapbot"
  touch "$HOME/.zapbot/.env"
  export ZAPBOT_API_KEY="wrong-key"
  _mock_curl 401 '{"error":{"type":"unauthorized","message":"x","status":401}}'
  _mock_gh "https://github.com/o/r/issues/9"
  local out rc
  out=$("$BIN" --allow-pat-fallback --kind comment --issue 9 --body "hi" 2>&1); rc=$?
  assert_equal "$rc" "0" "fallback proceeds" || return 1
  assert_contains "$out" "falling back to gh default auth" "warn printed" || return 1
  # gh was invoked.
  assert_contains "$(cat "$MOCK_LOG")" "gh " "gh invoked"
}

# ── End-to-end: --attribute-to-user skips broker + verify ───────────

test_e2e_attribute_to_user_skips_broker() {
  _reset_sandbox
  mkdir -p "$HOME/.zapbot"
  touch "$HOME/.zapbot/.env"
  export ZAPBOT_API_KEY="test-key"
  # Curl should NOT be called; if it is, stub fails noisily.
  cat > "$MOCK_BIN/curl" <<'EOF'
#!/usr/bin/env bash
echo "UNEXPECTED CURL CALL: $*" >> "$MOCK_LOG"
exit 99
EOF
  chmod +x "$MOCK_BIN/curl"
  _mock_gh "https://github.com/o/r/issues/11"
  local out rc
  out=$("$BIN" --attribute-to-user --kind comment --issue 11 --body "hi" 2>&1); rc=$?
  assert_equal "$rc" "0" "user attr success" || return 1
  if grep -q "UNEXPECTED CURL CALL" "$MOCK_LOG" 2>/dev/null; then
    echo "    FAIL: --attribute-to-user called the broker"
    return 1
  fi
  return 0
}

# ── End-to-end: conflicting flags → exit 22 before any gh/curl ──────

test_e2e_conflict_flags_exit_22() {
  _reset_sandbox
  local rc err
  err=$("$BIN" --allow-pat-fallback --attribute-to-user --kind comment --issue 5 --body x 2>&1); rc=$?
  assert_equal "$rc" "22" "conflict exit 22" || return 1
  assert_contains "$err" "mutually exclusive" "error message"
}

run_test "detect_zapbot finds ~/.zapbot/.env"         test_detect_zapbot_env
run_test "detect_zapbot finds ~/.zapbot/config.json"  test_detect_zapbot_config_json
run_test "detect_zapbot returns 0 when absent"        test_detect_zapbot_absent

run_test "resolve_bridge_url default"                  test_resolve_bridge_default
run_test "resolve_bridge_url env override"             test_resolve_bridge_env_override
run_test "resolve_bridge_url yaml beats env"           test_resolve_bridge_yaml_beats_env

run_test "fetch_broker_token happy path"               test_fetch_token_happy_path
run_test "fetch_broker_token TCP fail → 10"            test_fetch_token_tcp_fail_returns_10
run_test "fetch_broker_token 401 → 11"                 test_fetch_token_401_returns_11
run_test "fetch_broker_token 409 → 12"                 test_fetch_token_409_returns_12
run_test "fetch_broker_token 5xx → 13"                 test_fetch_token_500_returns_13
run_test "fetch_broker_token schema invalid → 14"      test_fetch_token_schema_invalid_returns_14

run_test "handle_fallback_flags default zero"          test_flags_default_both_zero
run_test "handle_fallback_flags consumes --pat"        test_flags_pat_consumed
run_test "handle_fallback_flags consumes --attribute"  test_flags_attribute_consumed
run_test "handle_fallback_flags rejects both → 22"     test_flags_both_together_returns_22

run_test "resolve_identity_mode D=0 → user"            test_mode_no_detection_user
run_test "resolve_identity_mode D=1 hit → bot"         test_mode_detected_bot_hit
run_test "resolve_identity_mode D=1 miss → strict"     test_mode_detected_miss_strict_fail
run_test "resolve_identity_mode D=1 miss F=1 → fbck"   test_mode_detected_miss_allow_pat
run_test "resolve_identity_mode U=1 → user"            test_mode_attribute_to_user_forces_user

run_test "verify_attribution Bot passes"               test_verify_attribution_bot_passes
run_test "verify_attribution non-Bot → 20"             test_verify_attribution_user_fails_20

run_test "e2e: no zapbot → user mode, no broker call"  test_e2e_no_zapbot_user_silent
run_test "e2e: bot success exports GH_TOKEN + verify"  test_e2e_bot_success_exports_gh_token
run_test "e2e: strict fail exits 10 with UX block"     test_e2e_strict_fail_exits_10_with_ux_block
run_test "e2e: --allow-pat-fallback warns + proceeds"  test_e2e_user_fallback_warns_and_proceeds
run_test "e2e: --attribute-to-user skips broker"       test_e2e_attribute_to_user_skips_broker
run_test "e2e: conflict flags → exit 22"               test_e2e_conflict_flags_exit_22

report
