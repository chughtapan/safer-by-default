#!/usr/bin/env bash
# Minimal bash test harness for safer-by-default binaries.
# Source this in per-binary test files.
set -uo pipefail

TESTS_PASSED=0
TESTS_FAILED=0
FAILED_NAMES=()

__red()   { printf '\033[0;31m%s\033[0m' "$*"; }
__green() { printf '\033[0;32m%s\033[0m' "$*"; }
__grey()  { printf '\033[0;90m%s\033[0m' "$*"; }

assert_equal() {
  local actual="$1"
  local expected="$2"
  local label="${3:-equal}"
  if [ "$actual" = "$expected" ]; then return 0; fi
  echo "    FAIL ($label)"
  echo "      expected: $expected"
  echo "      actual:   $actual"
  return 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="${3:-contains}"
  if printf '%s' "$haystack" | grep -qF "$needle"; then return 0; fi
  echo "    FAIL ($label)"
  echo "      expected contains: $needle"
  echo "      actual: $haystack"
  return 1
}

assert_matches() {
  local haystack="$1"
  local regex="$2"
  local label="${3:-matches}"
  if printf '%s' "$haystack" | grep -qE "$regex"; then return 0; fi
  echo "    FAIL ($label)"
  echo "      expected regex: $regex"
  echo "      actual: $haystack"
  return 1
}

assert_file_exists() {
  local f="$1"
  local label="${2:-file exists}"
  if [ -f "$f" ]; then return 0; fi
  echo "    FAIL ($label): $f not found"
  return 1
}

assert_zero() {
  local rc="$1"
  local label="${2:-zero exit}"
  if [ "$rc" = "0" ]; then return 0; fi
  echo "    FAIL ($label): exit $rc"
  return 1
}

assert_nonzero() {
  local rc="$1"
  local label="${2:-nonzero exit}"
  if [ "$rc" != "0" ]; then return 0; fi
  echo "    FAIL ($label): expected nonzero, got $rc"
  return 1
}

# A skill's full context surface: the generated SKILL.md plus every file the
# skill reads on demand (references/, prompts/, and the shared _shared/ pool).
# Rare-branch material moves between these, so any test that pins a rule must
# look at all of them or it silently stops enforcing when the rule relocates.
# Stated once here rather than re-derived per test.
skill_surface() {
  local name="$1"
  local root="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/skills}"
  local skill_md="$root/$name/SKILL.md"
  [ -f "$skill_md" ] || return 0
  printf '%s\n' "$skill_md"
  # An on-demand file is part of the surface only when SKILL.md actually points
  # at it. Globbing the directories instead would let a rule living in an
  # orphaned file satisfy a test even though the running skill never reads it —
  # the exact gap these tests exist to close.
  local f
  for f in "$root/$name"/references/*.md "$root/$name"/prompts/*.md "$root"/_shared/*.md; do
    [ -f "$f" ] || continue
    grep -qF "$(basename "$f")" "$skill_md" 2>/dev/null && printf '%s\n' "$f"
  done
}

# grep across a skill's whole surface. Same argument shape as grep, minus files.
skill_grep() {
  local name="$1"; shift
  local files=()
  while IFS= read -r f; do files+=("$f"); done < <(skill_surface "$name")
  [ ${#files[@]} -eq 0 ] && return 2
  grep "$@" "${files[@]}"
}

run_test() {
  local name="$1"
  local fn="$2"
  local out
  out=$($fn 2>&1); local rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "    $(__green ok) $name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo "    $(__red fail) $name"
    echo "$out" | sed 's/^/      /'
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_NAMES+=("$name")
  fi
}

# mock_gh_dir <exit-code> <stdout-payload>
# Writes a fake gh binary to a temp dir and prints the dir path.
# Caller: prepend the dir to PATH, then rm -rf after use.
mock_gh_dir() {
  local rc="$1"
  local out="$2"
  local dir
  dir=$(mktemp -d)
  cat > "$dir/gh" <<GHEOF
#!/usr/bin/env bash
echo '$out'
exit $rc
GHEOF
  chmod +x "$dir/gh"
  echo "$dir"
}

report() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  printf '  passed: %d\n' "$TESTS_PASSED"
  printf '  failed: %d\n' "$TESTS_FAILED"
  if [ "$TESTS_FAILED" -gt 0 ]; then
    echo "  failing:"
    for n in "${FAILED_NAMES[@]}"; do echo "    - $n"; done
    return 1
  fi
  return 0
}
