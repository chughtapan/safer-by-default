#!/usr/bin/env bash
# test-orchestrate-auto-dispatch.sh — unit tests for the parsing logic
# Phase 5d Step 6 (auto-dispatch work-queue scan) depends on.
#
# Step 6 lives inline in skills/orchestrate/SKILL.md as executable snippets
# (no dedicated binary). Rather than mocking `gh` and `tmux` for an
# integration-shaped test, this suite exercises the three parse rules that
# the inline snippets rely on:
#
#   1. The label regex that selects dispatchable sub-issues.
#   2. The idempotency marker comment format + extraction.
#   3. The priority-tier sort defined in Step 6c.
#
# If any of these rules drift out of sync with SKILL.md, the loop either
# re-dispatches already-in-flight work (breaks idempotency) or dispatches
# the wrong modality (breaks the Ratchet). These tests pin the rules.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../test-helpers.sh"

SKILL_MD="$(cd "$HERE/../.." && pwd)/skills/orchestrate/SKILL.md"

# The label regex from SKILL.md Step 6a.
MODALITY_REGEX='^safer:(implement-(junior|senior|staff)|verify|spike|research|contract)$'

# The idempotency marker format from SKILL.md Step 6e.
MARKER_REGEX='^<!-- orchestrate:dispatched teammate=[A-Za-z0-9_-]+ at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z -->$'

# The deferral marker format from SKILL.md Step 6a deferral-marker subsection.
# until field must be either ISO8601 (YYYY-MM-DDTHH:MM:SSZ) or condition:*
DEFERRAL_MARKER_REGEX='<!-- safer:deferred reason="(([^"\\]|\\.)*)" until="(([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z)|(condition:[^"]+))" added-by="([^"]+)" at="([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z)" -->'

# ---------------------------------------------------------------------------

test_regex_matches_all_seven_modalities() {
  local labels=(
    "safer:implement-junior"
    "safer:implement-senior"
    "safer:implement-staff"
    "safer:verify"
    "safer:spike"
    "safer:research"
    "safer:contract"
  )
  for l in "${labels[@]}"; do
    echo "$l" | grep -qE "$MODALITY_REGEX" || { echo "regex missed: $l"; return 1; }
  done
  return 0
}

test_regex_rejects_non_dispatchable_labels() {
  # review-senior is NOT dispatchable from the scan; it runs as a review pass,
  # not as a standalone teammate. Same for orchestrate, architect-junior, etc.
  local rejects=(
    "safer:review-senior"
    "safer:orchestrate"
    "safer:implement"
    "safer:architect-junior"
    "planning"
    "review"
    "plan-approved"
    ""
  )
  for l in "${rejects[@]}"; do
    if echo "$l" | grep -qE "$MODALITY_REGEX"; then
      echo "regex wrongly accepted: $l"; return 1
    fi
  done
  return 0
}

test_skill_md_step6a_jq_uses_same_regex() {
  # The regex string in SKILL.md Step 6a must match the MODALITY_REGEX constant
  # above verbatim. If it drifts, the loop filters a different label set than
  # this test pins.
  grep -qF "$MODALITY_REGEX" "$SKILL_MD"
}

test_idempotency_marker_matches_canonical_format() {
  local good=(
    "<!-- orchestrate:dispatched teammate=impl-senior-66 at=2026-04-18T23:45:00Z -->"
    "<!-- orchestrate:dispatched teammate=verify-42 at=2026-01-01T00:00:00Z -->"
    "<!-- orchestrate:dispatched teammate=a at=2000-12-31T23:59:59Z -->"
  )
  for c in "${good[@]}"; do
    echo "$c" | grep -qE "$MARKER_REGEX" || { echo "missed: $c"; return 1; }
  done
  return 0
}

test_idempotency_marker_rejects_malformed() {
  local bad=(
    "<!-- orchestrate:dispatched teammate=x at=2026-04-18 -->"      # no time
    "<!-- dispatched teammate=x at=2026-04-18T00:00:00Z -->"        # wrong prefix
    "orchestrate:dispatched teammate=x at=2026-04-18T00:00:00Z"     # not a comment
    "<!-- orchestrate:dispatched teammate= at=2026-04-18T00:00:00Z -->"  # empty name
    "<!-- orchestrate:dispatched teammate=x at=yesterday -->"
  )
  for c in "${bad[@]}"; do
    if echo "$c" | grep -qE "$MARKER_REGEX"; then
      echo "wrongly accepted: $c"; return 1
    fi
  done
  return 0
}

test_idempotency_marker_extracts_teammate_and_timestamp() {
  local c="<!-- orchestrate:dispatched teammate=impl-senior-66 at=2026-04-18T23:45:00Z -->"
  local name ts
  name=$(echo "$c" | sed -n 's/.*teammate=\([A-Za-z0-9_-]\+\).*/\1/p')
  ts=$(echo "$c" | sed -n 's/.*at=\([0-9T:Z-]\+\).*/\1/p')
  assert_equal "$name" "impl-senior-66" "extract name" && \
    assert_equal "$ts" "2026-04-18T23:45:00Z" "extract ts"
}

test_deferral_marker_matches_canonical_format() {
  local good=(
    "<!-- safer:deferred reason=\"awaiting user confirmation\" until=\"2026-04-20T00:00:00Z\" added-by=\"team-lead\" at=\"2026-04-19T15:30:00Z\" -->"
    "<!-- safer:deferred reason=\"upstream PR merge\" until=\"condition:chughtapan/cc-judge#14\" added-by=\"orchestrate\" at=\"2026-04-18T12:00:00Z\" -->"
    "<!-- safer:deferred reason=\"\" until=\"2026-12-31T23:59:59Z\" added-by=\"a\" at=\"2000-01-01T00:00:00Z\" -->"
  )
  for c in "${good[@]}"; do
    echo "$c" | grep -qE "$DEFERRAL_MARKER_REGEX" || { echo "missed: $c"; return 1; }
  done
  return 0
}

test_deferral_marker_rejects_malformed() {
  local bad=(
    "<!-- safer:deferred reason=\"test\" until=\"2026-04-20\" added-by=\"x\" at=\"2026-04-19T15:30:00Z\" -->"  # no time in until
    "<!-- safer:deferred reason=test until=\"2026-04-20T00:00:00Z\" added-by=\"x\" at=\"2026-04-19T15:30:00Z\" -->"  # unquoted reason
    "<!-- safer:deferred reason=\"test\" until=2026-04-20T00:00:00Z added-by=\"x\" at=\"2026-04-19T15:30:00Z\" -->"  # unquoted until
    "safer:deferred reason=\"test\" until=\"2026-04-20T00:00:00Z\" added-by=\"x\" at=\"2026-04-19T15:30:00Z\""  # not a comment
    "<!-- safer:deferred reason=\"test\" until=\"2026-04-20T00:00:00Z\" added-by= at=\"2026-04-19T15:30:00Z\" -->"  # empty added-by
  )
  for c in "${bad[@]}"; do
    if echo "$c" | grep -qE "$DEFERRAL_MARKER_REGEX"; then
      echo "wrongly accepted: $c"; return 1
    fi
  done
  return 0
}

test_deferral_marker_extracts_until_field() {
  local c="<!-- safer:deferred reason=\"test\" until=\"2026-04-20T15:45:00Z\" added-by=\"team\" at=\"2026-04-19T12:00:00Z\" -->"
  local until
  until=$(echo "$c" | sed -n 's/.*until="\([^"]*\)".*/\1/p')
  assert_equal "$until" "2026-04-20T15:45:00Z" "extract until ISO8601"
}

test_deferral_filter_skips_condition_indefinitely() {
  local c="<!-- safer:deferred reason=\"upstream merge\" until=\"condition:chughtapan/cc-judge#14\" added-by=\"lead\" at=\"2026-04-19T12:00:00Z\" -->"
  local until
  until=$(echo "$c" | sed -n 's/.*until="\([^"]*\)".*/\1/p')
  case "$until" in
    condition:*) return 0 ;; # correct: condition: prefix means skip
    *) echo "condition: check failed"; return 1 ;;
  esac
}

test_deferral_filter_compares_iso8601_timestamps() {
  # Simulate the filter logic: if marker.until > now, skip; else proceed.
  local past="2026-04-18T00:00:00Z"
  local future="2026-04-21T00:00:00Z"
  local now="2026-04-19T12:00:00Z"

  # Past: marker < now, so the deferral has expired; do NOT skip (proceed with dispatch)
  if [ "$past" \> "$now" ]; then
    echo "past check failed"; return 1
  fi

  # Future: marker > now, so the deferral is still active; skip
  if ! [ "$future" \> "$now" ]; then
    echo "future check failed"; return 1
  fi
  return 0
}

# Priority-tier sort reference implementation from Step 6c:
#   1 = blocker-level (review-labeled on critical path)
#   2 = spike or verify
#   3 = implement-*
#   4 = research
# Input lines: "<tier>\t<created_at_epoch>\t<issue_number>"
# Output: sorted ascending by (tier, created_at), one issue per line.
priority_sort() {
  sort -k1,1n -k2,2n | cut -f3
}

test_priority_sort_orders_by_tier() {
  local input
  input=$(printf '%s\n' \
    $'3\t1000\t30' \
    $'4\t900\t40' \
    $'2\t1100\t20' \
    $'1\t1200\t10')
  local got
  got=$(echo "$input" | priority_sort | tr '\n' ' ' | sed 's/ $//')
  assert_equal "$got" "10 20 30 40" "tier-major order"
}

test_priority_sort_breaks_ties_by_age() {
  # Same tier, oldest (smallest epoch) wins.
  local input
  input=$(printf '%s\n' \
    $'3\t2000\t301' \
    $'3\t1000\t302' \
    $'3\t1500\t303')
  local got
  got=$(echo "$input" | priority_sort | tr '\n' ' ' | sed 's/ $//')
  assert_equal "$got" "302 303 301" "tie-break on oldest"
}

# Per-tick cap from Step 6d: hard-cap of 3 new dispatches per tick, even
# when pane budget is larger.
apply_per_tick_cap() {
  # Inputs: $1 = spare, $2 = per_tick_cap. Outputs: dispatch budget.
  local spare="$1" cap="$2"
  if [ "$spare" -lt "$cap" ]; then echo "$spare"; else echo "$cap"; fi
}

test_per_tick_cap_limits_dispatch() {
  assert_equal "$(apply_per_tick_cap 10 3)" "3" "cap wins when spare is large" && \
    assert_equal "$(apply_per_tick_cap 2 3)"  "2" "spare wins when tighter" && \
    assert_equal "$(apply_per_tick_cap 0 3)"  "0" "no-capacity skip"
}

test_skill_md_pins_per_tick_cap_to_three() {
  # If the documented cap changes, the loop test above is lying. Pin it.
  grep -qF "per_tick_cap=3" "$SKILL_MD"
}

test_skill_md_pins_pane_ceiling_to_twenty() {
  grep -qF "pane_ceiling=20" "$SKILL_MD"
}

test_skill_md_has_all_seven_templates() {
  # One section per dispatchable modality.
  for modality in implement-junior implement-senior implement-staff verify spike research contract; do
    grep -qE "^#### ${modality}$" "$SKILL_MD" || { echo "missing template: $modality"; return 1; }
  done
  return 0
}

test_epic_body_template_includes_linear_project_line() {
  # Phase 3 epic body template must include the Linear project context line
  # for Linear sync integration. Extract the template from SKILL.md and verify
  # the expected line is present.
  sed -n '/^Epic body template:/,/^```$/p' "$SKILL_MD" | \
    grep -q 'Linear project:' || {
      echo "Linear project line missing from epic body template";
      return 1;
    }
}

# sbd#129: Step 5c.0 read-reviewer-body gate must be present.
test_skill_md_has_step_5c0_read_reviewer_body() {
  grep -qF "Step 5c.0 — Read reviewer body before merging" "$SKILL_MD"
}

test_skill_md_step5c0_has_gh_pr_view_command() {
  grep -qF 'gh pr view <N> --repo <R> --json reviews --jq' "$SKILL_MD"
}

# sbd#130: Phase 5e pane stall check must be present.
test_skill_md_has_pane_stall_check() {
  grep -qF "Waiting for team lead approval" "$SKILL_MD"
}

test_skill_md_has_phase_5e_protocol() {
  grep -qF "Phase 5e — permission_request response protocol" "$SKILL_MD"
}

# sbd#129+130: forbidden list entries must be present.
test_skill_md_forbidden_read_reviewer_body() {
  grep -qF "without reading the reviewer body on GitHub via the Step 5c.0 procedure" "$SKILL_MD"
}

test_skill_md_forbidden_permission_request_stall() {
  grep -qF "Letting a teammate \`permission_request\` sit unanswered past one sweep tick" "$SKILL_MD"
}

# ---------------------------------------------------------------------------

echo "── orchestrate-auto-dispatch unit tests ──"

run_test "modality regex matches all 7 dispatchable modalities" test_regex_matches_all_seven_modalities
run_test "modality regex rejects non-dispatchable labels"       test_regex_rejects_non_dispatchable_labels
run_test "SKILL.md Step 6a uses the pinned regex verbatim"      test_skill_md_step6a_jq_uses_same_regex
run_test "idempotency marker matches canonical format"          test_idempotency_marker_matches_canonical_format
run_test "idempotency marker rejects malformed strings"         test_idempotency_marker_rejects_malformed
run_test "idempotency marker extracts teammate + timestamp"     test_idempotency_marker_extracts_teammate_and_timestamp
run_test "deferral marker matches canonical format"             test_deferral_marker_matches_canonical_format
run_test "deferral marker rejects malformed strings"            test_deferral_marker_rejects_malformed
run_test "deferral marker extracts until field"                 test_deferral_marker_extracts_until_field
run_test "deferral filter skips condition indefinitely"         test_deferral_filter_skips_condition_indefinitely
run_test "deferral filter compares ISO8601 timestamps"          test_deferral_filter_compares_iso8601_timestamps
run_test "priority sort orders by tier then age"                test_priority_sort_orders_by_tier
run_test "priority sort breaks ties by oldest created_at"       test_priority_sort_breaks_ties_by_age
run_test "per-tick cap limits dispatch to 3"                    test_per_tick_cap_limits_dispatch
run_test "SKILL.md pins per_tick_cap=3"                         test_skill_md_pins_per_tick_cap_to_three
run_test "SKILL.md pins pane_ceiling=20"                        test_skill_md_pins_pane_ceiling_to_twenty
run_test "SKILL.md has one template per dispatchable modality"  test_skill_md_has_all_seven_templates
run_test "epic body template includes Linear project line"      test_epic_body_template_includes_linear_project_line
run_test "SKILL.md has Step 5c.0 read-reviewer-body gate"      test_skill_md_has_step_5c0_read_reviewer_body
run_test "SKILL.md Step 5c.0 has gh pr view command"           test_skill_md_step5c0_has_gh_pr_view_command
run_test "SKILL.md has pane stall check string"                test_skill_md_has_pane_stall_check
run_test "SKILL.md has Phase 5e protocol subsection"           test_skill_md_has_phase_5e_protocol
run_test "SKILL.md forbidden: read reviewer body"              test_skill_md_forbidden_read_reviewer_body
run_test "SKILL.md forbidden: permission_request stall"        test_skill_md_forbidden_permission_request_stall

report
