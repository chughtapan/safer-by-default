#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
BIN="$PLUGIN_DIR/setup-codex"

make_fake_tools() {
  local dir
  local real_readlink
  dir=$(mktemp -d)
  real_readlink=$(command -v readlink)

  cat > "$dir/gh" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "auth" ] && [ "${2:-}" = "status" ]; then
  exit 0
fi
exit 0
EOF

  cat > "$dir/bun" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  cat > "$dir/readlink" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "-f" ]; then
  echo "readlink: illegal option -- f" >&2
  exit 1
fi
"$real_readlink" "\$@"
EOF

  chmod +x "$dir/gh" "$dir/bun" "$dir/readlink"
  echo "$dir"
}

assert_symlink() {
  local path="$1"
  local label="${2:-symlink exists}"
  if [ -L "$path" ]; then return 0; fi
  echo "    FAIL ($label): $path is not a symlink"
  return 1
}

assert_absent() {
  local path="$1"
  local label="${2:-path absent}"
  if [ ! -e "$path" ]; then return 0; fi
  echo "    FAIL ($label): $path still exists"
  return 1
}

run_setup() {
  local home_dir="$1"
  local bin_dir="$2"
  local fake_tools="$3"

  # SAFER_SOURCE_DIR pins the resolver to the test's checkout. Without it,
  # setup-codex would fall through to the CC plugin cache (host-state leak)
  # or attempt a real git clone of REPO_URL (network dependency).
  HOME="$home_dir" \
  CODEX_HOME="$home_dir/.codex" \
  SAFER_CODEX_BIN_DIR="$bin_dir" \
  SAFER_STATE_DIR="$home_dir/.safer" \
  SAFER_SOURCE_DIR="$PLUGIN_DIR" \
  SAFER_XDG_SOURCE_DIR="$home_dir/.local/share/safer-by-default" \
  PATH="$fake_tools:$PATH" \
  "$BIN"
}

test_install_and_idempotent_with_bsd_readlink() {
  local tmp
  local fake_tools
  local bin_dir
  local out
  local out2

  tmp=$(mktemp -d)
  fake_tools=$(make_fake_tools)
  bin_dir="$tmp/local-bin"

  out=$(run_setup "$tmp" "$bin_dir" "$fake_tools" 2>&1)
  out2=$(run_setup "$tmp" "$bin_dir" "$fake_tools" 2>&1)

  assert_contains "$out" "Codex setup complete." "first install completes" || { rm -rf "$tmp" "$fake_tools"; return 1; }
  assert_contains "$out2" "Codex setup complete." "second install completes" || { rm -rf "$tmp" "$fake_tools"; return 1; }
  assert_file_exists "$tmp/.codex/skills/safer-spec/SKILL.md" "safer:spec wrapper exists" || { rm -rf "$tmp" "$fake_tools"; return 1; }
  assert_file_exists "$tmp/.codex/skills/safer-spec-init/SKILL.md" "safer:spec-init wrapper exists" || { rm -rf "$tmp" "$fake_tools"; return 1; }
  assert_file_exists "$tmp/.codex/skills/safer-spec-migrate/SKILL.md" "safer:spec-migrate wrapper exists" || { rm -rf "$tmp" "$fake_tools"; return 1; }
  assert_contains "$(cat "$tmp/.codex/skills/safer-spec/SKILL.md")" "safer-by-default codex wrapper" "wrapper marker present" || { rm -rf "$tmp" "$fake_tools"; return 1; }
  assert_symlink "$tmp/.codex/skills/safer-by-default" "plugin root link exists" || { rm -rf "$tmp" "$fake_tools"; return 1; }
  assert_symlink "$bin_dir/safer-update-check" "binary link exists" || { rm -rf "$tmp" "$fake_tools"; return 1; }

  rm -rf "$tmp" "$fake_tools"
}

test_refuses_to_overwrite_non_generated_wrapper() {
  local tmp
  local fake_tools
  local bin_dir
  local wrapper_dir
  local out
  local rc

  tmp=$(mktemp -d)
  fake_tools=$(make_fake_tools)
  bin_dir="$tmp/local-bin"
  wrapper_dir="$tmp/.codex/skills/safer-spec"
  mkdir -p "$wrapper_dir"
  cat > "$wrapper_dir/SKILL.md" <<'EOF'
---
name: custom
---

custom wrapper
EOF

  out=$(run_setup "$tmp" "$bin_dir" "$fake_tools" 2>&1); rc=$?

  assert_nonzero "$rc" "custom wrapper blocks install" || { rm -rf "$tmp" "$fake_tools"; return 1; }
  assert_contains "$out" "refusing to overwrite non-generated wrapper" "conflict error surfaced" || { rm -rf "$tmp" "$fake_tools"; return 1; }
  assert_contains "$(cat "$wrapper_dir/SKILL.md")" "custom wrapper" "existing wrapper preserved" || { rm -rf "$tmp" "$fake_tools"; return 1; }

  rm -rf "$tmp" "$fake_tools"
}

test_narrow_scope_cleanup_preserves_unrelated_wrappers() {
  local tmp
  local fake_tools
  local bin_dir
  local foreign_dir
  local out

  tmp=$(mktemp -d)
  fake_tools=$(make_fake_tools)
  bin_dir="$tmp/local-bin"

  # Seed an UNRELATED wrapper not in the retired list. The narrow-scope
  # cleanup must NOT touch it, even though it carries the safer-by-default
  # generated marker (the user may have hand-installed it from a fork).
  foreign_dir="$tmp/.codex/skills/safer-experimental"
  mkdir -p "$foreign_dir"
  cat > "$foreign_dir/SKILL.md" <<'EOF'
---
name: "safer:experimental"
description: "user-installed wrapper not shipped by this plugin"
---

<!-- safer-by-default codex wrapper -->

# safer:experimental

custom body
EOF

  out=$(run_setup "$tmp" "$bin_dir" "$fake_tools" 2>&1)

  assert_contains "$out" "Codex setup complete." "install completes" || { rm -rf "$tmp" "$fake_tools"; return 1; }
  assert_file_exists "$foreign_dir/SKILL.md" "unrelated wrapper preserved" || { rm -rf "$tmp" "$fake_tools"; return 1; }
  assert_contains "$(cat "$foreign_dir/SKILL.md")" "custom body" "unrelated wrapper body unchanged" || { rm -rf "$tmp" "$fake_tools"; return 1; }

  rm -rf "$tmp" "$fake_tools"
}

run_test "setup-codex installs cleanly and is idempotent with BSD-style readlink" test_install_and_idempotent_with_bsd_readlink
run_test "setup-codex refuses to overwrite a non-generated wrapper" test_refuses_to_overwrite_non_generated_wrapper
run_test "setup-codex preserves unrelated safer-* wrappers (narrow-scope cleanup)" test_narrow_scope_cleanup_preserves_unrelated_wrappers
report
