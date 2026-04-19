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
#        tag >= 10 via exit propagation; stderr carries original TAXONOMY_*)
#   32 — RESOLVE_LINEAR_ERROR       (forwarded from linear-api.sh; exit
#        propagated; stderr carries original LINEAR_*)
# Error detail (stderr): `RESOLVE_<TAG>: ...` with the upstream tag cited.
#
# Rule shape (discriminated, exhaustive):
#   rule_kind in { "manual-override", "parent-ref", "parent-heading",
#                  "label-keyword", "catchall", "no-match" }
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
#   (4) label-keyword     — first label in taxonomy.labelMap, file order
#   (5) catchall          — emitted by the CALLER, not this module; this
#                           module returns empty stdout on no-match.
#
# Taxonomy path: callers must set _SAFER_TAXO_PATH before calling resolve
# functions. Defaults to config/linear-taxonomy.yaml relative to CWD.
#
# Public surface:
#   resolve_project <gh_number> <body> <labels>
#   extract_manual_override <body>
#   extract_parent_ref <body>
#   extract_parent_heading <body>
#   match_label_keyword <labels>

# Default taxonomy path (callers override by exporting _SAFER_TAXO_PATH).
: "${_SAFER_TAXO_PATH:=config/linear-taxonomy.yaml}"

# resolve_project GH_NUMBER BODY LABELS
#   Full ranked-rules walk. Stops at first rule that produces a non-empty
#   project name. On success with no match, stdout is empty.
#   Rule 2/3: if the parent marker is present but linear_get_parent_project
#   returns empty, falls through (empty parent = non-match). If the Linear
#   API call fails, returns 32 — transient errors must not silently degrade.
#   Stdout: resolved project name, or empty. Exit: 0 | 30 | 31 | 32.
resolve_project() {
  local gh_number="$1" body="$2" labels="$3"

  if [[ ! "$gh_number" =~ ^[0-9]+$ ]]; then
    printf 'RESOLVE_BAD_INPUT: gh_number must be numeric, got %q\n' "$gh_number" >&2; return 30
  fi

  # Rule (1): manual override
  local override
  override=$(extract_manual_override "$body") || return $?
  if [[ -n "$override" ]]; then
    printf '%s\n' "$override"; return 0
  fi

  # Rule (2): parent-ref
  local parent_ref
  parent_ref=$(extract_parent_ref "$body") || return $?
  if [[ -n "$parent_ref" ]]; then
    local parent_project
    parent_project=$(linear_get_parent_project "$parent_ref") || {
      printf 'RESOLVE_LINEAR_ERROR: linear_get_parent_project failed for parent #%s\n' "$parent_ref" >&2; return 32
    }
    if [[ -n "$parent_project" ]]; then
      printf '%s\n' "$parent_project"; return 0
    fi
    # Empty parent project = non-match: fall through (plan §5 concern 1)
  fi

  # Rule (3): parent-heading (single-hop; Q3)
  local parent_heading
  parent_heading=$(extract_parent_heading "$body") || return $?
  if [[ -n "$parent_heading" ]]; then
    local heading_project
    heading_project=$(linear_get_parent_project "$parent_heading") || {
      printf 'RESOLVE_LINEAR_ERROR: linear_get_parent_project failed for heading #%s\n' "$parent_heading" >&2; return 32
    }
    if [[ -n "$heading_project" ]]; then
      printf '%s\n' "$heading_project"; return 0
    fi
    # Empty parent project = non-match: fall through (plan §5 concern 1)
  fi

  # Rule (4): label-keyword
  local label_project
  label_project=$(match_label_keyword "$labels") || {
    local rc=$?
    [[ $rc -eq 31 ]] && printf 'RESOLVE_TAXONOMY_ERROR: match_label_keyword failed\n' >&2
    return $rc
  }
  if [[ -n "$label_project" ]]; then
    printf '%s\n' "$label_project"; return 0
  fi

  # Rule (5): no match — caller substitutes catchall
  return 0
}

# extract_manual_override BODY
#   Parses rule (1): first occurrence of a line matching `^Linear-project:`.
#   Returns the trimmed value. No Linear call. No taxonomy check.
#   Stdout: project name or empty. Exit: 0 | 30.
extract_manual_override() {
  local body="$1"
  local match
  match=$(printf '%s' "$body" | grep -i '^Linear-project:' | head -1 || true)
  [[ -z "$match" ]] && return 0
  # Strip the key, drop trailing `# comment`, then trim leading/trailing whitespace.
  printf '%s' "$match" \
    | sed 's/^[Ll]inear-project: *//;s/ *#.*//;s/^[[:space:]]*//;s/[[:space:]]*$//'
}

# extract_parent_ref BODY
#   Parses rule (2) marker: first line matching `^Parent:\s*#(\d+)`.
#   Returns the captured issue number, or empty.
#   Stdout: GH issue number or empty. Exit: 0 | 30.
extract_parent_ref() {
  local body="$1"
  local match
  match=$(printf '%s' "$body" | grep -i '^Parent: *#' | head -1 || true)
  [[ -z "$match" ]] && return 0
  printf '%s' "$match" | sed 's/.*#\([0-9][0-9]*\).*/\1/'
}

# extract_parent_heading BODY
#   Parses rule (3) marker: `^## Parent` heading with a following line that
#   contains `#<number>`. Returns that number or empty. Single-hop only (Q3).
#   Stdout: GH issue number or empty. Exit: 0 | 30.
extract_parent_heading() {
  local body="$1"
  local after_heading
  after_heading=$(printf '%s' "$body" | grep -A 2 '^## Parent' | grep -o '#[0-9][0-9]*' | head -1 || true)
  [[ -z "$after_heading" ]] && return 0
  printf '%s' "$after_heading" | sed 's/#//'
}

# match_label_keyword LABELS
#   Scans LABELS (newline-delimited) against taxonomy.labelMap, file order,
#   first-match-wins. Uses _SAFER_TAXO_PATH for the taxonomy.
#   Stdout: project name or empty. Exit: 0 | 30 | 31.
match_label_keyword() {
  local labels="$1"
  local label_map
  label_map=$(taxonomy_label_map "$_SAFER_TAXO_PATH") || {
    printf 'RESOLVE_TAXONOMY_ERROR: taxonomy_label_map failed\n' >&2; return 31
  }
  while IFS=$'\t' read -r lbl prj; do
    if printf '%s\n' "$labels" | grep -qx "$lbl"; then
      printf '%s\n' "$prj"; return 0
    fi
  done <<< "$label_map"
  return 0
}
