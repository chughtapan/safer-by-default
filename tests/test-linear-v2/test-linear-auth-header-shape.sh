#!/usr/bin/env bash
# Iron rule (invariant 5, #112): the Authorization header must NOT contain
# a "Bearer " prefix. The value must be the raw API key only.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"
PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
# shellcheck disable=SC1091
source "$PLUGIN_DIR/lib/safer-linear/linear-api.sh"

test_no_bearer_prefix_in_auth_header() {
  export LINEAR_API_KEY="lin_api_test123"
  local header_file
  header_file=$(mktemp)
  # shellcheck disable=SC2317
  curl() {
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == -H && "${2:-}" == Authorization:* ]]; then
        printf '%s\n' "${2#Authorization: }" > "$header_file"
        shift 2; continue
      fi
      if [[ "$1" == -o && -n "${2:-}" ]]; then
        printf '{"data":{"ok":true}}\n' > "$2"
        shift 2; continue
      fi
      shift
    done
    printf '200'
  }
  export -f curl

  linear_graphql 'query { test }' >/dev/null 2>/dev/null

  if [[ ! -s "$header_file" ]]; then
    rm -f "$header_file"
    printf '    Authorization header not captured\n'
    return 1
  fi

  local auth_value
  auth_value=$(cat "$header_file")
  rm -f "$header_file"

  if printf '%s' "$auth_value" | grep -q "Bearer "; then
    printf '    FAIL: header contains "Bearer " prefix: %s\n' "$auth_value"
    return 1
  fi
  assert_equal "$auth_value" "lin_api_test123" "auth header is raw API key, no Bearer prefix"
}

test_auth_missing_returns_exit_20() {
  unset LINEAR_API_KEY || true
  local rc
  linear_graphql 'query { test }' 2>/dev/null; rc=$?
  assert_equal "$rc" "20" "missing LINEAR_API_KEY → exit 20"
}

test_bearer_not_in_any_lib_source() {
  # Belt-and-suspenders static check: the actual curl -H Authorization flag
  # in linear-api.sh must NOT contain "Bearer".
  local src
  src=$(grep -n 'Authorization: \$LINEAR_API_KEY' \
    "$PLUGIN_DIR/lib/safer-linear/linear-api.sh" || true)
  if [[ -z "$src" ]]; then
    printf '    FAIL: Authorization header line not found in linear-api.sh\n'
    return 1
  fi
  if printf '%s\n' "$src" | grep -q "Bearer"; then
    printf '    FAIL: "Bearer" found in Authorization header line: %s\n' "$src"
    return 1
  fi
  return 0
}

run_test "Authorization header has no Bearer prefix"    test_no_bearer_prefix_in_auth_header
run_test "missing LINEAR_API_KEY → exit 20"             test_auth_missing_returns_exit_20
run_test "source: no Bearer in Authorization line"      test_bearer_not_in_any_lib_source

report
