// Stamina Phase-4 consensus reducer — the deterministic aggregate over per-reviewer verdicts.
//
// This is the canonical encoding of the consensus table in skills/stamina/SKILL.md Phase 4.
// dispatch.workflow.js inlines a mirror of `consensus()` (Workflow scripts cannot import local
// files). This module + its --selftest are the source of truth; keep the mirror in sync.
//
// The reducer is pure: it reads ONLY the collected per-reviewer status tags and never the
// artifact. That is the Iron Rule made structural — stamina routes, it does not review.
//
// Status vocabulary (per reviewer, already normalized from GitHub native states upstream):
//   DONE | DONE_WITH_CONCERNS | ESCALATED | BLOCKED | NEEDS_CONTEXT
// (GitHub CHANGES_REQUESTED maps to ESCALATED before it reaches here.)

/** @typedef {"DONE"|"DONE_WITH_CONCERNS"|"ESCALATED"|"BLOCKED"|"NEEDS_CONTEXT"} ReviewerStatus */
/** @typedef {"DONE"|"DONE_WITH_CONCERNS"|"ESCALATED"|"BLOCKED"|"NEEDS_CONTEXT"|"WIDEN_RETRY"} Aggregate */

const REVIEWER_STATUSES = new Set([
  "DONE",
  "DONE_WITH_CONCERNS",
  "ESCALATED",
  "BLOCKED",
  "NEEDS_CONTEXT",
]);

/**
 * Aggregate per-reviewer statuses into one stamina verdict.
 *
 * Precedence (most-blocking first). The Phase-4 table lists conditions, not a total order; this
 * is the defensible total order, documented so a reader can audit it:
 *   1. Any BLOCKED            -> BLOCKED        (incomplete dispatch is not consensus)
 *   2. Any ESCALATED          -> ESCALATED      (a reviewer found a real problem; ratchet upstream)
 *   3. Any NEEDS_CONTEXT or unrecognized tag:
 *        at ceiling           -> NEEDS_CONTEXT  (user arbitrates)
 *        below ceiling        -> WIDEN_RETRY    (orchestration widens the set by one role, once)
 *   4. Any DONE_WITH_CONCERNS -> DONE_WITH_CONCERNS
 *   5. All DONE               -> DONE
 *
 * The reducer never returns "ship" or "merge"; a BLOCKED/ESCALATED aggregate ratchets upstream,
 * NEEDS_CONTEXT parks for the user. Acting on the aggregate is the caller's job, never the reduce.
 *
 * @param {ReviewerStatus[]} statuses
 * @param {{ atCeiling: boolean }} opts
 * @returns {{ verdict: Aggregate, reason: string }}
 */
export function consensus(statuses, opts) {
  if (!Array.isArray(statuses) || statuses.length === 0) {
    return { verdict: "NEEDS_CONTEXT", reason: "no reviewer verdicts collected" };
  }
  const atCeiling = opts?.atCeiling === true;

  const has = (s) => statuses.includes(s);
  const unrecognized = statuses.filter((s) => !REVIEWER_STATUSES.has(s));

  if (has("BLOCKED")) {
    return { verdict: "BLOCKED", reason: "a reviewer did not publish a verdict (dispatch failed)" };
  }
  if (has("ESCALATED")) {
    return { verdict: "ESCALATED", reason: "a reviewer escalated or requested changes; ratchet upstream" };
  }
  if (has("NEEDS_CONTEXT") || unrecognized.length > 0) {
    const why = unrecognized.length > 0
      ? `unrecognized reviewer status: ${unrecognized.join(", ")}`
      : "a reviewer returned NEEDS_CONTEXT";
    return atCeiling
      ? { verdict: "NEEDS_CONTEXT", reason: `${why}; at ceiling, user arbitrates` }
      : { verdict: "WIDEN_RETRY", reason: `${why}; widen the dispatch set by one role and retry once` };
  }
  if (has("DONE_WITH_CONCERNS")) {
    return { verdict: "DONE_WITH_CONCERNS", reason: "approved with reviewer-named concerns" };
  }
  return { verdict: "DONE", reason: "unanimous approve across the dispatch set" };
}

// --selftest: exercise every row of the Phase-4 table. Exit non-zero on any mismatch.
function selftest() {
  const cases = [
    { in: [["DONE", "DONE"], { atCeiling: false }], want: "DONE" },
    { in: [["DONE", "DONE_WITH_CONCERNS"], { atCeiling: false }], want: "DONE_WITH_CONCERNS" },
    { in: [["DONE", "ESCALATED"], { atCeiling: false }], want: "ESCALATED" },
    { in: [["DONE", "BLOCKED"], { atCeiling: true }], want: "BLOCKED" },
    // BLOCKED beats ESCALATED (incomplete dispatch dominates).
    { in: [["ESCALATED", "BLOCKED"], { atCeiling: true }], want: "BLOCKED" },
    // ESCALATED beats NEEDS_CONTEXT and DONE_WITH_CONCERNS.
    { in: [["ESCALATED", "NEEDS_CONTEXT", "DONE_WITH_CONCERNS"], { atCeiling: true }], want: "ESCALATED" },
    // NEEDS_CONTEXT below ceiling -> widen+retry; at ceiling -> NEEDS_CONTEXT.
    { in: [["DONE", "NEEDS_CONTEXT"], { atCeiling: false }], want: "WIDEN_RETRY" },
    { in: [["DONE", "NEEDS_CONTEXT"], { atCeiling: true }], want: "NEEDS_CONTEXT" },
    // Unrecognized tag is treated as NEEDS_CONTEXT-class (never guessed).
    { in: [["DONE", "LGTM"], { atCeiling: true }], want: "NEEDS_CONTEXT" },
    { in: [["DONE", "LGTM"], { atCeiling: false }], want: "WIDEN_RETRY" },
    // Empty input is a NEEDS_CONTEXT stop.
    { in: [[], { atCeiling: false }], want: "NEEDS_CONTEXT" },
  ];
  let failed = 0;
  for (const c of cases) {
    const got = consensus(c.in[0], c.in[1]).verdict;
    if (got !== c.want) {
      failed++;
      console.error(`FAIL: consensus(${JSON.stringify(c.in[0])}, ${JSON.stringify(c.in[1])}) = ${got}, want ${c.want}`);
    }
  }
  if (failed > 0) {
    console.error(`consensus selftest: ${failed} case(s) failed`);
    process.exit(1);
  }
  console.log(`consensus selftest: ${cases.length} cases passed`);
}

if (process.argv.includes("--selftest")) selftest();
