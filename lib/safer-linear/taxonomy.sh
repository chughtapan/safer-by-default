#!/usr/bin/env bash
# lib/safer-linear/taxonomy.sh
#
# Responsibility: load, validate, and query the in-repo Linear taxonomy.
# Sole owner of parsing config/linear-taxonomy.yaml. Every other module that
# needs a project name, the label map, or the catchall asks this module.
#
# Dependencies: yq (>=4.0), bash (>=4.0).
# Error channel: every public function returns one of:
#   0  — success; result on stdout (or populates named nameref var)
#   10 — TAXONOMY_NOT_FOUND  (file missing / unreadable)
#   11 — TAXONOMY_PARSE_ERROR (yq fails / not YAML)
#   12 — TAXONOMY_SCHEMA_ERROR (shape invalid: missing key, wrong type,
#         labelMap.project not in projects, catchall not in projects)
# Error detail is written to stderr as: `TAXONOMY_<TAG>: <human line>`.
#
# Public surface (exported for callers that `source` this file):
#   load_taxonomy <path>
#   validate_taxonomy <path>
#   taxonomy_projects <path>           # one project name per line on stdout
#   taxonomy_catchall <path>           # catchall name on stdout
#   taxonomy_label_map <path>          # "<label>\t<project>" per line, in order
#   taxonomy_contains_project <path> <name>   # exit 0 if listed, else 1

# load_taxonomy PATH
#   Validates + caches (in-process) the parsed taxonomy. Subsequent query
#   functions are permitted to trust the cache only within the same process
#   invocation. Caching strategy is implementation-detail; the interface is
#   "call load_taxonomy first, then query."
#   Stdout: empty. Exit: 0 | 10 | 11 | 12.
load_taxonomy() {
  echo "not implemented: load_taxonomy" >&2
  return 99
}

# validate_taxonomy PATH
#   Runs load_taxonomy and additionally asserts every cross-reference:
#     - schemaVersion equals 1
#     - catchall ∈ projects
#     - every labelMap[*].project ∈ projects
#     - projects has no duplicates
#     - labelMap labels have no duplicates
#   Used by drift/bootstrap before any Linear API call.
#   Stdout: empty. Exit: 0 | 10 | 11 | 12.
validate_taxonomy() {
  echo "not implemented: validate_taxonomy" >&2
  return 99
}

# taxonomy_projects PATH
#   Prints every project name from `projects`, one per line, preserving file
#   order. Caller may pipe to `sort -u` if needed. No duplicates by contract
#   (validate_taxonomy enforces).
#   Stdout: project names. Exit: 0 | 10 | 11 | 12.
taxonomy_projects() {
  echo "not implemented: taxonomy_projects" >&2
  return 99
}

# taxonomy_catchall PATH
#   Prints the catchall project name. Exactly one name. Guaranteed to appear
#   in taxonomy_projects by contract.
#   Stdout: one name. Exit: 0 | 10 | 11 | 12.
taxonomy_catchall() {
  echo "not implemented: taxonomy_catchall" >&2
  return 99
}

# taxonomy_label_map PATH
#   Prints "<label>\t<project>" per line, in file order. Order is significant
#   (first-match-wins in rule 4). Returns empty output (exit 0) if labelMap
#   is empty.
#   Stdout: tab-delimited rows. Exit: 0 | 10 | 11 | 12.
taxonomy_label_map() {
  echo "not implemented: taxonomy_label_map" >&2
  return 99
}

# taxonomy_contains_project PATH NAME
#   Checks membership of NAME in `projects`.
#   Stdout: empty. Exit: 0 (yes) | 1 (no) | 10 | 11 | 12.
taxonomy_contains_project() {
  echo "not implemented: taxonomy_contains_project" >&2
  return 99
}
