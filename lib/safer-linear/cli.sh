#!/usr/bin/env bash
# lib/safer-linear/cli.sh
#
# Responsibility: subcommand dispatcher + flag parser for the
# safer-linear-setup entry point. Owns ONLY: argv parsing, subcommand
# routing, result counters, human/machine-readable exit messages. Every
# domain concern (YAML, Linear API, rules) is delegated to the dedicated
# module.
#
# In the implementation PR, `bin/safer-linear-setup` is a four-line shim:
# strict mode + `source lib/safer-linear/cli.sh` + `cli_main "$@"`.
# This module is not executable on its own; it is sourced.
#
# Dependencies:
#   lib/safer-linear/taxonomy.sh
#   lib/safer-linear/linear-api.sh
#   lib/safer-linear/resolve.sh
#   lib/safer-linear/drift.sh
#
# Error channel (propagates module exit codes):
#   0   — success
#   1   — unknown subcommand / bad flags (user error; prints usage)
#   2   — drift_report detected drift (read-only signal)
#   10+ — forwarded from taxonomy.sh
#   20+ — forwarded from linear-api.sh
#   30+ — forwarded from resolve.sh
#   40+ — forwarded from drift.sh
#
# Subcommand surface (discriminated union, exhaustive):
#   subcommand in { "assign-projects", "drift-report",
#                   "bootstrap-verify", "help" }
#   Any other value → usage + exit 1.
#
# Public surface:
#   cli_main <argv...>
#   cli_usage
#   cmd_assign_projects <argv...>
#   cmd_drift_report <argv...>
#   cmd_bootstrap_verify <argv...>

_CLI_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all dependency modules once (guard against double-sourcing).
if [[ -z "${_CLI_TAXONOMY_LOADED:-}" ]]; then
  # shellcheck disable=SC1091
  source "$_CLI_LIB_DIR/taxonomy.sh"
  source "$_CLI_LIB_DIR/linear-api.sh"
  source "$_CLI_LIB_DIR/resolve.sh"
  source "$_CLI_LIB_DIR/drift.sh"
  _CLI_TAXONOMY_LOADED=1
fi

# cli_main ARGV...
#   Entry point. Parses the first positional arg as subcommand, routes to
#   the matching cmd_* handler. Unknown or absent subcommand prints usage
#   and exits 1.
#   Exit: dispatched handler's exit code, or 1 on unknown.
cli_main() {
  local subcommand="${1:-help}"
  shift || true

  case "$subcommand" in
    assign-projects)  cmd_assign_projects "$@" ;;
    drift-report)     cmd_drift_report "$@" ;;
    bootstrap-verify) cmd_bootstrap_verify "$@" ;;
    help|--help|-h)   cli_usage; return 0 ;;
    *)
      printf 'ERROR: unknown subcommand %q\n' "$subcommand" >&2
      cli_usage >&2; return 1 ;;
  esac
}

# cli_usage
#   Prints the full usage text to stdout. Exit: 0.
cli_usage() {
  cat <<'EOF'
Usage: safer-linear-setup <subcommand> [flags]

Subcommands:
  assign-projects  Assign GitHub issues to Linear projects per ranked rules.
  drift-report     Read-only: compare taxonomy vs live Linear projects.
  bootstrap-verify Verify all taxonomy projects exist in Linear.
  help             Print this usage text.

assign-projects flags:
  --all                Process all open issues.
  --since <duration>   Process issues updated within duration (e.g. 1h, 30m, 7d).
  --dry-run            Preview assignments; make no Linear mutations.
  --quiet              Suppress per-issue lines; print only RESULT summary.
  --taxonomy <path>    Path to taxonomy YAML (default: config/linear-taxonomy.yaml).

drift-report flags:
  --taxonomy <path>    Path to taxonomy YAML (default: config/linear-taxonomy.yaml).
  --format text|json   Output format (default: text).

bootstrap-verify flags:
  --taxonomy <path>    Path to taxonomy YAML (default: config/linear-taxonomy.yaml).

Exit codes:
  0  Success (or no drift for drift-report).
  1  Usage error (unknown subcommand or bad flags).
  2  Drift detected (drift-report only; read-only signal).
  42 Missing project in Linear (bootstrap/assign-projects).
  10-12 Taxonomy parse/schema error.
  20-24 Linear API error.
  30-32 Issue resolution error.
  40-41 Drift plumbing error.
EOF
}

# cmd_assign_projects ARGV...
#   Flags: --all | --since <duration>  (mutually exclusive, exactly one)
#          --dry-run
#          --quiet
#          --taxonomy <path>
#   Order: bootstrap_verify_preexisting → enumerate issues → per-issue loop.
cmd_assign_projects() {
  local all_flag=false since_duration="" dry_run=false quiet=false
  local taxonomy_path="${_SAFER_TAXO_PATH:-config/linear-taxonomy.yaml}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all)          all_flag=true ;;
      --since)        since_duration="$2"; shift ;;
      --dry-run)      dry_run=true ;;
      --quiet)        quiet=true ;;
      --taxonomy)     taxonomy_path="$2"; shift ;;
      --taxonomy=*)   taxonomy_path="${1#--taxonomy=}" ;;
      *)              printf 'ERROR: unknown flag %q\n' "$1" >&2; cli_usage >&2; return 1 ;;
    esac
    shift
  done

  if [[ "$all_flag" == true && -n "$since_duration" ]]; then
    printf 'ERROR: --all and --since are mutually exclusive\n' >&2; return 1
  fi
  if [[ "$all_flag" == false && -z "$since_duration" ]]; then
    printf 'ERROR: one of --all or --since <duration> is required\n' >&2; return 1
  fi
  if [[ -n "$since_duration" ]] && ! printf '%s' "$since_duration" | grep -qE '^[0-9]+[mhd]$'; then
    printf 'ERROR: --since DURATION must match ^[0-9]+[mhd]$ (e.g. 5m, 2h, 1d)\n' >&2; return 1
  fi

  # Expose taxonomy path for resolve module
  export _SAFER_TAXO_PATH="$taxonomy_path"

  # Q1 bootstrap check: fail loudly if any project is missing
  bootstrap_verify_preexisting "$taxonomy_path" || return $?

  local assigned=0 skipped=0 catchall=0 error=0

  # Enumerate GH issues
  local issues_json
  if [[ "$all_flag" == true ]]; then
    issues_json=$(gh issue list --repo chughtapan/safer-by-default \
      --state open --json number,body,labels --limit 1000)
  else
    local cutoff_date
    cutoff_date=$(date -u -d "$since_duration ago" +%Y-%m-%d 2>/dev/null \
      || date -u -v-"${since_duration%[mhd]}$(case "${since_duration: -1}" in m) echo M;; h) echo H;; d) echo d;; esac)" +%Y-%m-%d)
    issues_json=$(gh issue list --repo chughtapan/safer-by-default \
      --state open --search "updated:>=$cutoff_date" --json number,body,labels --limit 1000)
  fi

  while IFS= read -r issue_json; do
    [[ -z "$issue_json" ]] && continue

    local gh_number gh_body gh_labels
    gh_number=$(printf '%s' "$issue_json" | jq -r '.number')
    gh_body=$(printf '%s' "$issue_json" | jq -r '.body // ""')
    gh_labels=$(printf '%s' "$issue_json" | jq -r '[.labels[].name] | join("\n")')

    local project
    if ! project=$(resolve_project "$gh_number" "$gh_body" "$gh_labels"); then
      [[ "$quiet" == false ]] && printf 'ERROR #%s — project resolution failed\n' "$gh_number"
      ((++error)); continue
    fi

    if [[ -z "$project" ]]; then
      project=$(taxonomy_catchall "$taxonomy_path")
      [[ "$quiet" == false ]] && printf 'CATCHALL #%s → %s\n' "$gh_number" "$project"
      ((++catchall))
    fi

    local linear_issue
    if ! linear_issue=$(linear_find_issue_by_gh_number "$gh_number"); then
      [[ "$quiet" == false ]] && printf 'ERROR #%s — Linear API call failed\n' "$gh_number"
      ((++error)); continue
    fi

    if [[ -z "$linear_issue" ]]; then
      [[ "$quiet" == false ]] && printf 'SKIP #%s — not found in Linear\n' "$gh_number"
      ((++skipped)); continue
    fi

    local linear_id current_project
    linear_id=$(printf '%s' "$linear_issue" | jq -r '.id // ""')
    current_project=$(printf '%s' "$linear_issue" | jq -r '.project.name // ""')

    if [[ "$current_project" == "$project" ]]; then
      [[ "$quiet" == false ]] && printf 'SKIP #%s — already assigned to %s\n' "$gh_number" "$project"
      ((++skipped)); continue
    fi

    local project_id
    if ! project_id=$(linear_find_project_id "$project"); then
      [[ "$quiet" == false ]] && printf 'ERROR #%s — failed to find project id for %q\n' "$gh_number" "$project"
      ((++error)); continue
    fi

    if [[ -z "$project_id" ]]; then
      [[ "$quiet" == false ]] && printf 'ERROR #%s — project %q not found in Linear\n' "$gh_number" "$project"
      ((++error)); continue
    fi

    if [[ "$dry_run" == false ]]; then
      if linear_assign_issue_to_project "$linear_id" "$project_id"; then
        [[ "$quiet" == false ]] && printf 'ASSIGN #%s → %s\n' "$gh_number" "$project"
        ((++assigned))
      else
        [[ "$quiet" == false ]] && printf 'ERROR #%s — failed to assign to %s\n' "$gh_number" "$project"
        ((++error))
      fi
    else
      [[ "$quiet" == false ]] && printf 'DRY-RUN: would assign #%s → %s\n' "$gh_number" "$project"
      ((++assigned))
    fi
  done < <(printf '%s\n' "$issues_json" | jq -c '.[]')

  printf 'RESULT: assigned=%d skipped=%d catchall=%d error=%d\n' \
    "$assigned" "$skipped" "$catchall" "$error"
  return 0
}

# cmd_drift_report ARGV...
#   Flags: --taxonomy <path>, --format text|json
cmd_drift_report() {
  local taxonomy_path="${_SAFER_TAXO_PATH:-config/linear-taxonomy.yaml}"
  local format="text"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --taxonomy)   taxonomy_path="$2"; shift ;;
      --taxonomy=*) taxonomy_path="${1#--taxonomy=}" ;;
      --format)     format="$2"; shift ;;
      --format=*)   format="${1#--format=}" ;;
      *)            printf 'ERROR: unknown flag %q\n' "$1" >&2; return 1 ;;
    esac
    shift
  done

  drift_report "$taxonomy_path" --format="$format"
}

# cmd_bootstrap_verify ARGV...
#   Flags: --taxonomy <path>
cmd_bootstrap_verify() {
  local taxonomy_path="${_SAFER_TAXO_PATH:-config/linear-taxonomy.yaml}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --taxonomy)   taxonomy_path="$2"; shift ;;
      --taxonomy=*) taxonomy_path="${1#--taxonomy=}" ;;
      *)            printf 'ERROR: unknown flag %q\n' "$1" >&2; return 1 ;;
    esac
    shift
  done

  bootstrap_verify_preexisting "$taxonomy_path"
}
