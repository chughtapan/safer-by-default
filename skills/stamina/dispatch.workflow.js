// safer:stamina — the heterogeneous review fan-out as a Claude Code Workflow.
//
// WHAT THIS IS. A reference Workflow script that executes stamina's Phase 2-4: dispatch the N
// role-diverse reviewers in parallel, collect each verdict, and reduce to one consensus under the
// deterministic Phase-4 table. It replaces the brittle Mode-A/Mode-B teammate-spawn detection
// (probe Agent, catch "teammates cannot spawn teammates", escalate to team-lead) and the
// marker-parsing in Phase 3 — a Workflow runs in the main loop and fans out directly, and the
// schema returns a validated verdict instead of a string to grep.
//
// WHAT THIS IS NOT. This is not a reviewer and not a second dispatcher (Invariant 11). It never
// reads the diff or the plan to form a first-party opinion — the reduce is pure arithmetic over
// the reviewers' verdicts, which is the Iron Rule made structural. The consensus output is NOT
// "ship": any BLOCKED/ESCALATED ratchets upstream, NEEDS_CONTEXT parks for the user. This script
// computes the aggregate and stops — it does not merge, transition labels, or chain to verify.
//
// INVOCATION. Only the main-loop invoker (user or orchestrate team-lead, i.e. stamina "Mode A")
// can call Workflow; a stamina dispatched as a teammate (Mode B) and Codex both fall back to the
// prose SKILL.md. Classification (which N, which dispatch set) and CI Phase 0 stay in the prose.
//
// NOTE. This is a Claude Code Workflow script: top-level `await`/`return` execute inside the
// Workflow harness's async wrapper. A standalone TS/JS parser (your editor's LSP) does not know
// that and will mis-flag the top-level `return`s — those diagnostics are expected and harmless.

export const meta = {
  name: "stamina-dispatch",
  description: "Fan out N heterogeneous reviewers, reduce to the Phase-4 consensus. Routes, never reviews; never merges.",
  phases: [{ title: "Dispatch reviewers", detail: "parallel review passes" }],
}

// --- consensus reducer: mirror of skills/stamina/consensus.mjs (canonical; keep in sync;
// Workflow scripts cannot import local files). --------------------------------------------------
const REVIEWER_STATUSES = new Set(["DONE", "DONE_WITH_CONCERNS", "ESCALATED", "BLOCKED", "NEEDS_CONTEXT"])
function consensus(statuses, opts) {
  if (!Array.isArray(statuses) || statuses.length === 0) {
    return { verdict: "NEEDS_CONTEXT", reason: "no reviewer verdicts collected" }
  }
  const atCeiling = opts?.atCeiling === true
  const has = (s) => statuses.includes(s)
  const unrecognized = statuses.filter((s) => !REVIEWER_STATUSES.has(s))
  if (has("BLOCKED")) return { verdict: "BLOCKED", reason: "a reviewer did not publish a verdict (dispatch failed)" }
  if (has("ESCALATED")) return { verdict: "ESCALATED", reason: "a reviewer escalated or requested changes; ratchet upstream" }
  if (has("NEEDS_CONTEXT") || unrecognized.length > 0) {
    const why = unrecognized.length > 0 ? `unrecognized status: ${unrecognized.join(", ")}` : "a reviewer returned NEEDS_CONTEXT"
    return atCeiling
      ? { verdict: "NEEDS_CONTEXT", reason: `${why}; at ceiling, user arbitrates` }
      : { verdict: "WIDEN_RETRY", reason: `${why}; widen the dispatch set by one role and retry once` }
  }
  if (has("DONE_WITH_CONCERNS")) return { verdict: "DONE_WITH_CONCERNS", reason: "approved with reviewer-named concerns" }
  return { verdict: "DONE", reason: "unanimous approve across the dispatch set" }
}

// GitHub native CHANGES_REQUESTED normalizes to ESCALATED before the reduce (Phase 3 mapping).
const normalizeStatus = (s) => (s === "CHANGES_REQUESTED" ? "ESCALATED" : String(s ?? "").toUpperCase())

// --- dispatch input (args) ----------------------------------------------------------------------
// args = {
//   dispatchSet: [{ role, skill }],   // role-diverse; classification done in prose / safer-diff-scope
//   spareRoles?: [{ role, skill }],   // for the single widen-and-retry on NEEDS_CONTEXT below ceiling
//   targetUrl, mode: "plan"|"pr", acceptance, atCeiling: boolean, pluginRoot,
// }
const dispatchSet = args?.dispatchSet ?? []
const spareRoles = args?.spareRoles ?? []
const targetUrl = args?.targetUrl ?? "<target-url>"
const acceptance = args?.acceptance ?? "(see the sub-issue / PR-linked issue)"
const atCeiling = args?.atCeiling === true

const REVIEWER_SCHEMA = {
  type: "object",
  required: ["role", "skill", "status"],
  properties: {
    role: { type: "string" },
    skill: { type: "string" },
    status: { type: "string", enum: ["DONE", "DONE_WITH_CONCERNS", "ESCALATED", "BLOCKED", "NEEDS_CONTEXT", "CHANGES_REQUESTED"] },
    verdictUrl: { type: "string", description: "url of the native verdict the reviewer published (gh pr review / issue comment)" },
  },
}

const reviewerPrompt = (e) => `You are running ${e.skill} as a stamina-dispatched reviewer (role: ${e.role}).

Target: ${targetUrl}
Acceptance criteria (verbatim): ${acceptance}

Run the skill's standard workflow. Publish your verdict to the artifact's thread via the skill's
native publication path (gh pr review for PRs, gh issue comment for plans). Do NOT read the other
reviewers' work or synthesize a status you did not observe — you are one voice in the set.
Return the receipt: role, skill, status (DONE / DONE_WITH_CONCERNS / ESCALATED / BLOCKED /
NEEDS_CONTEXT), and verdictUrl.`

// Independence pre-check (Phase 2): reject a set that repeats a skill — same skill + model is one
// pass, not two. /codex is the only cross-model channel.
const skills = dispatchSet.map((e) => e.skill)
const dup = skills.find((s, i) => skills.indexOf(s) !== i)
if (dup) {
  return { verdict: "NEEDS_CONTEXT", reason: `homogeneous dispatch: ${dup} appears twice; same skill+model is one pass (independence rule)` }
}

const dispatchAll = (set) =>
  parallel(
    set.map((e) => () =>
      agent(reviewerPrompt(e), { label: `review:${e.role}`, schema: REVIEWER_SCHEMA }).then((r) =>
        r
          ? { ...r, status: normalizeStatus(r.status) }
          : { role: e.role, skill: e.skill, status: "BLOCKED" }, // reviewer dispatch failed
      ),
    ),
  )

phase("Dispatch reviewers")
let reviewers = await dispatchAll(dispatchSet)
let result = consensus(reviewers.map((r) => r.status), { atCeiling })

// Phase-4 "widen by one role and retry once" — only when below ceiling and a spare role exists.
if (result.verdict === "WIDEN_RETRY") {
  if (spareRoles.length > 0) {
    log(`consensus split below ceiling; widening by one role (${spareRoles[0].role}) and retrying once`)
    const extra = await dispatchAll([spareRoles[0]])
    reviewers = reviewers.concat(extra)
    result = consensus(reviewers.map((r) => r.status), { atCeiling: true }) // the retry is the final attempt
  } else {
    result = { verdict: "NEEDS_CONTEXT", reason: `${result.reason} (no spare role available to widen)` }
  }
}

// Return the consensus + the per-reviewer routing table ONLY. The caller publishes the
// consolidated comment and ratchets/parks per the verdict. This script never merges or transitions.
return {
  verdict: result.verdict,
  reason: result.reason,
  reviewers: reviewers.map((r) => ({ role: r.role, skill: r.skill, status: r.status, verdictUrl: r.verdictUrl ?? null })),
  reminder: "BLOCKED/ESCALATED ratchet upstream; NEEDS_CONTEXT parks for the user. No auto-merge.",
}
