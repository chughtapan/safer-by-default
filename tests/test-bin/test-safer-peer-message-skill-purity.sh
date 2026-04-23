#!/usr/bin/env bash
# Tests the grep-purity rule (SPEC r4.1 §5(d) bullet 1, architect §2.6):
# SKILL.md prompt files MUST NOT USE MoltZap transport SDKs or the zapbot
# bridge directly. They may NAME these tokens in prose warnings (the
# MoltZap peer-channel preamble explicitly tells the skill not to import
# them), but they must not invoke them.
#
# The test therefore flags IMPORT-LIKE syntax (require / import / from /
# $(invocation)) rather than bare mentions. Bare prose mentions inside a
# "do not import" warning are expected.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"

_fail=0
_pass=0
_total=0

_log() { printf '%s\n' "$*" >&2; }

# Forbidden *usage* patterns. Each entry is a regex. We use `grep -E` so
# the patterns are extended-regex.
FORBIDDEN_PATTERNS=(
  # JS/TS import/require of transport SDKs.
  "^[[:space:]]*(import|const|let|var)[[:space:]].*['\"]@moltzap/"
  "^[[:space:]]*(import|const|let|var)[[:space:]].*['\"]@modelcontextprotocol/"
  "require\\(['\"]@moltzap/"
  "require\\(['\"]@modelcontextprotocol/"
  # Shell invocation of the zapbot bridge binaries.
  "bun[[:space:]]+run[[:space:]]+.*src/bridge\\.ts"
  "bun[[:space:]]+run[[:space:]]+.*src/moltzap/"
)

# Also flag any line that ends with `… @moltzap/…` etc. as an executable
# statement — conservative belt-and-suspenders. These do not match the
# prose warnings in the peer-channel preamble because the preamble uses
# backtick-escaped inline code, not bare unquoted tokens.

declare -a offenders=()
while IFS= read -r -d '' skill_md; do
  for pat in "${FORBIDDEN_PATTERNS[@]}"; do
    if grep -En -- "$pat" "$skill_md" >/dev/null 2>&1; then
      offenders+=("$skill_md: pattern=$pat")
    fi
  done
done < <(find "$SKILLS_DIR" -type f -name "SKILL.md" -print0)

_total=$(( _total + 1 ))
if [ ${#offenders[@]} -eq 0 ]; then
  _pass=$(( _pass + 1 ))
  _log "  ✓ no SKILL.md invokes a forbidden transport directly"
else
  _fail=$(( _fail + 1 ))
  _log "  ✗ forbidden transport invocations found in SKILL.md files:"
  for o in "${offenders[@]}"; do
    _log "      $o"
  done
fi

echo ""
echo "[test-safer-peer-message-skill-purity] $_pass/$_total passed"
if [ "$_fail" -gt 0 ]; then
  exit 1
fi
exit 0
