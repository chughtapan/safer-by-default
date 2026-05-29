// safer:docs-reader — the 4-persona cold-start read as a Claude Code Workflow (ONE round).
//
// WHAT THIS IS. A reference Workflow script for docs-reader's dispatch + aggregate: spawn the 4
// canonical personas in parallel, each reading the artifact COLD, then run the severity-weighted
// consensus aggregator (deterministic; the closed failure-mode enum makes the keying pure). It
// replaces the manual TeamCreate + per-persona Agent + schema-validate-and-retry dance.
//
// WHAT THIS IS NOT. This runs EXACTLY ONE round. Round 2 (the user applies revisions and
// re-invokes) and round 3 (`--allow-round-3`) are HUMAN gates — the script must not auto-advance
// them. Cold-start isolation is the iron rule: each persona receives ONLY the artifact payload +
// its lens + the schema — never session history, the parent epic, or sibling docs (passing those
// would defeat the exact bug the personas exist to catch). The aggregator introduces no judgments
// the personas did not emit. A cross-persona CONTRADICTION is surfaced for escalation, never
// auto-resolved. Emit-only: the script never revises the artifact.
//
// NOTE. This is a Claude Code Workflow script: top-level `await`/`return` execute inside the
// Workflow harness's async wrapper. A standalone TS/JS parser (your editor's LSP) does not know
// that and will mis-flag the top-level `return`s — those diagnostics are expected and harmless.
//
// INVOCATION. Main-loop docs-reader only; a dispatched docs-reader teammate and Codex fall back to
// the prose SKILL.md. args carries the resolved artifact payload (already fetched by the prose).

export const meta = {
  name: "docs-reader-personas",
  description: "One round: 4 cold-start personas read an artifact in parallel, then a deterministic severity-weighted aggregate. Emit-only; never auto-advances rounds.",
  phases: [{ title: "Persona read", detail: "4 cold-start opus personas in parallel" }],
}

// args = { artifactRef?: "<url-or-abs-path>", artifact?: "<inline payload>", round: 1, personas?: [names] }
// Normalize args. The harness delivers `args` as a JSON string, and large/nested payloads arrive
// malformed (a stray bracket makes it unparseable). Parse defensively and FAIL LOUD — a silent
// fallback to the placeholder would have personas review nothing.
// Prefer `artifactRef` (a URL or absolute path) for anything non-trivial: a large artifact inlined
// in args overflows the fragile args channel, so each persona READS the ref instead (reading the
// one named artifact preserves cold-start isolation). Inline `artifact` is for small payloads only.
// (See docs/workflow-composition.md → "Passing inputs".)
function parseArgs(a) {
  if (a == null || (typeof a === "string" && a.trim() === "")) return { ok: true, A: {} }
  if (typeof a !== "string") return { ok: true, A: a }
  try { return { ok: true, A: JSON.parse(a) } } catch (e) { return { ok: false, error: String(e) } }
}
const _p = parseArgs(args)
if (!_p.ok) return { status: "BLOCKED", error: `args did not parse: ${_p.error}`, hint: "Pass the artifact by reference (artifactRef: a URL or absolute path) rather than inlining a large payload in args." }
const A = _p.A
const artifactRef = A.artifactRef ?? null
const artifact = artifactRef
  ? `Read the artifact under review from this reference (it is your ONLY input): ${artifactRef}`
  : (A.artifact ?? "<artifact payload missing>")
const round = A.round ?? 1

const CANONICAL = {
  "cold-start-junior": "A junior engineer with zero prior context. Flag anything you cannot act on without outside knowledge: missing context, presumed prerequisites, undefined jargon.",
  "install-operator": "An operator following the install/setup steps literally. Flag irreversible steps, presumed prerequisites, and any command or path that would fail from a clean machine.",
  "cli-ergonomics-auditor": "A CLI/API ergonomics reviewer. Flag flag-incoherence, discoverability gaps, noisy output, and terminology collisions.",
  "security-skeptic": "A security reviewer. Flag unevidenced auth claims, secret leaks, and any trust-boundary assertion stated without proof.",
}
const FAILURE_MODES = new Set([
  "missing-context", "terminology-collision", "presumed-prerequisite", "irreversible-step",
  "noisy-output", "auth-claim-unevidenced", "secret-leak", "flag-incoherence",
  "discoverability-gap", "jargon-density",
])
const names = A.personas ?? Object.keys(CANONICAL)

const PERSONA_SCHEMA = {
  type: "object",
  required: ["verdict", "items", "axisScores", "confidence"],
  properties: {
    verdict: { type: "string", enum: ["SHIP", "REVISE"] },
    confidence: { type: "string", enum: ["LOW", "MED", "HIGH"] },
    items: {
      type: "array",
      items: {
        type: "object",
        required: ["severity", "location", "failure_mode", "evidence"],
        properties: {
          severity: { type: "string", enum: ["BLOCK", "FRICTION", "NIT"] },
          location: { type: "string", description: "section heading or quoted phrase (the anchor)" },
          failure_mode: { type: "string", enum: [...FAILURE_MODES] },
          evidence: { type: "string" },
        },
      },
    },
    axisScores: { type: "object", description: "axis name -> integer 0-10", additionalProperties: { type: "number" } },
  },
}

const personaPrompt = (lens) => `You are a docs-reader persona reading ONE artifact COLD — you have no prior context, no session
history, no parent issue, no sibling docs. Your lens: ${lens}

The complete artifact (this is all you get):
---
${artifact}
---

Report ONLY what this artifact does or does not let you do. If you needed context outside the
artifact to proceed, that IS the finding (severity BLOCK or FRICTION, not an error). Return:
verdict (SHIP | REVISE), items (each: severity BLOCK|FRICTION|NIT, location = the section heading
or quoted phrase, failure_mode from the closed enum, evidence), axisScores (0-10 integers), and
confidence (LOW | MED | HIGH).`

phase("Persona read")
log(`docs-reader round ${round}: dispatching ${names.length} cold-start personas`)

const slots = await parallel(
  names.map((n) => () =>
    agent(personaPrompt(CANONICAL[n] ?? n), { label: `persona:${n}`, model: "opus", schema: PERSONA_SCHEMA })
      .then((r) => ({ persona: n, ok: !!r, report: r }))
      .catch(() => ({ persona: n, ok: false, report: null })), // SYSTEM_FAILURE slot
  ),
)

// All personas failed -> ESCALATED (PERSONA_DISPATCH_FAILURE). Faithful to the SKILL's exit.
const live = slots.filter((s) => s.ok && s.report)
if (live.length === 0) {
  return { status: "ESCALATED", cause: "PERSONA_DISPATCH_FAILURE", slots }
}

// --- severity-weighted consensus aggregator (deterministic; SKILL §Aggregation) ----------------
// Item key = (lowercased location anchor, failure_mode). Two items aggregate iff both match.
const key = (it) => `${String(it.location).trim().toLowerCase()} ${it.failure_mode}`
const byKey = new Map() // key -> { severities, personas, frictionPersonas, sample }
for (const s of live) {
  for (const it of s.report.items ?? []) {
    if (!FAILURE_MODES.has(it.failure_mode)) continue // reject out-of-enum (invalid persona output)
    const k = key(it)
    const e = byKey.get(k) ?? { severities: new Set(), personas: new Set(), frictionPersonas: new Set(), sample: it }
    e.severities.add(it.severity)
    e.personas.add(s.persona)
    if (it.severity === "FRICTION") e.frictionPersonas.add(s.persona) // count FRICTION-emitting personas, not any-severity
    byKey.set(k, e)
  }
}

const mustFix = [], shouldFix = [], logged = []
for (const [k, e] of byKey) {
  const item = { key: k, ...e.sample, personaCount: e.personas.size }
  if (e.severities.has("BLOCK")) mustFix.push(item)                                  // BLOCK (any 1+)
  else if (e.frictionPersonas.size >= 2) shouldFix.push(item)                        // FRICTION from >=2 personas
  else logged.push(item)                                                             // FRICTION x1 + NIT
}

// Axis rollup = arithmetic mean over personas that emitted that axis (missing != 0).
const axisRollup = {}
const axisAcc = new Map()
for (const s of live) {
  for (const [axis, score] of Object.entries(s.report.axisScores ?? {})) {
    if (typeof score !== "number") continue
    const a = axisAcc.get(axis) ?? { sum: 0, n: 0 }
    a.sum += score; a.n += 1; axisAcc.set(axis, a)
  }
}
for (const [axis, a] of axisAcc) axisRollup[axis] = Math.round((a.sum / a.n) * 10) / 10

// Final verdict: SHIP iff must-fix empty AND no persona REVISE. Confidence: the lowest persona's.
const RANK = { LOW: 0, MED: 1, HIGH: 2 }
const anyRevise = live.some((s) => s.report.verdict === "REVISE")
const verdict = mustFix.length === 0 && !anyRevise ? "SHIP" : "REVISE"
const confidence = live.reduce((lo, s) => (RANK[s.report.confidence] < RANK[lo] ? s.report.confidence : lo), "HIGH")

return {
  round,
  verdict,
  confidence,
  mustFix,
  shouldFix,
  logged,
  axisRollup,
  perPersona: live.map((s) => ({ persona: s.persona, verdict: s.report.verdict, confidence: s.report.confidence })),
  failedPersonas: slots.filter((s) => !s.ok).map((s) => s.persona),
  reminder: "ONE round only. Round 2/3 are human gates — do not auto-advance. A cross-persona CONTRADICTION on a load-bearing claim is ESCALATED by the prose, never auto-resolved. Emit-only: never revise the artifact.",
}
