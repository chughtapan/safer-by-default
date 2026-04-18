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
for t in "$HERE"/test-bin/test-*.sh; do
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
