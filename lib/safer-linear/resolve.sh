#!/usr/bin/env bash
# lib/safer-linear/resolve.sh
#
# Responsibility: pure ranked-rules resolution engine. Given a GitHub issue's
# body + labels + number, produces the Linear project name the assignment
# flow should target, or the empty string when every rule misses (caller
# substitutes the catchall and counts the event).
#
# Dependencies:
#   lib/safer-linear/taxonomy.sh  (label-keyword map + project membership)
#   lib/safer-linear/linear-api.sh (parent-project lookup for rules 2/3)
# Error channel (every public function):
#   0  — success; resolved project name on stdout (empty = no rule matched)
#   30 — RESOLVE_BAD_INPUT          (gh_number not numeric; body/labels unset)
#   31 — RESOLVE_TAXONOMY_ERROR     (forwarded from taxonomy.sh, preserving
#        tag ≥ 10 via exit propagation; stderr carries original TAXONOMY_*)
#   32 — RESOLVE_LINEAR_ERROR       (forwarded from linear-api.sh; exit
#        propagated; stderr carries original LINEAR_*)
# Error detail (stderr): `RESOLVE_<TAG>: ...` with the upstream tag cited.
#
# Rule shape (discriminated, exhaustive):
#   rule_kind ∈ { "manual-override", "parent-ref", "parent-heading",
#                 "label-keyword", "catchall", "no-match" }
#   A rule "matches" iff it produces a non-empty project name. Presence of
#   the marker (e.g. a `Parent: #N` line) is NOT a match if the parent has
#   no Linear project — control falls through to the next rule. This is the
#   fallthrough semantics concern flagged in sub-issue #120: the invariant
#   "parent-link primacy" in the spec is conditional on the parent actually
#   having a project; when it does not, label-keyword is permitted to match.
#
# Precedence (spec acceptance #2):
#   (1) manual-override   — body line `Linear-project: <name>`
#   (2) parent-ref        — body line `Parent: #N`, parent's project nonempty
#   (3) parent-heading    — `## Parent` heading followed by `#N`, parent's
#                           project nonempty (single-hop only; Q3 decision)
#   (4) label-keyword     — first label ∈ taxonomy.labelMap, file order
#   (5) catchall          — emitted by the CALLER, not this module; this
#                           module returns empty stdout on no-match.
#
# Public surface:
#   resolve_project <gh_number> <body> <labels>
#   extract_manual_override <body>
#   extract_parent_ref <body>
#   extract_parent_heading <body>
#   match_label_keyword <labels>

# resolve_project GH_NUMBER BODY LABELS
#   Full ranked-rules walk. Stops at first rule that produces a non-empty
#   project name. On success with no match, stdout is empty (NOT the
#   catchall; catchall substitution is the caller's concern for logging/
#   counter discipline).
#   Rule 2/3 require a Linear API call (via linear_get_parent_project). If
#   that call fails, the function returns 32 with no fallthrough — a
#   transient Linear error must not silently degrade the decision.
#   Stdout: resolved project name, or empty. Exit: 0 | 30 | 31 | 32.
resolve_project() {
  echo "not implemented: resolve_project" >&2
  return 99
}

# extract_manual_override BODY
#   Parses rule (1): first occurrence of a line matching `^Linear-project:`.
#   Returns the trimmed value (everything after the colon, before an
#   optional trailing `#` comment). No Linear call. No taxonomy check —
#   honoring a user-named-but-taxonomy-absent project is the caller's
#   policy decision per spec Q3.
#   Stdout: project name or empty. Exit: 0 | 30.
extract_manual_override() {
  echo "not implemented: extract_manual_override" >&2
  return 99
}

# extract_parent_ref BODY
#   Parses rule (2) marker: first line matching `^Parent:\s*#(\d+)`. Returns
#   the captured issue number as a decimal string, or empty.
#   Stdout: GH issue number or empty. Exit: 0 | 30.
extract_parent_ref() {
  echo "not implemented: extract_parent_ref" >&2
  return 99
}

# extract_parent_heading BODY
#   Parses rule (3) marker: `^## Parent` heading with a following line that
#   contains `#<number>`. Returns that number or empty. Single-hop only
#   (Q3 decision): this function NEVER walks past the immediate parent.
#   Stdout: GH issue number or empty. Exit: 0 | 30.
extract_parent_heading() {
  echo "not implemented: extract_parent_heading" >&2
  return 99
}

# match_label_keyword LABELS
#   Scans `labels` (newline-delimited, as produced by
#   `gh issue list --json labels | jq -r '.labels | map(.name) | join("\n")'`)
#   against taxonomy.labelMap, in file order, first-match-wins.
#   Stdout: project name or empty. Exit: 0 | 30 | 31.
match_label_keyword() {
  echo "not implemented: match_label_keyword" >&2
  return 99
}
