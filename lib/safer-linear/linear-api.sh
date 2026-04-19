#!/usr/bin/env bash
# lib/safer-linear/linear-api.sh
#
# Responsibility: only module that issues HTTP requests to Linear's GraphQL
# endpoint. Owns the auth-header shape (invariant 5, issue #112) and is the
# one place where that shape is enforced. Any other module that needs Linear
# data goes through this module.
#
# Dependencies: curl, jq (>=1.6), bash (>=4.0). LINEAR_API_KEY in env.
# Error channel: every public function returns one of:
#   0  — success; payload on stdout (JSON unless noted)
#   20 — LINEAR_AUTH_MISSING     (LINEAR_API_KEY unset or empty)
#   21 — LINEAR_NETWORK_ERROR    (curl failed / non-2xx / empty response)
#   22 — LINEAR_API_ERROR        (`.errors` present in response body)
#   23 — LINEAR_AUTH_REJECTED    (401/403 from Linear; cite #112 context)
#   24 — LINEAR_NOT_FOUND        (entity filter returned zero nodes where
#        one was expected; not used when empty is a legal answer)
# Error detail (stderr): `LINEAR_<TAG>: <short cause>` plus, when applicable,
# the sanitized request hash (no API key in logs).
#
# Auth shape (iron rule, invariant 5):
#   Authorization: $LINEAR_API_KEY        (raw API key, no auth-scheme prefix)
# The test suite asserts the literal substring "Bearer " never appears in
# any outbound Authorization header produced by this module (see tests/
# test-linear-v2/test-linear-auth-header-shape.sh).
#
# Public surface:
#   linear_graphql <query>
#   linear_list_projects
#   linear_find_issue_by_gh_number <gh-number>
#   linear_find_project_id <project-name>
#   linear_assign_issue_to_project <linear-issue-id> <linear-project-id>
#   linear_get_parent_project <gh-parent-number>

_LINEAR_ENDPOINT="https://api.linear.app/graphql"

# linear_graphql QUERY_OR_MUTATION
#   Raw GraphQL transport. Every other function in this module routes here.
#   Implements the Authorization header shape invariant. This is the only
#   place any caller in the repo may compose an Authorization header for
#   Linear.
#   Stdout: raw JSON response body. Exit: 0 | 20 | 21 | 22 | 23.
linear_graphql() {
  local query="$1"

  if [[ -z "${LINEAR_API_KEY:-}" ]]; then
    printf 'LINEAR_AUTH_MISSING: LINEAR_API_KEY not set\n' >&2; return 20
  fi

  local tmpbody
  tmpbody=$(mktemp)

  local http_code
  http_code=$(curl -s -X POST "$_LINEAR_ENDPOINT" \
    -H "Content-Type: application/json" \
    -H "Authorization: $LINEAR_API_KEY" \
    -d "$(printf '%s' "$query" | jq -Rs '{query: .}')" \
    -o "$tmpbody" \
    -w '%{http_code}' 2>/dev/null)
  local curl_rc=$?

  local body
  body=$(cat "$tmpbody"); rm -f "$tmpbody"

  if [[ $curl_rc -ne 0 ]]; then
    printf 'LINEAR_NETWORK_ERROR: curl failed (exit %d)\n' "$curl_rc" >&2; return 21
  fi

  if [[ "$http_code" == 401 || "$http_code" == 403 ]]; then
    printf 'LINEAR_AUTH_REJECTED: HTTP %s — check LINEAR_API_KEY shape (#112)\n' "$http_code" >&2; return 23
  fi

  if [[ "$http_code" != 200 ]]; then
    printf 'LINEAR_NETWORK_ERROR: HTTP %s\n' "$http_code" >&2; return 21
  fi

  if [[ -z "$body" ]]; then
    printf 'LINEAR_NETWORK_ERROR: empty response body\n' >&2; return 21
  fi

  if printf '%s' "$body" | jq -e '.errors | length > 0' >/dev/null 2>&1; then
    local errmsg
    errmsg=$(printf '%s' "$body" | jq -r '.errors[0].message // "unknown error"')
    printf 'LINEAR_API_ERROR: %s\n' "$errmsg" >&2; return 22
  fi

  printf '%s\n' "$body"
}

# linear_list_projects
#   Returns the full set of projects visible to LINEAR_API_KEY.
#   Used by drift + bootstrap preflight.
#   Stdout: JSON array of `{ id, name }`. Exit: 0 | 20 | 21 | 22 | 23.
linear_list_projects() {
  local resp
  resp=$(linear_graphql 'query { projects(first: 250) { nodes { id name } } }') || return $?
  printf '%s\n' "$resp" | jq '.data.projects.nodes'
}

# linear_find_issue_by_gh_number GH_NUMBER
#   Resolves a GitHub issue number to the Linear issue whose attachments
#   include the canonical GH issue URL. Matches by URL to avoid false
#   matches from cross-references in body text.
#   Stdout: JSON `{ id, project: { id, name } | null }`, or empty if not found.
#   Exit: 0 | 20 | 21 | 22 | 23.
linear_find_issue_by_gh_number() {
  local gh_number="$1"
  local gh_url="https://github.com/chughtapan/safer-by-default/issues/$gh_number"
  local query="query { issues(filter: { attachments: { url: { eq: \"$gh_url\" } } }) { nodes { id project { id name } } } }"
  local resp
  resp=$(linear_graphql "$query") || return $?
  printf '%s\n' "$resp" | jq '.data.issues.nodes[0] // empty'
}

# linear_find_project_id PROJECT_NAME
#   Exact-name lookup against Linear's projects. Case-sensitive.
#   Stdout: project id, or empty if not found. Exit: 0 | 20 | 21 | 22 | 23.
linear_find_project_id() {
  local project_name="$1"
  local query="query { projects(filter: { name: { eq: \"$project_name\" } }) { nodes { id } } }"
  local resp
  resp=$(linear_graphql "$query") || return $?
  printf '%s\n' "$resp" | jq -r '.data.projects.nodes[0].id // ""'
}

# linear_assign_issue_to_project LINEAR_ISSUE_ID LINEAR_PROJECT_ID
#   Single issueUpdate mutation. Idempotency is the caller's responsibility.
#   Stdout: empty on success. Exit: 0 | 20 | 21 | 22 | 23.
linear_assign_issue_to_project() {
  local issue_id="$1" project_id="$2"
  local query="mutation { issueUpdate(id: \"$issue_id\", input: { projectId: \"$project_id\" }) { issue { id } } }"
  linear_graphql "$query" >/dev/null
}

# linear_get_parent_project GH_PARENT_NUMBER
#   Convenience: single-hop lookup of the parent's Linear project name.
#   Returns empty stdout if the parent is not attached to Linear OR is
#   attached but has no project assigned (rule-2/3 fallthrough signal).
#   The resolver treats empty as "rule did not match" — see resolve.sh.
#   Stdout: project name, or empty. Exit: 0 | 20 | 21 | 22 | 23.
linear_get_parent_project() {
  local gh_parent_number="$1"
  local issue
  issue=$(linear_find_issue_by_gh_number "$gh_parent_number") || return $?
  # Empty issue (parent not attached to Linear) is a valid "no project" answer.
  [[ -z "$issue" ]] && return 0
  printf '%s\n' "$issue" | jq -r '.project.name // ""'
}
