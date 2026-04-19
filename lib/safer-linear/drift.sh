#!/usr/bin/env bash
# lib/safer-linear/drift.sh
#
# Responsibility: compare the in-repo taxonomy against Linear's live project
# set. Two public entry points share that plumbing:
#
#   drift_report         — read-only; prints both deltas to stdout or JSON.
#                          Exit 0 if no drift, 2 if any drift detected.
#                          Required by spec acceptance criterion "drift
#                          surfacing". CI/cron wiring is deferred — this
#                          module only makes the delta observable.
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
#   42 — BOOTSTRAP_MISSING_PROJECT (spec: fail-loudly Q1; message names the
#        first missing project and points at the bootstrap procedure)
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

# drift_report TAXONOMY_PATH [--format=text|json]
#   Read-only comparison. Order of operations:
#     1. validate_taxonomy TAXONOMY_PATH
#     2. linear_list_projects
#     3. compute bidirectional set difference
#     4. emit formatted output
#   Stdout: formatted delta (text or json). Exit: 0 (no drift) | 2 (drift) | 40 | 41.
drift_report() {
  echo "not implemented: drift_report" >&2
  return 99
}

# bootstrap_verify_preexisting TAXONOMY_PATH
#   Q1 behavior: require-preexisting. Succeeds iff every project named in
#   the taxonomy exists in Linear. On first missing project, prints the
#   error line required by spec acceptance "missing-project is loud" and
#   exits 42.
#   Stdout: empty on success. Exit: 0 | 40 | 41 | 42.
bootstrap_verify_preexisting() {
  echo "not implemented: bootstrap_verify_preexisting" >&2
  return 99
}
