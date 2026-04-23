#!/usr/bin/env bash
# Tests the grep-purity rule (SPEC r4.1 §5(d) bullet 1, architect §2.6):
# SKILL.md prompt files MUST NOT USE MoltZap transport SDKs or the zapbot
# bridge directly. They may NAME these tokens in prose warnings (the
# MoltZap peer-channel preamble explicitly tells the skill not to import
# them), but they must not invoke them.
#
# The test therefore flags IMPORT-LIKE syntax (require / import / from /
# bun-run invocation) rather than bare mentions.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

REPO_ROOT="$(cd "$HERE/../.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"

# Forbidden *usage* patterns. Assembled from an array for readability;
# each entry is one alternative in the final grep -E alternation. The
# quote class `['\"]` (escaped for the heredoc below) matches either
# single or double quotes.
FORBIDDEN_PATTERNS=(
  "^[[:space:]]*(import|const|let|var)[[:space:]].*['\"]@moltzap/"
  "^[[:space:]]*(import|const|let|var)[[:space:]].*['\"]@modelcontextprotocol/"
  "require\\(['\"]@moltzap/"
  "require\\(['\"]@modelcontextprotocol/"
  "bun[[:space:]]+run[[:space:]]+[^[:space:]]*src/bridge\\.ts"
  "bun[[:space:]]+run[[:space:]]+[^[:space:]]*src/moltzap/"
)
# Join with `|` into a single alternation.
FORBIDDEN_ALT="$(IFS='|'; echo "${FORBIDDEN_PATTERNS[*]}")"

_scan_for_forbidden() {
  # Run grep per-file in a loop. Returns offender-lines on stdout (empty
  # if none); returns exit 2 if grep itself errored on any file (bad
  # regex, IO). Kept explicit rather than piping through xargs so
  # "no matches" (grep exit 1) is distinguishable from regex failure
  # (grep exit >=2).
  local dir="$1"
  local any_error=0
  while IFS= read -r -d '' f; do
    local out
    out=$(grep -EHn -- "$FORBIDDEN_ALT" "$f" 2>/dev/null)
    local rc=$?
    if [ "$rc" -ge 2 ]; then
      any_error=1
    elif [ "$rc" -eq 0 ] && [ -n "$out" ]; then
      printf '%s\n' "$out"
    fi
  done < <(find "$dir" -type f -name "SKILL.md" -print0)
  if [ "$any_error" -ne 0 ]; then return 2; fi
  return 0
}

test_no_skill_md_invokes_forbidden_transport() {
  local offenders
  offenders=$(_scan_for_forbidden "$SKILLS_DIR")
  local scan_rc=$?
  if [ "$scan_rc" -ge 2 ]; then
    echo "    FAIL: grep regex error scanning $SKILLS_DIR"
    return 1
  fi
  if [ -z "$offenders" ]; then
    return 0
  fi
  echo "    FAIL: forbidden transport invocations found"
  echo "$offenders" | sed 's/^/      /'
  return 1
}

test_purity_regex_catches_planted_import() {
  # Plant a forbidden import in a tmp SKILL.md fixture, point the
  # SKILLS_DIR at it, and verify the test fails. This guards the regex
  # against future drift.
  local fixture
  fixture=$(mktemp -d)
  mkdir -p "$fixture/fake-skill"
  cat > "$fixture/fake-skill/SKILL.md" <<'FAKE'
---
name: fake-skill
---
# fake skill
import { connect } from "@moltzap/app-sdk";
FAKE
  local result
  result=$(_scan_for_forbidden "$fixture")
  rm -rf "$fixture"
  if [ -z "$result" ]; then
    echo "    FAIL: regex failed to catch planted \`import '@moltzap/app-sdk'\`"
    return 1
  fi
  return 0
}

echo "[test-safer-peer-message-skill-purity]"
run_test "no SKILL.md invokes a forbidden transport" test_no_skill_md_invokes_forbidden_transport
run_test "regex catches a planted forbidden import" test_purity_regex_catches_planted_import

report
