#!/usr/bin/env bash
# test-doc-citations.sh — pins the class of defect that a stale-render check
# cannot see: a document citing something that does not exist.
#
# safer-gen-skills --check compares each SKILL.tmpl against its rendered
# SKILL.md. That catches an un-rendered edit. It does not read prose, so it
# passes happily while AGENTS.md points at a PRINCIPLES.md heading that was
# never written, or scenarios/README.md links a spec file that was deleted.
# Both of those shipped and survived until a human went looking.
#
# Two checks, both cheap and both local:
#   1. Relative markdown links in the docs resolve to a real path.
#   2. `PRINCIPLES.md` -> "Heading" citations name a heading that exists.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

ROOT="$(cd "$HERE/../.." && pwd)"

# Docs a cold-start reader actually opens.
#
# Two exclusions, both principled rather than convenient:
#
#   - Skill bodies. They are generated, and their citations are covered by the
#     templates they render from.
#   - CHANGELOG.md. A changelog describes the past, including headings that were
#     renamed away and files that were deleted on purpose. "Removed the LSP
#     layer" and "cited a heading that did not exist" are correct entries whose
#     targets must NOT resolve. Requiring them to resolve would make an accurate
#     changelog unwritable, and would also flag any entry that quotes the
#     citation pattern while explaining it.
doc_set() {
  find "$ROOT" -maxdepth 1 -name '*.md' -type f ! -name 'CHANGELOG.md'
  find "$ROOT/scenarios" "$ROOT/docs" -name '*.md' -type f 2>/dev/null
}

# ---------------------------------------------------------------------------
# 1. Relative markdown links resolve.

test_relative_links_resolve() {
  local broken=""
  local doc target resolved
  while IFS= read -r doc; do
    [ -f "$doc" ] || continue
    # ](path) where path is relative, not a URL, not an anchor-only ref.
    while IFS= read -r target; do
      [ -n "$target" ] || continue
      case "$target" in
        http://*|https://*|mailto:*|'#'*) continue ;;
      esac
      # Strip any #anchor suffix; the path is what must exist.
      resolved="$(dirname "$doc")/${target%%#*}"
      [ -e "$resolved" ] || broken="$broken\n  $doc -> $target"
    done < <(grep -oE '\]\([^)]+\)' "$doc" | sed 's/^](//; s/)$//')
  done < <(doc_set)

  if [ -n "$broken" ]; then
    printf 'broken relative links:%b\n' "$broken" >&2
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 2. `PRINCIPLES.md` -> "Heading" citations name a real heading.
#
# This is the exact shape of the AGENTS.md:69 defect: a citation written as
# prose rather than as a link, so no link checker would ever see it.

# Extract every heading name cited from a doc. A citation is any line that
# mentions PRINCIPLES.md, then an arrow, then a quoted name. The mention is
# usually a markdown link (`[`PRINCIPLES.md`](./PRINCIPLES.md) -> "X"`), so
# anchoring the arrow directly to the filename misses the common form. It did:
# the first version of this check reported green on the exact AGENTS.md defect
# that motivated writing it.
cited_headings() {
  grep -E 'PRINCIPLES\.md.*(->|→)[[:space:]]*"' "$1" 2>/dev/null \
    | sed 's/.*\(->\|→\)[[:space:]]*"\([^"]*\)".*/\2/'
}

principles_headings() {
  grep -E '^#{1,6} ' "$ROOT/PRINCIPLES.md" | sed 's/^#\{1,6\} //'
}

test_principles_heading_citations_resolve() {
  [ -f "$ROOT/PRINCIPLES.md" ] || { echo "PRINCIPLES.md missing" >&2; return 1; }

  local headings
  headings="$(principles_headings)"

  local missing=""
  local doc cited
  while IFS= read -r doc; do
    [ -f "$doc" ] || continue
    while IFS= read -r cited; do
      [ -n "$cited" ] || continue
      printf '%s\n' "$headings" | grep -qF "$cited" \
        || missing="$missing\n  $doc cites \"$cited\""
    done < <(cited_headings "$doc")
  done < <(doc_set)

  if [ -n "$missing" ]; then
    printf 'citations to nonexistent PRINCIPLES.md headings:%b\n' "$missing" >&2
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 3. Negative control: the checks fail when they should.
#
# A checker that cannot fail is worse than no checker, because it reports
# green. Plant both defect shapes in a temp copy and assert each is caught.

test_checks_catch_planted_defects() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  printf '# t\n\n[dead](./no-such-file.md)\n' > "$tmp/broken-link.md"
  grep -oE '\]\([^)]+\)' "$tmp/broken-link.md" | grep -q 'no-such-file' || return 1
  [ -e "$tmp/no-such-file.md" ] && return 1

  # Use the citation form that actually appears in the tree, a markdown link
  # followed by the arrow, not the bare-filename form. The bare form is the
  # one the first version of this check handled, which is why it passed while
  # the real defect sat in AGENTS.md untouched.
  printf '# t\n\nSee [`PRINCIPLES.md`](./PRINCIPLES.md) → "No Such Heading Anywhere".\n' \
    > "$tmp/bad-cite.md"
  local cited
  cited="$(cited_headings "$tmp/bad-cite.md")"
  [ "$cited" = "No Such Heading Anywhere" ] || {
    echo "citation extractor missed the markdown-link form (got: '$cited')" >&2
    return 1
  }
  principles_headings | grep -qF "$cited" && return 1

  # And the plain form still works.
  printf '# t\n\nSee `PRINCIPLES.md` -> "Also Not A Heading".\n' > "$tmp/bad-cite2.md"
  [ "$(cited_headings "$tmp/bad-cite2.md")" = "Also Not A Heading" ] || return 1

  return 0
}

run_test "relative markdown links resolve to real paths"        test_relative_links_resolve
run_test "PRINCIPLES.md heading citations name real headings"   test_principles_heading_citations_resolve
run_test "both checks catch a planted defect"                   test_checks_catch_planted_defects

report
