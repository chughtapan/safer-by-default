# Walkthrough: brief — the architect plan, narrated

**Target**: chughtapan/brief#7 architect plan · **Scenes**: 7

## Scene 1 — Hook
- Type: title
- Title card: "BRIEF ME ON THE PLAN"
- Subtitle: "5 packages · Effect end to end · the PARK"
- Narration: You asked for the plan, so here it is out loud. The architect turned the contract and four green spikes into a build shape. Five packages, Effect from top to bottom. Watch where an artifact becomes a narrated player.

## Scene 2 — Five packages
- Type: code
- Files: spike/walkthrough/brief-plan-source.md
- Show: `bat --line-range 3:9 spike/walkthrough/brief-plan-source.md`
- Highlight: 5-9
- Narration: Five packages, each with one job. Core is the pipeline that turns an artifact into cast plus audio. Player is the static browser bundle. Emit writes the output, local first. C l i is the brief binary the agent shells out to. Eval grades the planner prompts. The highlighted five are the whole system.

## Scene 3 — The data flow
- Type: code
- Files: spike/walkthrough/brief-plan-source.md
- Show: `bat --line-range 11:20 spike/walkthrough/brief-plan-source.md`
- Highlight: 14-20
- Narration: This is the dogfood path, brief on a markdown file. The planner writes the story, Cartesia speaks it, asciinema records the screen with per scene markers, scrub checks for secrets, and the envelope packs manifest, cast, and audio into one blob. Emit inlines it into a single h t m l you open from a file. No server, no upload.

## Scene 4 — Type discipline
- Type: code
- Files: spike/walkthrough/brief-plan-source.md
- Show: `bat --line-range 22:28 spike/walkthrough/brief-plan-source.md`
- Highlight: 24-25
- Narration: The type discipline is Effect, not Zod. Every fallible function returns Effect of A, E, R, so the error set lives in the signature, not as a surprise at runtime. Errors are tagged classes the caller must exhaust. Boundaries decode through schema. Even the Cartesia and asciinema adapters are services, so tests run against the real thing, never a mock.

## Scene 5 — Dev-infra
- Type: code
- Files: spike/walkthrough/brief-plan-source.md
- Show: `bat --line-range 30:34 spike/walkthrough/brief-plan-source.md`
- Highlight: 32-34
- Narration: Brief eats its own dog food. The same three safer guards run on it. A twenty three rule architecture lint floor, a live language server that links each finding back to the principles doc, and per folder living specs whose validate exit codes route a failure to the right modality.

## Scene 6 — Locked, and still open
- Type: code
- Files: spike/walkthrough/brief-plan-source.md
- Show: `bat --line-range 36:47 spike/walkthrough/brief-plan-source.md`
- Highlight: 45-47
- Narration: The spikes already settled the hard calls. Native player sync at twelve milliseconds, sonic three for voice, plain g zip for the fragment, local h t m l as the primary share. What is still yours is the highlighted three. The real device Safari test that gates implementation, a nod on the package count, and confirming core schema over the retired standalone.

## Scene 7 — Outro
- Type: outro
- Title card: "YOUR CALL"
- Subtitle: "approve + pick a review path → first code"
- Narration: That is the plan. Approve it and pick a review path, and the first real code lands behind these same guards.
