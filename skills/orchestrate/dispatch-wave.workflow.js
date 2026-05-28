// safer:orchestrate — one dispatch wave as a Claude Code Workflow.
//
// WHAT THIS IS. A reference Workflow script that executes ONE wave of orchestrate's Phase 5
// dispatch: given the decomposition DAG and current sub-issue states, dispatch every ready
// modality in parallel (each in its own git worktree), wait for all to publish, and return their
// structured receipts. It replaces the hand-managed substrate that exists only because the old
// path used fire-and-forget tmux teammates: the CronCreate 2-min poll loop (Step 5d), the swarm
// socket discovery + dead-pane cleanup (Step 1a / Step 4 paths a-b), the per-tick cap vs
// pane_ceiling math, roster rewriting, and SendMessage marker-parsing. parallel() awaits
// completion (nothing to poll); the runtime's concurrency cap is the capacity limit; agent()
// isolation:'worktree' gives each modality its own tree; the schema gives a validated receipt.
//
// WHAT THIS IS NOT. This is not orchestrate. It runs the rulebook's dispatch step; it is not a
// second dispatcher (review-senior Invariant 11 holds). It does NOT transition labels, merge PRs,
// close sub-issues, resolve the contract budget, route diagnose verdicts, or advance the DAG.
// Every receipt returns to orchestrate's PROSE lifecycle, which applies the contract gate
// (Phase 5c.-1), the ratchet (any escalation parks), and the stop conditions — the human gates
// stay in prose, between waves. The cross-session epic lifecycle (contract OK, park-and-wait,
// resume days later) is NOT expressible as one Workflow run and stays prose by design.
//
// INVOCATION. Only the main-loop team-lead (the orchestrate session itself) can call this; a
// dispatched teammate cannot invoke Workflow. Codex has no Workflow tool. Both fall back to the
// prose Phase 5 in SKILL.md. args is the wave input the prose lifecycle assembles from GitHub.
//
// NOTE. This is a Claude Code Workflow script: top-level `await`/`return` execute inside the
// Workflow harness's async wrapper. A standalone TS/JS parser (your editor's LSP) does not know
// that and will mis-flag the top-level `return`s — those diagnostics are expected and harmless.

export const meta = {
  name: "orchestrate-dispatch-wave",
  description: "One orchestrate dispatch wave: fan out ready modalities (worktree-isolated), collect receipts. No gating, no merge, no DAG advance.",
  phases: [{ title: "Dispatch wave", detail: "parallel modality dispatch over the ready set" }],
}

// --- ready-set resolver: mirror of skills/orchestrate/ready-set.mjs (canonical; keep in sync;
// Workflow scripts cannot import local files). ---------------------------------------------------
const PARKED = new Set(["paused", "awaiting-amendment", "blocked"])
const NO_DEP = new Set(["", "none", "-"]) // NOT #tbd: that is an unsatisfied placeholder dep.
const norm = (id) => String(id ?? "").trim().replace(/^#/, "")
function readySet(rows) {
  if (!Array.isArray(rows)) return []
  const stateById = new Map(rows.map((r) => [norm(r.subIssue), r.state]))
  const depDone = (dep) => stateById.get(norm(dep)) === "done"
  const realDeps = (r) => (r.dependsOn ?? []).filter((d) => !NO_DEP.has(norm(d).toLowerCase()))
  return rows.filter(
    (r) => r.state === "planning" && !PARKED.has(r.state) && realDeps(r).every(depDone),
  )
}

// --- wave input (args) --------------------------------------------------------------------------
// args = {
//   rows: [{ subIssue, modality, dependsOn?: [], acceptance, state, url }],  // the decomposition table + live states
//   parentEpic: "<url>", repo: "owner/name", pluginRoot: "<path>",
// }
// Normalize args. The harness delivers `args` as a JSON string, and large/nested payloads can
// arrive malformed (a stray bracket makes the whole thing unparseable). Parse defensively and
// FAIL LOUD — a silent no-op masquerades as "no work" and masks a malformed dispatch.
// Keep args SMALL: rows are short pointers (subIssue / modality / dependsOn / state / url). The
// dispatched modality agent reads acceptance + context from its sub-issue, so no long text rides
// in args. (See docs/workflow-composition.md → "Passing inputs".)
function parseArgs(a) {
  if (a == null || (typeof a === "string" && a.trim() === "")) return { ok: true, A: {} }
  if (typeof a !== "string") return { ok: true, A: a }
  try { return { ok: true, A: JSON.parse(a) } } catch (e) { return { ok: false, error: String(e) } }
}
const _p = parseArgs(args)
if (!_p.ok) return { status: "BLOCKED", error: `args did not parse: ${_p.error}`, hint: "Workflow args must be small, well-formed JSON; pass large content by reference (a URL the dispatched agent fetches), not inline." }
const A = _p.A
const rows = A.rows ?? []
const parentEpic = A.parentEpic ?? "<parent-epic-url>"
const pluginRoot = A.pluginRoot ?? "the plugin root"

const STATUS_SCHEMA = {
  type: "object",
  required: ["subIssue", "modality", "status"],
  properties: {
    subIssue: { type: "string" },
    modality: { type: "string" },
    status: { type: "string", enum: ["DONE", "DONE_WITH_CONCERNS", "ESCALATED", "BLOCKED", "NEEDS_CONTEXT"] },
    artifactUrl: { type: "string", description: "the comment/PR/label change the modality published to its sub-issue" },
    note: { type: "string", description: "one line: what was produced, or why it escalated/blocked" },
  },
}

// The Phase 5a teammate prompt, verbatim shape. The Workflow runs each modality as an agent() in
// its own worktree; the modality publishes its artifact to GitHub and returns the validated receipt.
const modalityPrompt = (r) => `You are invoking the /safer:${r.modality} skill against one sub-issue.

Context:
- Parent epic: ${parentEpic}
- Your sub-issue: ${r.url}
- Read both issues before starting.
- Read PRINCIPLES.md and skills/${r.modality}/SKILL.md at ${pluginRoot}.

Your assignment (the sub-issue's acceptance criteria, verbatim):
${r.acceptance ?? "(see the sub-issue body)"}

Publish your artifact back to the sub-issue (comment, PR, or label change per the modality's
publication rule). Do NOT transition labels you do not own, merge anything, or touch sibling
sub-issues. When finished, return the receipt: subIssue, modality, status (one of
DONE / DONE_WITH_CONCERNS / ESCALATED / BLOCKED / NEEDS_CONTEXT), artifactUrl, and a one-line note.`

phase("Dispatch wave")
const ready = readySet(rows)
log(`ready set: ${ready.length} of ${rows.length} rows dispatchable this wave`)
if (ready.length === 0) {
  return { dispatched: [], note: "no ready rows (deps unsatisfied or all parked/in-flight); prose lifecycle decides whether to park, create a #TBD row, or wait" }
}

const receipts = await parallel(
  ready.map((r) => () =>
    agent(modalityPrompt(r), {
      label: `dispatch:${r.modality}#${norm(r.subIssue)}`,
      schema: STATUS_SCHEMA,
      isolation: "worktree",
    }).then((rec) => rec ?? { subIssue: norm(r.subIssue), modality: r.modality, status: "BLOCKED", note: "agent returned no receipt (skipped or errored)" }),
  ),
)

// Return the wave's receipts ONLY. orchestrate's prose lifecycle (Phase 5c) reads each reviewer
// body, applies the contract-budget gate, ratchets any escalation upstream, and advances the DAG.
// This script never gates, merges, transitions, or closes.
return {
  dispatched: receipts,
  needsProseAttention: receipts.filter((r) => r && r.status !== "DONE"),
  reminder: "Apply contract gate / ratchet / DAG advance in the prose lifecycle. No gate is auto-advanced here.",
}
