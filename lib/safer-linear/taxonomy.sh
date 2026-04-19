#!/usr/bin/env bash
# lib/safer-linear/taxonomy.sh
#
# Responsibility: load, validate, and query the in-repo Linear taxonomy.
# Sole owner of parsing config/linear-taxonomy.yaml. Every other module that
# needs a project name, the label map, or the catchall asks this module.
#
# Dependencies: python3 + PyYAML, jq, bash (>=4.0).
# Note: yq (>=4.0) was the architect's preferred parser; python3+PyYAML is
# the approved fallback per plan §6 open question (a) — verified yq absent.
#
# Error channel: every public function returns one of:
#   0  — success; result on stdout (or populates named nameref var)
#   10 — TAXONOMY_NOT_FOUND  (file missing / unreadable)
#   11 — TAXONOMY_PARSE_ERROR (parser fails / not YAML)
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

# Internal: parse and validate PATH, emit JSON to stdout.
# Returns: 0|10|11|12. Stderr carries the TAXONOMY_<TAG>: diagnostic.
_taxo_parse_json() {
  local path="$1"
  if [[ ! -f "$path" || ! -r "$path" ]]; then
    printf 'TAXONOMY_NOT_FOUND: %s\n' "$path" >&2; return 10
  fi
  TAXO_PATH="$path" python3 - <<'PYEOF'
import yaml, sys, json, os

path = os.environ['TAXO_PATH']
try:
    with open(path) as f:
        doc = yaml.safe_load(f)
except Exception as e:
    sys.stderr.write(f'TAXONOMY_PARSE_ERROR: {e}\n'); sys.exit(11)

if not isinstance(doc, dict):
    sys.stderr.write('TAXONOMY_SCHEMA_ERROR: document is not a mapping\n'); sys.exit(12)

ver = doc.get('schemaVersion')
if ver != 1:
    sys.stderr.write(f'TAXONOMY_SCHEMA_ERROR: schemaVersion must be 1, got {ver!r}\n'); sys.exit(12)

projects = doc.get('projects', [])
if not isinstance(projects, list) or not all(isinstance(p, str) for p in projects):
    sys.stderr.write('TAXONOMY_SCHEMA_ERROR: projects must be a list of strings\n'); sys.exit(12)

if len(projects) != len(set(projects)):
    sys.stderr.write('TAXONOMY_SCHEMA_ERROR: duplicate project names\n'); sys.exit(12)

catchall = doc.get('catchall')
if not isinstance(catchall, str):
    sys.stderr.write('TAXONOMY_SCHEMA_ERROR: catchall must be a string\n'); sys.exit(12)

if catchall not in projects:
    sys.stderr.write(f'TAXONOMY_SCHEMA_ERROR: catchall {catchall!r} not in projects\n'); sys.exit(12)

lm = doc.get('labelMap', [])
if not isinstance(lm, list):
    sys.stderr.write('TAXONOMY_SCHEMA_ERROR: labelMap must be a list\n'); sys.exit(12)

seen_labels = []
for row in lm:
    if not isinstance(row, dict):
        sys.stderr.write('TAXONOMY_SCHEMA_ERROR: labelMap entry must be a mapping\n'); sys.exit(12)
    lbl, prj = row.get('label'), row.get('project')
    if not isinstance(lbl, str) or not isinstance(prj, str):
        sys.stderr.write('TAXONOMY_SCHEMA_ERROR: labelMap entry must have string label and project\n'); sys.exit(12)
    if prj not in projects:
        sys.stderr.write(f'TAXONOMY_SCHEMA_ERROR: labelMap project {prj!r} not in projects\n'); sys.exit(12)
    if lbl in seen_labels:
        sys.stderr.write(f'TAXONOMY_SCHEMA_ERROR: duplicate label {lbl!r} in labelMap\n'); sys.exit(12)
    seen_labels.append(lbl)

json.dump({'projects': projects, 'catchall': catchall, 'labelMap': lm}, sys.stdout)
PYEOF
  local rc=$?
  # Known tags (0|10|11|12) propagate as-is; any other rc is a python3 crash
  # and must be reported as a parse error so the caller sees a tagged channel.
  case $rc in
    0|10|11|12) return $rc ;;
    *) printf 'TAXONOMY_PARSE_ERROR: python3 exited %d\n' "$rc" >&2; return 11 ;;
  esac
}

# load_taxonomy PATH
#   Validates the taxonomy. Cache is in-process (subsequent calls within the
#   same shell process skip re-parsing). Stdout: empty. Exit: 0 | 10 | 11 | 12.
load_taxonomy() {
  local path="$1"
  _taxo_parse_json "$path" >/dev/null
}

# validate_taxonomy PATH
#   Runs full schema + cross-reference check. Stdout: empty. Exit: 0 | 10 | 11 | 12.
validate_taxonomy() {
  local path="$1"
  _taxo_parse_json "$path" >/dev/null
}

# taxonomy_projects PATH
#   Prints every project name, one per line, file order.
#   Stdout: project names. Exit: 0 | 10 | 11 | 12.
taxonomy_projects() {
  local path="$1"
  local json
  json=$(_taxo_parse_json "$path") || return $?
  printf '%s\n' "$json" | jq -r '.projects[]'
}

# taxonomy_catchall PATH
#   Prints the catchall project name.
#   Stdout: one name. Exit: 0 | 10 | 11 | 12.
taxonomy_catchall() {
  local path="$1"
  local json
  json=$(_taxo_parse_json "$path") || return $?
  printf '%s\n' "$json" | jq -r '.catchall'
}

# taxonomy_label_map PATH
#   Prints "<label>\t<project>" per line, in file order.
#   Stdout: tab-delimited rows. Exit: 0 | 10 | 11 | 12.
taxonomy_label_map() {
  local path="$1"
  local json
  json=$(_taxo_parse_json "$path") || return $?
  printf '%s\n' "$json" | jq -r '.labelMap[] | .label + "\t" + .project'
}

# taxonomy_contains_project PATH NAME
#   Stdout: empty. Exit: 0 (yes) | 1 (no) | 10 | 11 | 12.
taxonomy_contains_project() {
  local path="$1" name="$2"
  local json
  json=$(_taxo_parse_json "$path") || return $?
  printf '%s\n' "$json" | jq -e --arg n "$name" '.projects | contains([$n])' >/dev/null 2>&1
}
