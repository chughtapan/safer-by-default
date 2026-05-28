// safer:verify — Phase 3.5 (gstack testing-layer composition) as a Claude Code Workflow.
//
// WHAT THIS IS. A reference Workflow script for verify's Phase 3.5: evaluate each of the 7 gstack
// composition targets' trigger conditions, dispatch ONLY the targets whose trigger fires (in
// parallel — they are independent read-only observations against a deployed/runnable artifact),
// and fold their verdicts through the Phase-5 precedence table. It turns "the model remembers to
// fire the right subset of targets and aggregate them correctly" into deterministic control flow.
// (SKILL.md's Phase-3.5 table lists 8 rows; this runs the 7 report-only forms — /qa is excluded,
// verify never runs a --fix variant, so its report-only sibling /qa-only stands in.)
//
// WHAT THIS IS NOT. This is not verify. Ring 1 (lint / typecheck / test / safer-spec validate)
// stays in Phase 3's deterministic bash — this script is Phase 3.5 only, an advisory input to the
// final verdict. Verify's iron rule holds: every target runs in REPORT-ONLY / advisory mode (never
// a /qa or /design-review --fix variant — verify never self-edits). A composed target that would
// prompt for user input is surfaced/escalated to /safer:orchestrate, never auto-answered. The
// script computes the Phase-3.5 verdict and returns it; the final SHIP/HOLD decision is verify's.
//
// NOTE. This is a Claude Code Workflow script: top-level `await`/`return` execute inside the
// Workflow harness's async wrapper. A standalone TS/JS parser (your editor's LSP) does not know
// that and will mis-flag the top-level `return`s — those diagnostics are expected and harmless.
//
// INVOCATION. Main-loop verify only; a dispatched verify teammate and Codex fall back to the prose
// Phase 3.5. args is assembled by the prose lifecycle from the sub-issue + diff + deploy state.

export const meta = {
  name: "verify-phase35",
  description: "verify Phase 3.5: fire the triggered gstack testing targets (report-only), fold verdicts. Advisory input; ring-1 and the final verdict stay in verify.",
  phases: [{ title: "Compose testing layer", detail: "parallel report-only gstack targets whose triggers fire" }],
}

// args = { acceptanceText, diffScope: { files: [] }, qaUrl, deployUrl, labelState, pluginRoot }
// The Workflow harness may deliver `args` as a JSON string rather than a parsed object; normalize.
function parseArgs(a) { if (typeof a !== "string") return a ?? {}; try { return JSON.parse(a) } catch { return {} } }
const A = parseArgs(args)
const acceptance = (A.acceptanceText ?? "").toLowerCase()
const files = A.diffScope?.files ?? []
const qaUrl = A.qaUrl ?? ""
const deployUrl = A.deployUrl ?? ""
const labelState = A.labelState ?? ""

const refs = (...needles) => needles.some((n) => acceptance.includes(n))
const touches = (...frags) => files.some((f) => frags.some((g) => String(f).includes(g)))

// The 7 report-only composition targets, each with its trigger predicate (faithful to SKILL.md Phase 3.5) and
// the gstack invocation in its REPORT-ONLY form. `worstVerdict` documents the target's mapping
// from finding-severity to the verify verdict it can contribute.
const TARGETS = [
  { name: "/health",          fires: () => refs("health score", "code quality", "lint floor") || touches("package.json", "tsconfig.json", "eslint"), invoke: "gstack invoke /health --report-only", worstVerdict: "SHIP_WITH_CONCERNS" },
  { name: "/qa-only",         fires: () => (refs("qa", "user flow", "test the app") || refs("qa report")) && !!qaUrl, invoke: `gstack invoke /qa-only --url ${qaUrl || "<qa-url>"}`, worstVerdict: "HOLD" },
  { name: "/canary",          fires: () => !!deployUrl && labelState === "verifying", invoke: `gstack invoke /canary --url ${deployUrl || "<deploy-url>"} --window 10m`, worstVerdict: "SHIP_WITH_CONCERNS" },
  { name: "/design-review",   fires: () => refs("visual", "design", "ui", "look") && !!qaUrl, invoke: `gstack invoke /design-review --url ${qaUrl || "<qa-url>"} --report-only`, worstVerdict: "HOLD" },
  { name: "/devex-review",    fires: () => refs("developer experience", "dx", "api design", "cli", "docs onboarding") && !!deployUrl, invoke: `gstack invoke /devex-review --url ${deployUrl || "<deploy-url>"}`, worstVerdict: "SHIP_WITH_CONCERNS" },
  { name: "/benchmark",       fires: () => refs("performance", "benchmark", "page speed", "web vitals") && !!deployUrl, invoke: `gstack invoke /benchmark --url ${deployUrl || "<deploy-url>"} --baseline main`, worstVerdict: "HOLD" },
  { name: "/benchmark-models",fires: () => refs("model benchmark", "skill prompt comparison"), invoke: "gstack invoke /benchmark-models --skill <name>", worstVerdict: "pass" }, // report-only; never blocks
]

const VERDICT_SCHEMA = {
  type: "object",
  required: ["target", "verdict"],
  properties: {
    target: { type: "string" },
    verdict: { type: "string", enum: ["pass", "SHIP_WITH_CONCERNS", "HOLD"] },
    summary: { type: "string" },
    artifactUrl: { type: "string" },
  },
}

const targetPrompt = (t) => `Run the gstack target ${t.name} in REPORT-ONLY / advisory mode as a verify Phase-3.5 composition pass.
Command: ${t.invoke}
Do NOT apply any fix (verify never self-edits — that is /safer:implement-* work). If ${t.name}
would prompt for user input, STOP and report that as needing escalation to /safer:orchestrate;
do not answer the prompt.
Map findings to a verdict per the Phase-3.5 table: this target's most-severe contribution is
"${t.worstVerdict}" (a critical/blocker finding) and otherwise "pass". Return: target, verdict
(pass | SHIP_WITH_CONCERNS | HOLD), a one-line summary, and the artifact URL if one was published.`

phase("Compose testing layer")
const fired = TARGETS.filter((t) => t.fires())
log(`Phase 3.5: ${fired.length} of ${TARGETS.length} targets triggered: ${fired.map((t) => t.name).join(", ") || "(none)"}`)
if (fired.length === 0) {
  return { phase35Verdict: "pass", targets: [], note: "no Phase-3.5 trigger fired; ring-1 verdict stands unchanged" }
}

const results = await parallel(
  fired.map((t) => () =>
    agent(targetPrompt(t), { label: `verify3.5:${t.name}`, schema: VERDICT_SCHEMA }).then((r) =>
      r ?? { target: t.name, verdict: "SHIP_WITH_CONCERNS", summary: "target dispatch returned no result; treat as a concern, not a clean pass" },
    ),
  ),
)

// Phase-5 precedence: any composed HOLD -> HOLD; any SHIP_WITH_CONCERNS -> SHIP_WITH_CONCERNS;
// else no change to the ring-1 verdict. Advisory only — verify owns the final SHIP/HOLD.
const verdicts = results.map((r) => r.verdict)
const phase35Verdict = verdicts.includes("HOLD")
  ? "HOLD"
  : verdicts.includes("SHIP_WITH_CONCERNS")
    ? "SHIP_WITH_CONCERNS"
    : "pass"

return {
  phase35Verdict,
  targets: results,
  reminder: "Advisory input to verify's final verdict. Ring-1 (lint/typecheck/test) is separate. No fixes applied here.",
}
