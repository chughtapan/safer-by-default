#!/usr/bin/env bash
# test-safer-gen-skills.sh — renderer tests for bin/safer-gen-skills.
#
# The renderer knows one directive, {{> principles-core}}, which inlines
# PRINCIPLES.core.md. {{> principles}} (the full doctrine) is a hard error;
# every other unknown directive passes through verbatim.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
BIN="$PLUGIN_DIR/bin/safer-gen-skills"

# Build a self-contained fixture tree at $tmp that mirrors the real layout:
#   $tmp/PRINCIPLES.md         (full doctrine; referenced by path, never inlined)
#   $tmp/PRINCIPLES.core.md    (compressed floor; inlined by the renderer)
#   $tmp/bin/safer-gen-skills  (copy of the real binary)
#   $tmp/skills/<name>/SKILL.tmpl
build_fixture() {
  local tmp="$1"
  mkdir -p "$tmp/bin" "$tmp/skills"
  cat > "$tmp/PRINCIPLES.md" <<'EOF'
# PRINCIPLES — fixture

Body of the fixture's PRINCIPLES.md goes here.
EOF
  cat > "$tmp/PRINCIPLES.core.md" <<'EOF'
Body of the fixture's PRINCIPLES.core.md goes here.
EOF
  cp "$BIN" "$tmp/bin/safer-gen-skills"
  chmod +x "$tmp/bin/safer-gen-skills"
}

write_skill() {
  local tmp="$1" name="$2" body="$3"
  mkdir -p "$tmp/skills/$name"
  cat > "$tmp/skills/$name/SKILL.tmpl" <<EOF
---
name: $name
description: fixture
---

# /safer:$name

$body
EOF
}

# ---------------------------------------------------------------------------

# Doctrine reaches a skill in two layers: the core is inlined, the full
# PRINCIPLES.md is referenced by path. A renderer that inlined the full file
# would silently restore the ~8.4k lines of duplication this split removed.
test_principles_core_directive_inlines_core_only() {
  local tmp; tmp=$(mktemp -d)
  build_fixture "$tmp"
  write_skill "$tmp" example '{{> principles-core}}'

  (cd "$tmp" && ./bin/safer-gen-skills >/dev/null 2>&1) || {
    rm -rf "$tmp"; echo "    FAIL: generator exited non-zero"; return 1
  }
  local out="$tmp/skills/example/SKILL.md"
  assert_file_exists "$out" "generated SKILL.md exists" || { rm -rf "$tmp"; return 1; }
  local body; body=$(cat "$out")
  rm -rf "$tmp"
  assert_contains "$body" "Body of the fixture's PRINCIPLES.core.md goes here." "core body inlined" || return 1
  assert_contains "$body" "AUTO-GENERATED" "generated marker stamped" || return 1
  case "$body" in
    *"Body of the fixture's PRINCIPLES.md goes here."*)
      echo "    FAIL: full PRINCIPLES.md was inlined"; return 1 ;;
    *'{{> principles-core}}'*)
      echo "    FAIL: directive survived into output"; return 1 ;;
  esac
}

test_legacy_principles_directive_refused() {
  local tmp; tmp=$(mktemp -d)
  build_fixture "$tmp"
  write_skill "$tmp" example '{{> principles}}'

  local rc out
  out=$(cd "$tmp" && ./bin/safer-gen-skills 2>&1); rc=$?
  rm -rf "$tmp"
  assert_nonzero "$rc" "renderer refuses the retired {{> principles}} directive" || return 1
  assert_contains "$out" "principles-core" "stderr names the successor directive" || return 1
}

# The renderer knows exactly one directive. Anything else must survive into the
# output verbatim rather than resolving to empty, so a typo or a directive from a
# retired feature is visible in review instead of silently deleting a section.
test_unknown_directive_passes_through_visibly() {
  local tmp; tmp=$(mktemp -d)
  build_fixture "$tmp"
  write_skill "$tmp" example '{{> not-a-real-directive}}'

  (cd "$tmp" && ./bin/safer-gen-skills >/dev/null 2>&1) || {
    rm -rf "$tmp"; echo "    FAIL: generator exited non-zero"; return 1
  }
  local body; body=$(cat "$tmp/skills/example/SKILL.md")
  rm -rf "$tmp"
  assert_contains "$body" '{{> not-a-real-directive}}' "unknown directive emitted verbatim" || return 1
}

test_check_detects_stale_skill_md() {
  local tmp; tmp=$(mktemp -d)
  build_fixture "$tmp"
  write_skill "$tmp" example '{{> principles-core}}'
  (cd "$tmp" && ./bin/safer-gen-skills >/dev/null 2>&1)

  local rc out
  (cd "$tmp" && ./bin/safer-gen-skills --check >/dev/null 2>&1); rc=$?
  assert_zero "$rc" "--check is clean right after a render" || { rm -rf "$tmp"; return 1; }

  echo "hand-edited line" >> "$tmp/skills/example/SKILL.md"
  out=$(cd "$tmp" && ./bin/safer-gen-skills --check 2>&1); rc=$?
  rm -rf "$tmp"
  assert_nonzero "$rc" "--check fails when SKILL.md drifts from its template" || return 1
  assert_contains "$out" "STALE" "stderr names the stale file" || return 1
}

test_render_is_idempotent() {
  local tmp; tmp=$(mktemp -d)
  build_fixture "$tmp"
  write_skill "$tmp" example '{{> principles-core}}'
  (cd "$tmp" && ./bin/safer-gen-skills >/dev/null 2>&1) || {
    rm -rf "$tmp"; echo "    FAIL: first render exited non-zero"; return 1
  }
  local first; first=$(cat "$tmp/skills/example/SKILL.md" 2>/dev/null)
  # Without this, two failed renders both yield "" and the test passes green.
  [ -n "$first" ] || { rm -rf "$tmp"; echo "    FAIL: first render produced no output"; return 1; }
  (cd "$tmp" && ./bin/safer-gen-skills >/dev/null 2>&1) || {
    rm -rf "$tmp"; echo "    FAIL: second render exited non-zero"; return 1
  }
  local second; second=$(cat "$tmp/skills/example/SKILL.md" 2>/dev/null)
  rm -rf "$tmp"
  assert_equal "$second" "$first" "second render matches the first byte-for-byte" || return 1
}

test_missing_core_file_fails_loud() {
  local tmp; tmp=$(mktemp -d)
  build_fixture "$tmp"
  write_skill "$tmp" example '{{> principles-core}}'
  rm "$tmp/PRINCIPLES.core.md"

  local rc out
  out=$(cd "$tmp" && ./bin/safer-gen-skills 2>&1); rc=$?
  rm -rf "$tmp"
  assert_nonzero "$rc" "renderer fails when PRINCIPLES.core.md is absent" || return 1
  assert_contains "$out" "PRINCIPLES.core.md" "stderr names the missing file" || return 1
}

run_test "principles-core directive inlines PRINCIPLES.core.md, not PRINCIPLES.md" test_principles_core_directive_inlines_core_only
run_test "retired {{> principles}} directive fails loud and names the successor" test_legacy_principles_directive_refused
run_test "unknown directive passes through visibly" test_unknown_directive_passes_through_visibly
run_test "--check detects a hand-edited SKILL.md" test_check_detects_stale_skill_md
run_test "render is idempotent" test_render_is_idempotent
run_test "missing PRINCIPLES.core.md fails loud" test_missing_core_file_fails_loud
report
