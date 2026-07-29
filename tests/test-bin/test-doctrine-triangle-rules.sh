#!/usr/bin/env bash
# test-doctrine-triangle-rules.sh — string-match tests for the three doctrine
# rules introduced by sbd#129 (read-reviewer-body), sbd#130 (pane-monitor),
# and sbd#131 (reviewer HOLD-vs-APPROVE).
#
# These tests pin the new doctrine in skills/review-senior/SKILL.md and
# skills/verify/SKILL.md. If the key phrases drift out of the SKILL.md files,
# the rules are silently unenforceable.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

# Pinned against each skill's whole context surface, not just SKILL.md: these
# rules stop being enforceable the moment one moves into a references/ file.
REVIEW_SENIOR_MD="$(cd "$HERE/../.." && pwd)/skills/review-senior/SKILL.md"
VERIFY_MD="$(cd "$HERE/../.." && pwd)/skills/verify/SKILL.md"
rs_grep() { skill_grep review-senior "$@"; }
vf_grep() { skill_grep verify "$@"; }

# ---------------------------------------------------------------------------
# sbd#131: review-senior Forbidden verdicts section

test_review_senior_has_forbidden_verdicts_section() {
  rs_grep -qF "## Forbidden verdicts"
}

test_review_senior_forbidden_approve_with_deferred_measurement() {
  rs_grep -qF "Returning APPROVE with a deferred measurement condition the reviewer cannot confirm"
}

test_review_senior_has_hold_verdict() {
  rs_grep -qF "HOLD"
}

test_review_senior_has_hold_vs_request_changes_subsection() {
  rs_grep -qF "### HOLD vs REQUEST-CHANGES"
}

test_review_senior_completion_status_includes_hold() {
  rs_grep -qF "\`HOLD\` review posted with"
}

# sbd#131: verify "Verify is the merge gate" section

test_verify_has_merge_gate_section() {
  vf_grep -qF "## Verify is the merge gate"
}

test_verify_merge_gate_names_hold_artifact() {
  vf_grep -qF "verify's published comment is the artifact that turns HOLD"
}

test_verify_antipattern_author_claim_not_measurement() {
  vf_grep -qF "The author's PR body claims 85% mutation; that's enough"
}

# ---------------------------------------------------------------------------

echo "── doctrine-triangle-rules tests ──"

run_test "review-senior has Forbidden verdicts section"          test_review_senior_has_forbidden_verdicts_section
run_test "review-senior forbids APPROVE with deferred measure"   test_review_senior_forbidden_approve_with_deferred_measurement
run_test "review-senior SKILL.md contains HOLD verdict"         test_review_senior_has_hold_verdict
run_test "review-senior has HOLD-vs-REQUEST-CHANGES subsection" test_review_senior_has_hold_vs_request_changes_subsection
run_test "review-senior completion status includes HOLD row"     test_review_senior_completion_status_includes_hold
run_test "verify has 'Verify is the merge gate' section"        test_verify_has_merge_gate_section
run_test "verify merge gate names HOLD artifact"                test_verify_merge_gate_names_hold_artifact
run_test "verify anti-pattern: author claim not measurement"    test_verify_antipattern_author_claim_not_measurement

report
