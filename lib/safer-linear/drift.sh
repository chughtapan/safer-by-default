#!/usr/bin/env bash
# lib/safer-linear/drift.sh
#
# Responsibility: compare the in-repo taxonomy against Linear's live project
# set. Two public entry points share that plumbing:
#
#   drift_report         — read-only; prints both deltas to stdout or JSON.
#                          Exit 0 if no drift, 2 if any drift detected.
#
#   bootstrap_verify_preexisting
#                        — Q1 decision: require-preexisting. Preflight for
#                          the assignment flow. Succeeds iff every project
#                          named in the taxonomy exists in Linear. On first
#                          missing project, prints the error line required
#                          by spec acceptance "missing-project is loud" and
#                          exits nonzero with tag 42.
#
# Both functions validate the taxonomy first (taxonomy.sh::validate_taxonomy).
# Neither mutates Linear. Creation of projects is explicitly out of scope
# for v2 per Q1.
#
# Dependencies:
#   lib/safer-linear/taxonomy.sh
#   lib/safer-linear/linear-api.sh
# Error channel:
#   0  — success (for drift_report: no drift; for bootstrap: all present)
#   2  — drift_report: drift present (operator-visible signal; read-only)
#   40 — DRIFT_TAXONOMY_ERROR     (forwarded from taxonomy.sh)
#   41 — DRIFT_LINEAR_ERROR       (forwarded from linear-api.sh)
#   42 — BOOTSTRAP_MISSING_PROJECT (spec: fail-loudly Q1)
# Error detail (stderr): `DRIFT_<TAG>: ...` or `BOOTSTRAP_<TAG>: ...`.
#
# Output shape for drift_report (text format, default):
#   DRIFT in-taxonomy-not-in-linear: <name>
#   DRIFT in-linear-not-in-taxonomy: <name>
#   DRIFT summary: missing_in_linear=<N> extra_in_linear=<M>
# JSON format (--format=json):
#   { "missingInLinear": ["..."], "extraInLinear": ["..."], "drift": true|false }
#
# Public surface:
#   drift_report <taxonomy-path> [--format=text|json]
#   bootstrap_verify_preexisting <taxonomy-path>

# Internal: validate taxonomy + fetch live Linear projects.
# On success, sets caller's local vars taxonomy_names and linear_names
# (newline-delimited sorted lists).
# Returns 0|40|41.
_drift_load() {
  local taxonomy_path="$1"

  validate_taxonomy "$taxonomy_path" || {
    printf 'DRIFT_TAXONOMY_ERROR: validate_taxonomy failed for %s\n' "$taxonomy_path" >&2; return 40
  }

  local taxo_projects
  taxo_projects=$(taxonomy_projects "$taxonomy_path") || {
    printf 'DRIFT_TAXONOMY_ERROR: taxonomy_projects failed\n' >&2; return 40
  }

  local live_json
  live_json=$(linear_list_projects) || {
    printf 'DRIFT_LINEAR_ERROR: linear_list_projects failed\n' >&2; return 41
  }

  local live_projects
  live_projects=$(printf '%s\n' "$live_json" | jq -r '.[].name')

  # Export via nameref-style globals for caller (same process)
  _DRIFT_TAXO_NAMES=$(printf '%s\n' "$taxo_projects" | sort)
  _DRIFT_LIVE_NAMES=$(printf '%s\n' "$live_projects" | sort)
}

# drift_report TAXONOMY_PATH [--format=text|json]
#   Read-only comparison. Exit: 0 (no drift) | 2 (drift) | 40 | 41.
drift_report() {
  local taxonomy_path="$1"
  local format="text"
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --format=*) format="${1#--format=}" ;;
      --format)   format="$2"; shift ;;
    esac
    shift
  done

  local _DRIFT_TAXO_NAMES _DRIFT_LIVE_NAMES
  _drift_load "$taxonomy_path" || return $?

  # missing_in_linear = in taxonomy but not in live
  local missing_in_linear
  missing_in_linear=$(comm -23 \
    <(printf '%s\n' "$_DRIFT_TAXO_NAMES") \
    <(printf '%s\n' "$_DRIFT_LIVE_NAMES"))

  # extra_in_linear = in live but not in taxonomy
  local extra_in_linear
  extra_in_linear=$(comm -13 \
    <(printf '%s\n' "$_DRIFT_TAXO_NAMES") \
    <(printf '%s\n' "$_DRIFT_LIVE_NAMES"))

  # `comm` returns empty for an empty diff, so a non-empty var means >=1 line.
  local missing_count=0 extra_count=0
  [[ -n "$missing_in_linear" ]] && missing_count=$(printf '%s\n' "$missing_in_linear" | grep -c '.')
  [[ -n "$extra_in_linear"   ]] && extra_count=$(printf '%s\n' "$extra_in_linear" | grep -c '.')

  local has_drift=false
  [[ "$missing_count" -gt 0 || "$extra_count" -gt 0 ]] && has_drift=true

  if [[ "$format" == "json" ]]; then
    local missing_arr extra_arr
    missing_arr=$(printf '%s\n' "$missing_in_linear" | jq -Rs 'split("\n") | map(select(. != ""))')
    extra_arr=$(printf '%s\n' "$extra_in_linear" | jq -Rs 'split("\n") | map(select(. != ""))')
    jq -n \
      --argjson m "$missing_arr" \
      --argjson e "$extra_arr" \
      --argjson d "$has_drift" \
      '{missingInLinear: $m, extraInLinear: $e, drift: $d}'
  else
    while IFS= read -r name; do
      [[ -z "$name" ]] && continue
      printf 'DRIFT in-taxonomy-not-in-linear: %s\n' "$name"
    done <<< "$missing_in_linear"
    while IFS= read -r name; do
      [[ -z "$name" ]] && continue
      printf 'DRIFT in-linear-not-in-taxonomy: %s\n' "$name"
    done <<< "$extra_in_linear"
    printf 'DRIFT summary: missing_in_linear=%d extra_in_linear=%d\n' "$missing_count" "$extra_count"
  fi

  [[ "$has_drift" == true ]] && return 2
  return 0
}

# bootstrap_verify_preexisting TAXONOMY_PATH
#   Q1 behavior: require-preexisting. Exit: 0 | 40 | 41 | 42.
bootstrap_verify_preexisting() {
  local taxonomy_path="$1"

  local _DRIFT_TAXO_NAMES _DRIFT_LIVE_NAMES
  _drift_load "$taxonomy_path" || return $?

  while IFS= read -r project; do
    [[ -z "$project" ]] && continue
    if ! printf '%s\n' "$_DRIFT_LIVE_NAMES" | grep -qx "$project"; then
      printf 'BOOTSTRAP_MISSING_PROJECT: project "%s" not found in Linear — create it first\n' "$project" >&2
      return 42
    fi
  done <<< "$_DRIFT_TAXO_NAMES"

  return 0
}
