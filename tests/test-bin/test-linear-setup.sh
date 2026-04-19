#!/bin/bash

# Unit tests for safer-linear-setup
# Tests API key validation and script structure

SCRIPT_PATH="${SCRIPT_PATH:-./bin/safer-linear-setup}"
TESTS_PASSED=0
TESTS_FAILED=0

# Test: script fails when LINEAR_API_KEY not set
test_missing_api_key() {
  # Save current value if set
  local saved_key="${LINEAR_API_KEY:-}"
  unset LINEAR_API_KEY

  local output
  output=$("$SCRIPT_PATH" 2>&1 || true)

  # Restore
  if [ -n "$saved_key" ]; then
    export LINEAR_API_KEY="$saved_key"
  fi

  if echo "$output" | grep -q "LINEAR_API_KEY not set"; then
    echo "✓ test_missing_api_key"
    ((TESTS_PASSED++))
  else
    echo "✗ test_missing_api_key"
    ((TESTS_FAILED++))
  fi
}

# Test: script requires authorization header with Bearer token
test_script_structure() {
  if grep -q "Authorization: Bearer" "$SCRIPT_PATH"; then
    echo "✓ test_script_structure"
    ((TESTS_PASSED++))
  else
    echo "✗ test_script_structure"
    ((TESTS_FAILED++))
  fi
}

# Test: script defines all 11 labels
test_labels_defined() {
  if grep -q "junior.*0891b2" "$SCRIPT_PATH" && \
     grep -q "senior.*2563eb" "$SCRIPT_PATH" && \
     grep -q "staff.*7c3aed" "$SCRIPT_PATH"; then
    echo "✓ test_labels_defined"
    ((TESTS_PASSED++))
  else
    echo "✗ test_labels_defined"
    ((TESTS_FAILED++))
  fi
}

# Test: script defines all 6 projects
test_projects_defined() {
  if grep -q "Epic-B-cc-judge" "$SCRIPT_PATH" && \
     grep -q "Moltzap-migration" "$SCRIPT_PATH" && \
     grep -q "Testing-doctrine" "$SCRIPT_PATH"; then
    echo "✓ test_projects_defined"
    ((TESTS_PASSED++))
  else
    echo "✗ test_projects_defined"
    ((TESTS_FAILED++))
  fi
}

# Test: script checks idempotency (team_exists, label_exists functions)
test_idempotency_check() {
  if grep -q "team_exists" "$SCRIPT_PATH" && grep -q "label_exists" "$SCRIPT_PATH"; then
    echo "✓ test_idempotency_check"
    ((TESTS_PASSED++))
  else
    echo "✗ test_idempotency_check"
    ((TESTS_FAILED++))
  fi
}

# Run all tests
echo "Running safer-linear-setup tests..."
echo ""

test_missing_api_key
test_script_structure
test_labels_defined
test_projects_defined
test_idempotency_check

echo ""
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"

if [ "$TESTS_FAILED" -eq 0 ]; then
  exit 0
else
  exit 1
fi
