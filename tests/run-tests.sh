#!/usr/bin/env bash
# Master test runner. Executes every test under tests/test-bin/ and returns
# non-zero on any failure. Summary at the end.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091

total_passed=0
total_failed=0
failing_suites=()

shopt -s nullglob

# Collect suites to run. Unit tests under tests/test-bin/ always run.
# Integration tests under tests/test-integration/ hit real GitHub, so they
# are opt-in via SAFER_RUN_INTEGRATION=1 (or the --integration flag).
run_integration="${SAFER_RUN_INTEGRATION:-0}"
for arg in "$@"; do
  case "$arg" in
    --integration) run_integration=1 ;;
  esac
done

suites=("$HERE"/test-bin/test-*.sh "$HERE"/test-linear-v2/test-*.sh)
if [ "$run_integration" = "1" ]; then
  suites+=("$HERE"/test-integration/test-*.sh)
else
  echo "(integration tests skipped; set SAFER_RUN_INTEGRATION=1 or pass --integration to include them)"
  echo ""
fi

for t in "${suites[@]}"; do
  name=$(basename "$t" .sh)
  echo "── $name ──"
  chmod +x "$t" 2>/dev/null || true
  output=$(bash "$t" 2>&1); rc=$?
  echo "$output"
  # Parse "passed: N" and "failed: N" from the report section
  p=$(echo "$output" | awk '/passed:/ { gsub(/[^0-9]/,"",$2); print $2 }' | tail -1)
  f=$(echo "$output" | awk '/failed:/ { gsub(/[^0-9]/,"",$2); print $2 }' | tail -1)
  total_passed=$((total_passed + ${p:-0}))
  total_failed=$((total_failed + ${f:-0}))
  if [ "$rc" -ne 0 ] || [ "${f:-0}" -gt 0 ]; then
    failing_suites+=("$name")
  fi
  echo ""
done

echo "════════════════════════════════════════"
echo "  TOTAL passed: $total_passed"
echo "  TOTAL failed: $total_failed"
if [ "${#failing_suites[@]}" -gt 0 ]; then
  echo "  failing suites:"
  for s in "${failing_suites[@]}"; do echo "    - $s"; done
  exit 1
fi
exit 0
