#!/usr/bin/env bash
# lib/safer-linear/cli.sh
#
# Responsibility: subcommand dispatcher + flag parser for the
# safer-linear-setup entry point. Owns ONLY: argv parsing, subcommand
# routing, result counters, human/machine-readable exit messages. Every
# domain concern (YAML, Linear API, rules) is delegated to the dedicated
# module.
#
# In the implementation PR, `bin/safer-linear-setup` becomes a four-line
# shim: strict mode + `source lib/safer-linear/cli.sh` + `cli_main "$@"`.
# This module is not executable on its own; it is sourced.
#
# Dependencies:
#   lib/safer-linear/taxonomy.sh
#   lib/safer-linear/linear-api.sh
#   lib/safer-linear/resolve.sh
#   lib/safer-linear/drift.sh
#
# Error channel (propagates module exit codes; see module comments):
#   0   — success
#   1   — unknown subcommand / bad flags (user error; prints usage)
#   2   — drift_report detected drift (read-only signal)
#   10+ — forwarded from taxonomy.sh
#   20+ — forwarded from linear-api.sh
#   30+ — forwarded from resolve.sh
#   40+ — forwarded from drift.sh
#
# Subcommand surface (discriminated union, exhaustive):
#   subcommand ∈ { "assign-projects", "drift-report",
#                  "bootstrap-verify", "help" }
#   Any other value → usage + exit 1.
#
# Public surface:
#   cli_main <argv...>
#   cli_usage
#   cmd_assign_projects <argv...>
#   cmd_drift_report <argv...>
#   cmd_bootstrap_verify <argv...>

# cli_main ARGV...
#   Entry point. Parses the first positional arg as subcommand, routes to
#   the matching cmd_* handler. Unknown or absent subcommand prints usage
#   and exits 1. Handlers own their own flag-parsing.
#   Exit: dispatched handler's exit code, or 1 on unknown.
cli_main() {
  echo "not implemented: cli_main" >&2
  return 99
}

# cli_usage
#   Prints the full usage text (all subcommands + flags) to stdout. Used
#   both by the `help` subcommand and by every "bad invocation" path.
#   Stdout: usage text. Exit: 0.
cli_usage() {
  echo "not implemented: cli_usage" >&2
  return 99
}

# cmd_assign_projects ARGV...
#   Flags: --all | --since <duration>   (mutually exclusive, exactly one)
#          --dry-run                    (preview; no Linear mutation)
#          --quiet                      (suppress per-issue lines)
#          --taxonomy <path>            (default: config/linear-taxonomy.yaml)
#
#   Order of operations:
#     1. bootstrap_verify_preexisting (Q1: fail-loudly on first missing)
#     2. enumerate GH issues (gh issue list)
#     3. for each issue: resolve_project → maybe catchall → idempotency
#        check → linear_assign_issue_to_project (unless --dry-run)
#     4. emit RESULT line: assigned=N skipped=N catchall=N error=N
#   Stdout: per-issue lines + RESULT. Exit: 0 on any non-fatal outcome; 42
#   immediately if bootstrap fails; forwarded tag on infrastructural error.
cmd_assign_projects() {
  echo "not implemented: cmd_assign_projects" >&2
  return 99
}

# cmd_drift_report ARGV...
#   Flags: --taxonomy <path>            (default: config/linear-taxonomy.yaml)
#          --format <text|json>         (default: text)
#   Delegates to drift_report. Read-only; never mutates Linear.
#   Exit: 0 (no drift) | 2 (drift detected) | 40 | 41.
cmd_drift_report() {
  echo "not implemented: cmd_drift_report" >&2
  return 99
}

# cmd_bootstrap_verify ARGV...
#   Flags: --taxonomy <path>            (default: config/linear-taxonomy.yaml)
#   Delegates to bootstrap_verify_preexisting. Intended to be run once at
#   workspace setup, plus as the assign-projects preflight.
#   Exit: 0 | 40 | 41 | 42.
cmd_bootstrap_verify() {
  echo "not implemented: cmd_bootstrap_verify" >&2
  return 99
}
