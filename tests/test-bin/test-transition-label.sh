#!/usr/bin/env bash
# Validates argument handling and gh interaction branches with a mock gh.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
BIN="$PLUGIN_DIR/bin/safer-transition-label"

# mock_gh_dir_sequence <rc1> <rc2> — first gh call returns rc1, second returns rc2.
mock_gh_dir_sequence() {
  local rc1="$1"
  local rc2="$2"
  local dir
  dir=$(mktemp -d)
  local counter_file="$dir/.call_count"
  echo "0" > "$counter_file"
  cat > "$dir/gh" <<GHEOF
#!/usr/bin/env bash
count=\$(cat "$counter_file")
count=\$((count + 1))
echo "\$count" > "$counter_file"
if [ "\$count" -le 1 ]; then
  exit $rc1
else
  exit $rc2
fi
GHEOF
  chmod +x "$dir/gh"
  echo "$dir"
}

test_requires_args() {
  local rc
  "$BIN" >/dev/null 2>&1; rc=$?
  assert_nonzero "$rc" "no args should fail"
  "$BIN" --issue 1 >/dev/null 2>&1; rc=$?
  assert_nonzero "$rc" "missing --from/--to should fail"
  "$BIN" --issue 1 --from planning >/dev/null 2>&1; rc=$?
  assert_nonzero "$rc" "missing --to should fail"
}

test_gh_not_installed() {
  local fake_path out rc
  fake_path=$(mktemp -d)
  ln -s "$(command -v bash)" "$fake_path/bash"
  out=$(PATH="$fake_path" "$BIN" --issue 1 --from planning --to implementing 2>&1); rc=$?
  rm -rf "$fake_path"
  assert_nonzero "$rc" "no gh → nonzero exit"
  assert_contains "$out" "gh not installed" "error message"
}

test_happy_path_success() {
  local fake out rc
  fake=$(mock_gh_dir_sequence 0 0)
  out=$(PATH="$fake:$PATH" "$BIN" --issue 42 --from planning --to implementing 2>&1); rc=$?
  rm -rf "$fake"
  assert_zero "$rc" "first gh succeeds → exit 0"
  assert_contains "$out" "TRANSITIONED" "transition message"
  assert_contains "$out" "#42" "issue number"
  assert_contains "$out" "planning" "from label"
  assert_contains "$out" "implementing" "to label"
}

test_retry_path_success() {
  local fake out rc
  # First gh call fails (FROM label not present), second succeeds (add-only)
  fake=$(mock_gh_dir_sequence 1 0)
  out=$(PATH="$fake:$PATH" "$BIN" --issue 7 --from planning --to implementing 2>&1); rc=$?
  rm -rf "$fake"
  assert_zero "$rc" "retry path → exit 0"
  assert_contains "$out" "TRANSITIONED" "transition message present"
  assert_contains "$out" "no planning" "indicates from-label absent"
}

test_total_failure() {
  local fake out rc
  fake=$(mock_gh_dir_sequence 1 1)
  out=$(PATH="$fake:$PATH" "$BIN" --issue 3 --from planning --to implementing 2>&1); rc=$?
  rm -rf "$fake"
  assert_nonzero "$rc" "both gh calls fail → nonzero exit"
  assert_contains "$out" "ERROR" "error message present"
}

test_repo_flag_forwarded() {
  local fake out rc
  fake=$(mock_gh_dir_sequence 0 0)
  out=$(PATH="$fake:$PATH" "$BIN" --issue 1 --from a --to b --repo org/repo 2>&1); rc=$?
  rm -rf "$fake"
  assert_zero "$rc" "--repo forwarded, exit 0"
}

run_test "safer-transition-label requires --issue/--from/--to" test_requires_args
run_test "safer-transition-label: gh not installed → error" test_gh_not_installed
run_test "safer-transition-label: first gh succeeds → TRANSITIONED" test_happy_path_success
run_test "safer-transition-label: retry path (no FROM) → TRANSITIONED" test_retry_path_success
run_test "safer-transition-label: both gh calls fail → ERROR" test_total_failure
run_test "safer-transition-label: --repo flag accepted" test_repo_flag_forwarded
report
