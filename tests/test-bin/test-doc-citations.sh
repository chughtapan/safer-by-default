#!/usr/bin/env bash
# test-doc-citations.sh — pins the class of defect that a stale-render check
# cannot see: a document citing something that does not exist.
#
# safer-gen-skills --check compares each SKILL.tmpl against its rendered
# SKILL.md. That catches an un-rendered edit. It does not read prose, so it
# passes happily while AGENTS.md points at a PRINCIPLES.md heading nobody
# wrote, or scenarios/README.md links a spec file that was deleted. Both
# shipped and survived until a human went looking.
#
# This checker has itself reported green on the defect it was written for
# twice, so every check below carries a control that plants the REAL defect
# shape rather than a synthetic one:
#   - v1 matched only the bare-filename citation form, so it never saw the
#     markdown-link form that AGENTS.md actually uses.
#   - v2 compared with `grep -qF`, a substring match, so renaming a heading
#     to "<original> RENAMED" still matched and the run stayed green.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

ROOT="$(cd "$HERE/../.." && pwd)"

# Every hand-authored doc that can carry a citation.
#
# Generated `SKILL.md` files are excluded because they are renders of
# `SKILL.tmpl`, which IS in this set, so a bad citation is caught at its
# source. That claim is only true because the templates are listed below; an
# earlier version of this comment asserted the coverage while the templates
# were out of scope, which is exactly the kind of unchecked claim this file
# exists to catch.
#
# `CHANGELOG.md` is in the link set but NOT the citation set, and the reason
# is evidenced rather than theoretical.
#
# A changelog entry that documents a citation fix must quote the broken
# citation to be intelligible: "cited PRINCIPLES.md -> Durability (the heading
# is Durable records)". That sentence is indistinguishable, to any extractor,
# from the defect it describes. It happened twice while writing this file, and
# it will happen every time a citation fix is documented, so rewording is
# whack-a-mole rather than a fix.
#
# The distinction is real, not convenient: the check exists to stop a doc from
# sending a reader to a heading that does not exist. A changelog is not sending
# the reader anywhere; it is recording that someone else once did. Links are
# still checked, because a changelog link is a live link.
doc_set() {
  find "$ROOT" -maxdepth 1 -name '*.md' -type f
  find "$ROOT/scenarios" "$ROOT/docs" -name '*.md' -type f 2>/dev/null
  find "$ROOT/skills" -name 'SKILL.tmpl' -type f 2>/dev/null
  find "$ROOT/skills" \( -path '*/references/*.md' -o -path '*/prompts/*.md' \) -type f 2>/dev/null
  find "$ROOT/skills/_shared" -name '*.md' -type f 2>/dev/null
}

citation_doc_set() {
  doc_set | grep -v '/CHANGELOG\.md$'
}

principles_headings() {
  grep -E '^#{1,6} ' "$ROOT/PRINCIPLES.md" | sed 's/^#\{1,6\} //'
}

# ---------------------------------------------------------------------------
# 1. Relative markdown links resolve.

# Strip fenced code blocks. Skill templates embed bash and jq, and a jq
# interpolation like "[#\(.number)](\(.url))" is a perfect false positive for
# the markdown-link pattern. Prose is what carries citations; code is not.
prose_only() {
  awk '/^[[:space:]]*```/ { infence = !infence; next } !infence' "$1"
}

test_relative_links_resolve() {
  local broken="" doc target resolved
  while IFS= read -r doc; do
    [ -f "$doc" ] || continue
    while IFS= read -r target; do
      [ -n "$target" ] || continue
      case "$target" in
        http://*|https://*|mailto:*|'#'*|'$'*|*'\('*) continue ;;
      esac
      resolved="$(dirname "$doc")/${target%%#*}"
      [ -e "$resolved" ] || broken="$broken\n  $doc -> $target"
    done < <(prose_only "$doc" | grep -oE '\]\([^)]+\)' | sed 's/^](//; s/)$//')
  done < <(doc_set)

  [ -z "$broken" ] || { printf 'broken relative links:%b\n' "$broken" >&2; return 1; }
}

# ---------------------------------------------------------------------------
# 2. Quoted citations name a real heading.
#
# The mention is usually a markdown link, so anchoring the arrow directly to
# the filename misses the common form. Comparison is `grep -qxF`: exact
# whole-line. A substring match reports green on any heading whose text was
# extended rather than replaced, which is how v2 passed a renamed heading.

cited_headings() {
  grep -E 'PRINCIPLES\.md.*(->|→)[[:space:]]*"' "$1" 2>/dev/null \
    | sed 's/.*\(->\|→\)[[:space:]]*"\([^"]*\)".*/\2/'
}

test_quoted_citations_resolve() {
  local headings missing="" doc cited
  headings="$(principles_headings)"
  while IFS= read -r doc; do
    [ -f "$doc" ] || continue
    while IFS= read -r cited; do
      [ -n "$cited" ] || continue
      printf '%s\n' "$headings" | grep -qxF "$cited" \
        || missing="$missing\n  $doc cites \"$cited\""
    done < <(cited_headings "$doc")
  done < <(citation_doc_set)

  [ -z "$missing" ] || {
    printf 'citations to nonexistent PRINCIPLES.md headings:%b\n' "$missing" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# 3. Unquoted citations resolve too.
#
# The repo's dominant convention is unquoted and often abbreviated:
# `PRINCIPLES.md -> Part 3` for the heading "Part 3 - Stamina", and chained
# forms like `-> Contracts -> Goal modes`. An earlier version of this check
# demanded the quoted form instead, which would have rewritten eleven call
# sites to satisfy the checker rather than checking the convention actually in
# use. Parse it instead.
#
# A citation resolves when some heading H is a prefix of the cited text, or the
# cited text is a prefix of H. That accepts abbreviation ("Part 3" for "Part 3
# - Stamina") and trailing sentence text ("Goal modes requires"), while still
# rejecting a name no heading starts with.

unquoted_cited() {
  prose_only "$1" 2>/dev/null \
    | grep -oE 'PRINCIPLES\.md`?\)?[[:space:]]*(->|→)[[:space:]]*[^",.)(]*' \
    | sed 's/.*\(->\|→\)[[:space:]]*//' \
    | sed 's/[[:space:]]*\(->\|→\)[[:space:]]*/\n/g' \
    | sed 's/`//g; s/[[:space:]]*$//' \
    | grep -v '^$'
}

test_unquoted_citations_resolve() {
  local headings missing="" doc cited
  headings="$(principles_headings)"
  while IFS= read -r doc; do
    [ -f "$doc" ] || continue
    while IFS= read -r cited; do
      [ -n "$cited" ] || continue
      printf '%s\n' "$headings" | grep -qF "$cited" && continue
      # Cited text may carry trailing sentence words; accept if it starts with
      # a real heading.
      local ok=0 h
      while IFS= read -r h; do
        case "$cited" in "$h"*) ok=1; break ;; esac
      done < <(printf '%s\n' "$headings")
      [ "$ok" = 1 ] || missing="$missing\n  $doc cites \"$cited\""
    done < <(unquoted_cited "$doc")
  done < <(citation_doc_set)

  [ -z "$missing" ] || {
    printf 'unquoted citations naming no PRINCIPLES.md heading:%b\n' "$missing" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# 4. Controls. Each plants the real defect shape this checker has shipped.

test_controls_catch_real_defect_shapes() {
  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  local cited

  # (a) The markdown-link form, which v1 missed.
  printf '# t\n\nSee [`PRINCIPLES.md`](./PRINCIPLES.md) → "No Such Heading Anywhere".\n' \
    > "$tmp/a.md"
  cited="$(cited_headings "$tmp/a.md")"
  [ "$cited" = "No Such Heading Anywhere" ] || {
    echo "extractor missed the markdown-link form (got '$cited')" >&2; return 1; }

  # (b) Substring vs exact, which v2 got wrong. A heading extended with a
  # suffix must NOT satisfy a citation to the original.
  if printf '%s\n' "Composing with gstack RENAMED" | grep -qxF "Composing with gstack"; then
    echo "exact-match comparison regressed to substring" >&2; return 1
  fi
  printf '%s\n' "Composing with gstack RENAMED" | grep -qF "Composing with gstack" || {
    echo "control no longer exercises the substring case" >&2; return 1; }

  # (c) An unquoted citation naming no heading is extracted.
  printf '# t\n\nPer PRINCIPLES.md → Durability, do the thing.\n' > "$tmp/c.md"
  [ "$(unquoted_cited "$tmp/c.md")" = "Durability" ] || {
    echo "unquoted extractor failed (got '$(unquoted_cited "$tmp/c.md")')" >&2; return 1; }

  # (d) and (e) assert RESOLUTION, not extraction text. The extractor
  # over-captures when a citation is not followed by punctuation ("Goal modes
  # here"), and that is fine: the prefix rule resolves it against the real
  # heading. Asserting the extracted string instead made these controls fail
  # on inputs the checker handles correctly.
  resolves() {  # $1 = cited text
    printf '%s\n' "$(principles_headings)" | grep -qF "$1" && return 0
    local h
    while IFS= read -r h; do
      case "$1" in "$h"*) return 0 ;; esac
    done < <(principles_headings)
    return 1
  }

  # Abbreviated citation, the repo's dominant form.
  printf '# t\n\nThe table lives in `PRINCIPLES.md` → Part 3.\n' > "$tmp/d.md"
  resolves "$(unquoted_cited "$tmp/d.md")" || {
    echo "abbreviated citation did not resolve" >&2; return 1; }

  # Chained citation, with and without trailing punctuation.
  printf '# t\n\nSee `PRINCIPLES.md` → Contracts → Goal modes here.\n' > "$tmp/e.md"
  resolves "$(unquoted_cited "$tmp/e.md" | tail -1)" || {
    echo "chained citation did not resolve" >&2; return 1; }

  # And a name no heading starts with must NOT resolve.
  resolves "Durability" && {
    echo "'Durability' resolved; the check would miss the real defect" >&2; return 1; }

  # (f) Code fences are not scanned. A jq interpolation is a perfect false
  # positive for the markdown-link pattern.
  printf '# t\n\n```bash\necho "[#1](\\(.url))"\n```\n' > "$tmp/f.md"
  [ -z "$(prose_only "$tmp/f.md" | grep -oE '\]\([^)]+\)')" ] || {
    echo "code fence was scanned for links" >&2; return 1; }

  return 0
}

run_test "relative markdown links resolve to real paths"         test_relative_links_resolve
run_test "quoted PRINCIPLES.md citations name real headings"      test_quoted_citations_resolve
run_test "unquoted PRINCIPLES.md citations resolve by prefix"      test_unquoted_citations_resolve
run_test "controls catch the real defect shapes"                  test_controls_catch_real_defect_shapes

report
