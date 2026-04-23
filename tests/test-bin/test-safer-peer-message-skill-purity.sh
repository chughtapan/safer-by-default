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

# Forbidden *usage* patterns. Combined into one alternation so each
# SKILL.md is scanned once rather than once per pattern.
FORBIDDEN_ALT='(^[[:space:]]*(import|const|let|var)[[:space:]].*[[:quote:]]@moltzap/)|(^[[:space:]]*(import|const|let|var)[[:space:]].*[[:quote:]]@modelcontextprotocol/)|(require\(['"'"'"]@moltzap/)|(require\(['"'"'"]@modelcontextprotocol/)|(bun[[:space:]]+run[[:space:]]+.*src/bridge\.ts)|(bun[[:space:]]+run[[:space:]]+.*src/moltzap/)'

test_no_skill_md_invokes_forbidden_transport() {
  local offenders
  offenders=$(find "$SKILLS_DIR" -type f -name "SKILL.md" -print0 \
               | xargs -0 grep -EHn -- "$FORBIDDEN_ALT" 2>/dev/null || true)
  if [ -z "$offenders" ]; then
    return 0
  fi
  echo "    FAIL: forbidden transport invocations found"
  echo "$offenders" | sed 's/^/      /'
  return 1
}

echo "[test-safer-peer-message-skill-purity]"
run_test "no SKILL.md invokes a forbidden transport" test_no_skill_md_invokes_forbidden_transport

report
