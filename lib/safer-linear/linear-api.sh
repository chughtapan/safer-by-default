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
#   Authorization: $LINEAR_API_KEY        (raw, no "Bearer " prefix)
# The test suite asserts the literal substring "Bearer " never appears in
# any outbound Authorization header produced by this module (see tests/
# test-linear-v2/test-auth-header.sh acceptance reference).
#
# Public surface:
#   linear_graphql <query>
#   linear_list_projects
#   linear_find_issue_by_gh_number <gh-number>
#   linear_find_project_id <project-name>
#   linear_assign_issue_to_project <linear-issue-id> <linear-project-id>
#   linear_get_parent_project <linear-issue-id>

# linear_graphql QUERY_OR_MUTATION
#   Raw GraphQL transport. Every other function in this module routes here.
#   Implements the Authorization header shape invariant. This is the only
#   place any caller in the repo may compose an Authorization header for
#   Linear.
#   Stdout: raw JSON response body. Exit: 0 | 20 | 21 | 22 | 23.
linear_graphql() {
  echo "not implemented: linear_graphql" >&2
  return 99
}

# linear_list_projects
#   Returns the full set of projects visible to LINEAR_API_KEY in the MOL
#   team. Used by drift + bootstrap preflight.
#   Stdout: JSON array of `{ id, name }`. Exit: 0 | 20 | 21 | 22 | 23.
linear_list_projects() {
  echo "not implemented: linear_list_projects" >&2
  return 99
}

# linear_find_issue_by_gh_number GH_NUMBER
#   Resolves a GitHub issue number to the Linear issue whose attachments
#   include the canonical GH issue URL. Matches by URL (not title/body) to
#   avoid false matches from cross-references in body text.
#   Stdout: JSON `{ id, project: { id, name } | null }`, or empty if no
#   Linear issue attached to that URL. Exit: 0 | 20 | 21 | 22 | 23.
linear_find_issue_by_gh_number() {
  echo "not implemented: linear_find_issue_by_gh_number" >&2
  return 99
}

# linear_find_project_id PROJECT_NAME
#   Exact-name lookup against Linear's projects. Case-sensitive.
#   Stdout: project id, or empty if not found. Exit: 0 | 20 | 21 | 22 | 23.
linear_find_project_id() {
  echo "not implemented: linear_find_project_id" >&2
  return 99
}

# linear_assign_issue_to_project LINEAR_ISSUE_ID LINEAR_PROJECT_ID
#   Single issueUpdate mutation. Idempotency is the caller's responsibility
#   (caller SHOULD short-circuit when the current project already matches).
#   Stdout: empty on success. Exit: 0 | 20 | 21 | 22 | 23.
linear_assign_issue_to_project() {
  echo "not implemented: linear_assign_issue_to_project" >&2
  return 99
}

# linear_get_parent_project GH_PARENT_NUMBER
#   Convenience: single-hop lookup of the parent's Linear project name.
#   Returns empty stdout if the parent is not attached to Linear OR is
#   attached but has no project assigned (rule-2/3 fallthrough signal).
#   The resolver treats empty as "rule did not match" — see resolve.sh.
#   Stdout: project name, or empty. Exit: 0 | 20 | 21 | 22 | 23.
linear_get_parent_project() {
  echo "not implemented: linear_get_parent_project" >&2
  return 99
}
