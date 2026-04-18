#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
BIN="$PLUGIN_DIR/bin/safer-diff-scope"

# Helper: run with a synthetic diff file
run_diff() {
  local diff_file="$1"
  "$BIN" --diff "$diff_file" 2>&1
}

test_junior_diff() {
  local tmp
  tmp=$(mktemp)
  cat > "$tmp" <<'EOF'
diff --git a/src/auth/token.ts b/src/auth/token.ts
index abc..def 100644
--- a/src/auth/token.ts
+++ b/src/auth/token.ts
@@ -10,6 +10,7 @@ export function verify(x) {
-  return decode(x);
+  if (!x) return null;
+  return decode(x);
 }
EOF
  local out
  out=$(run_diff "$tmp")
  rm -f "$tmp"
  assert_contains "$out" '"tier":"junior"' "single-file internal change is junior"
}

test_senior_multi_module() {
  local tmp
  tmp=$(mktemp)
  cat > "$tmp" <<'EOF'
diff --git a/src/auth/token.ts b/src/auth/token.ts
@@ -1,1 +1,2 @@
+  // edit
diff --git a/src/billing/charge.ts b/src/billing/charge.ts
@@ -1,1 +1,2 @@
+  // edit
EOF
  local out
  out=$(run_diff "$tmp")
  rm -f "$tmp"
  assert_contains "$out" '"tier":"senior"' "multi-module diff is senior"
}

test_senior_exported_signature() {
  local tmp
  tmp=$(mktemp)
  cat > "$tmp" <<'EOF'
diff --git a/src/auth/token.ts b/src/auth/token.ts
@@ -1,2 +1,3 @@
+export function newPublicApi(x: string): number { return x.length; }
 export const existing = 1;
EOF
  local out
  out=$(run_diff "$tmp")
  rm -f "$tmp"
  assert_contains "$out" '"tier":"senior"' "added export makes it senior"
  assert_contains "$out" '"exports":1' "one exported change counted"
}

test_staff_new_deps() {
  local tmp
  tmp=$(mktemp)
  # Diff adds a genuinely new dep ("bar") without reformatting "foo".
  cat > "$tmp" <<'EOF'
diff --git a/package.json b/package.json
@@ -10,4 +10,5 @@
   "dependencies": {
     "foo": "^1.0.0",
+    "bar": "^2.0.0",
     "baz": "^3.0.0"
   }
 }
EOF
  local out
  out=$(run_diff "$tmp")
  rm -f "$tmp"
  assert_contains "$out" '"tier":"staff"' "adding a dep is staff"
  assert_contains "$out" '"new_deps":1' "one new dep"
}

test_empty_diff() {
  local tmp
  tmp=$(mktemp)
  : > "$tmp"
  local out
  out=$(run_diff "$tmp")
  rm -f "$tmp"
  assert_contains "$out" '"tier":"junior"' "empty diff defaults to junior"
  assert_contains "$out" '"files":0' "empty diff has 0 files"
}

run_test "diff-scope classifies junior (internal change)" test_junior_diff
run_test "diff-scope classifies senior (multi-module)" test_senior_multi_module
run_test "diff-scope classifies senior (exported signature)" test_senior_exported_signature
run_test "diff-scope classifies staff (new dep)" test_staff_new_deps
run_test "diff-scope handles empty diff" test_empty_diff
report
