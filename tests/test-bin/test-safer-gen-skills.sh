#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

PLUGIN_DIR="$(cd "$HERE/../.." && pwd)"
BIN="$PLUGIN_DIR/bin/safer-gen-skills"

# Local helpers (the shared test-helpers.sh has assert_equal but not assert_ne).
assert_eq() {
  local actual="$1" expected="$2" label="${3:-equal}"
  if [ "$actual" = "$expected" ]; then return 0; fi
  echo "    FAIL ($label): expected '$expected', got '$actual'"; return 1
}
assert_ne() {
  local actual="$1" not_expected="$2" label="${3:-not-equal}"
  if [ "$actual" != "$not_expected" ]; then return 0; fi
  echo "    FAIL ($label): both values are '$actual'"; return 1
}

# Build a self-contained fixture tree at $tmp that mirrors the real layout:
#   $tmp/PRINCIPLES.md
#   $tmp/bin/safer-gen-skills           (copy of the real binary)
#   $tmp/skills/<name>/SKILL.tmpl
#   $tmp/vendor/safer-spec-development/skills/<slug>/SKILL.md
build_fixture() {
  local tmp="$1"
  mkdir -p "$tmp/bin" "$tmp/skills" "$tmp/vendor/safer-spec-development/skills"
  cat > "$tmp/PRINCIPLES.md" <<'EOF'
# PRINCIPLES — fixture

Body of the fixture's PRINCIPLES.md goes here.
EOF
  cp "$BIN" "$tmp/bin/safer-gen-skills"
  chmod +x "$tmp/bin/safer-gen-skills"
}

write_vendor_skill() {
  local tmp="$1"
  local slug="$2"
  mkdir -p "$tmp/vendor/safer-spec-development/skills/$slug"
  cat > "$tmp/vendor/safer-spec-development/skills/$slug/SKILL.md" <<EOF
---
name: $slug
description: vendor skill fixture
---

# $slug

Vendor body line one.

## Subsection

Vendor body line two.
EOF
}

write_wrapper_skill() {
  local tmp="$1"
  local name="$2"
  local vendor_slug="$3"
  mkdir -p "$tmp/skills/$name"
  cat > "$tmp/skills/$name/SKILL.tmpl" <<EOF
---
name: $name
description: wrapper around vendor $vendor_slug
---

# /safer:$name

{{> vendor-skill:$vendor_slug}}
EOF
}

test_vendor_directive_inlines_body_and_demotes_h1() {
  local tmp; tmp=$(mktemp -d)
  build_fixture "$tmp"
  write_vendor_skill "$tmp" "example-vendor"
  write_wrapper_skill "$tmp" "example" "example-vendor"

  (cd "$tmp" && ./bin/safer-gen-skills >/dev/null 2>&1) || { rm -rf "$tmp"; echo "    FAIL: generator exited non-zero"; return 1; }

  local out="$tmp/skills/example/SKILL.md"
  assert_file_exists "$out" "generated SKILL.md exists" || { rm -rf "$tmp"; return 1; }
  # Wrapper's H1 is preserved.
  grep -qF "# /safer:example" "$out" || { rm -rf "$tmp"; echo "    FAIL: wrapper H1 missing"; return 1; }
  # Vendor body inlined.
  grep -qF "Vendor body line one." "$out" || { rm -rf "$tmp"; echo "    FAIL: vendor body not inlined"; return 1; }
  # Vendor's frontmatter stripped (no `name: example-vendor` line in body).
  ! grep -qF "name: example-vendor" "$out" || { rm -rf "$tmp"; echo "    FAIL: vendor frontmatter survived"; return 1; }
  # Vendor's first H1 (`# example-vendor`) demoted to H2.
  grep -qF "## example-vendor" "$out" || { rm -rf "$tmp"; echo "    FAIL: vendor H1 not demoted to H2"; return 1; }
  ! grep -qE "^# example-vendor$" "$out" || { rm -rf "$tmp"; echo "    FAIL: vendor H1 survived"; return 1; }

  rm -rf "$tmp"
}

test_check_release_passes_on_clean_tree() {
  local tmp; tmp=$(mktemp -d)
  build_fixture "$tmp"
  write_vendor_skill "$tmp" "example-vendor"
  write_wrapper_skill "$tmp" "example" "example-vendor"

  (cd "$tmp" && ./bin/safer-gen-skills >/dev/null 2>&1)
  local rc
  (cd "$tmp" && ./bin/safer-gen-skills --check --release >/dev/null 2>&1); rc=$?
  rm -rf "$tmp"
  assert_eq "$rc" "0" "release-mode check exits 0 on clean tree" || return 1
}

test_check_release_fails_on_sentinel_in_tmpl() {
  local tmp; tmp=$(mktemp -d)
  build_fixture "$tmp"
  write_vendor_skill "$tmp" "example-vendor"
  write_wrapper_skill "$tmp" "example" "example-vendor"
  # Inject the sentinel directly into a committed SKILL.tmpl.
  cat >> "$tmp/skills/example/SKILL.tmpl" <<'EOF'

# install line (sentinel-bearing dev form)
pnpm add -D @chughtapan/safer-spec-development@__SAFER_SPEC_VERSION__
EOF
  (cd "$tmp" && ./bin/safer-gen-skills >/dev/null 2>&1)
  local rc
  local out
  out=$(cd "$tmp" && ./bin/safer-gen-skills --check --release 2>&1); rc=$?
  rm -rf "$tmp"
  assert_ne "$rc" "0" "release-mode check exits non-zero when sentinel is in tmpl" || return 1
  assert_contains "$out" "__SAFER_SPEC_VERSION__" "stderr names the sentinel" || return 1
}

test_check_release_fails_on_sentinel_via_vendor_indirection() {
  local tmp; tmp=$(mktemp -d)
  build_fixture "$tmp"
  # Vendor body carries the sentinel; renderer inlines it; --check --release
  # greps the generated SKILL.md and trips. This is the "via vendor" case the
  # security reviewer asked be covered: a compromised sister-repo cannot smuggle
  # the sentinel past the release gate by hiding it in a vendor body.
  mkdir -p "$tmp/vendor/safer-spec-development/skills/example-vendor"
  cat > "$tmp/vendor/safer-spec-development/skills/example-vendor/SKILL.md" <<'EOF'
---
name: example-vendor
---

# example-vendor

Body has __SAFER_SPEC_VERSION__ baked in.
EOF
  write_wrapper_skill "$tmp" "example" "example-vendor"

  (cd "$tmp" && ./bin/safer-gen-skills >/dev/null 2>&1)
  local rc
  local out
  out=$(cd "$tmp" && ./bin/safer-gen-skills --check --release 2>&1); rc=$?
  rm -rf "$tmp"
  assert_ne "$rc" "0" "release-mode check exits non-zero when sentinel inlines via vendor" || return 1
  assert_contains "$out" "__SAFER_SPEC_VERSION__" "stderr names the vendor-sourced sentinel" || return 1
}

test_vendor_skill_symlink_refused() {
  local tmp; tmp=$(mktemp -d)
  build_fixture "$tmp"
  write_vendor_skill "$tmp" "real-target"
  # Plant the leaf SKILL.md as a symlink to a host-private file (the
  # threat model: a compromised sister-repo merge plants a leaf symlink).
  mkdir -p "$tmp/vendor/safer-spec-development/skills/example-vendor"
  local secret="$tmp/secret-host-file"
  echo "host-private-content-must-not-inline" > "$secret"
  ln -s "$secret" "$tmp/vendor/safer-spec-development/skills/example-vendor/SKILL.md"
  write_wrapper_skill "$tmp" "example" "example-vendor"

  local rc
  local out
  out=$(cd "$tmp" && ./bin/safer-gen-skills 2>&1); rc=$?
  assert_ne "$rc" "0" "renderer refuses symlinked vendor SKILL.md" || { rm -rf "$tmp"; return 1; }
  assert_contains "$out" "refusing to inline" "stderr names the refusal" || { rm -rf "$tmp"; return 1; }
  # The host-private contents must NOT have been inlined.
  if [ -f "$tmp/skills/example/SKILL.md" ]; then
    ! grep -qF "host-private-content-must-not-inline" "$tmp/skills/example/SKILL.md" \
      || { rm -rf "$tmp"; echo "    FAIL: symlink target was inlined"; return 1; }
  fi
  rm -rf "$tmp"
}

test_vendor_skill_dir_symlink_refused() {
  # Round-2 security finding: the leaf-only `[ -L "$vendor_path" ]` check
  # missed directory-component symlinks. A compromised sister-repo merge can
  # plant the per-slug directory as a symlink pointing at an attacker-controlled
  # tree where the leaf SKILL.md is a regular file. Git represents directory
  # symlinks and file symlinks identically at the tree level. The guard must
  # close both shapes.
  local tmp; tmp=$(mktemp -d)
  build_fixture "$tmp"
  # Attacker tree: a real directory holding a real SKILL.md the attacker
  # controls. The leaf is NOT a symlink — only the slug directory is.
  local attacker_dir="$tmp/attacker-tree/example-vendor"
  mkdir -p "$attacker_dir"
  cat > "$attacker_dir/SKILL.md" <<'EOF'
---
name: example-vendor
---

# example-vendor

SECRET-CONTENT-VIA-DIR-SYMLINK-9999 — host-private vector that must never inline.
EOF
  # Plant the per-slug DIRECTORY as a symlink under the vendor tree.
  mkdir -p "$tmp/vendor/safer-spec-development/skills"
  ln -s "$attacker_dir" "$tmp/vendor/safer-spec-development/skills/example-vendor"
  write_wrapper_skill "$tmp" "example" "example-vendor"

  local rc
  local out
  out=$(cd "$tmp" && ./bin/safer-gen-skills 2>&1); rc=$?
  assert_ne "$rc" "0" "renderer refuses directory-symlink in vendor tree" || { rm -rf "$tmp"; return 1; }
  assert_contains "$out" "refusing to inline" "stderr names the directory-symlink refusal" || { rm -rf "$tmp"; return 1; }
  if [ -f "$tmp/skills/example/SKILL.md" ]; then
    ! grep -qF "SECRET-CONTENT-VIA-DIR-SYMLINK-9999" "$tmp/skills/example/SKILL.md" \
      || { rm -rf "$tmp"; echo "    FAIL: directory-symlink target was inlined"; return 1; }
  fi
  rm -rf "$tmp"
}

test_vendor_skill_in_root_dir_symlink_refused() {
  # The trickiest case: directory symlink whose target lives WITHIN the
  # vendor root. The canonical-prefix check passes (resolved path is still
  # inside $VENDOR_SKILLS_ROOT). Only the component-walk arm catches this.
  # Threat model: attacker plants a symlink to bypass per-folder governance
  # boundaries WITHIN the sister repo (e.g., redirect /skills/safer-spec-init/
  # to /skills/safer-spec-migrate/ to swap which body the wrapper renders).
  local tmp; tmp=$(mktemp -d)
  build_fixture "$tmp"
  # Plant a real target inside the vendor root.
  mkdir -p "$tmp/vendor/safer-spec-development/skills/real-target"
  cat > "$tmp/vendor/safer-spec-development/skills/real-target/SKILL.md" <<'EOF'
---
name: real-target
---

# real-target

IN-ROOT-REDIRECT-TARGET — must not inline via a directory-symlink redirect.
EOF
  # Plant a directory-symlink under the vendor root pointing at the in-root target.
  ln -s "$tmp/vendor/safer-spec-development/skills/real-target" \
    "$tmp/vendor/safer-spec-development/skills/example-vendor"
  write_wrapper_skill "$tmp" "example" "example-vendor"

  local rc
  local out
  out=$(cd "$tmp" && ./bin/safer-gen-skills 2>&1); rc=$?
  assert_ne "$rc" "0" "renderer refuses in-root directory-symlink" || { rm -rf "$tmp"; return 1; }
  assert_contains "$out" "refusing to inline" "stderr names the in-root symlink refusal" || { rm -rf "$tmp"; return 1; }
  if [ -f "$tmp/skills/example/SKILL.md" ]; then
    ! grep -qF "IN-ROOT-REDIRECT-TARGET" "$tmp/skills/example/SKILL.md" \
      || { rm -rf "$tmp"; echo "    FAIL: in-root symlink target was inlined"; return 1; }
  fi
  rm -rf "$tmp"
}

test_vendor_skill_escape_via_canonical_path_refused() {
  # Sibling shape: when the leaf or a directory symlink's target lives entirely
  # OUTSIDE $VENDOR_SKILLS_ROOT, the canonicalize+prefix-check arm fires (the
  # symlink-component walk also catches this, but the prefix-check is the
  # belt to the walk's suspenders — covering attacker patterns the walk
  # might miss as the implementation evolves).
  local tmp; tmp=$(mktemp -d)
  build_fixture "$tmp"
  local outside_target="$tmp/outside-tree/example-vendor"
  mkdir -p "$outside_target"
  cat > "$outside_target/SKILL.md" <<'EOF'
---
name: example-vendor
---

# example-vendor

ESCAPE-TARGET-CONTENT — must not inline.
EOF
  mkdir -p "$tmp/vendor/safer-spec-development/skills"
  ln -s "$outside_target" "$tmp/vendor/safer-spec-development/skills/example-vendor"
  write_wrapper_skill "$tmp" "example" "example-vendor"

  local rc
  local out
  out=$(cd "$tmp" && ./bin/safer-gen-skills 2>&1); rc=$?
  assert_ne "$rc" "0" "renderer refuses canonical-path escape" || { rm -rf "$tmp"; return 1; }
  if [ -f "$tmp/skills/example/SKILL.md" ]; then
    ! grep -qF "ESCAPE-TARGET-CONTENT" "$tmp/skills/example/SKILL.md" \
      || { rm -rf "$tmp"; echo "    FAIL: outside-root content was inlined"; return 1; }
  fi
  rm -rf "$tmp"
}

test_vendor_directive_pre_validates_missing_slug() {
  local tmp; tmp=$(mktemp -d)
  build_fixture "$tmp"
  # Wrapper references a slug that does not exist on disk.
  write_wrapper_skill "$tmp" "example" "does-not-exist"

  local rc
  local out
  out=$(cd "$tmp" && ./bin/safer-gen-skills 2>&1); rc=$?
  rm -rf "$tmp"
  assert_ne "$rc" "0" "renderer fails when vendor slug is missing" || return 1
  assert_contains "$out" "does-not-exist" "stderr names the missing slug" || return 1
}

run_test "vendor-skill directive inlines body, strips frontmatter, demotes H1" test_vendor_directive_inlines_body_and_demotes_h1
run_test "--check --release passes on a clean tree" test_check_release_passes_on_clean_tree
run_test "--check --release fails when sentinel is in SKILL.tmpl directly" test_check_release_fails_on_sentinel_in_tmpl
run_test "--check --release fails when sentinel inlines via vendor body" test_check_release_fails_on_sentinel_via_vendor_indirection
run_test "renderer refuses symlinked vendor SKILL.md (supply-chain guard, leaf)" test_vendor_skill_symlink_refused
run_test "renderer refuses directory-symlink in vendor tree (supply-chain guard, dir)" test_vendor_skill_dir_symlink_refused
run_test "renderer refuses in-root directory-symlink (component-walk arm)" test_vendor_skill_in_root_dir_symlink_refused
run_test "renderer refuses canonical-path escape outside vendor root" test_vendor_skill_escape_via_canonical_path_refused
run_test "renderer pre-validates and fails loud on missing vendor slug" test_vendor_directive_pre_validates_missing_slug
report
