# Walkthrough: brief v1 — the ship-ready plan

**Target**: chughtapan/brief#7 plan-approved · **Scenes**: 6

## Scene 1 — Hook
- Type: title
- Title card: "SHIP-READY"
- Subtitle: "brief v1 — survived 4 review rounds"
- Narration: The plan is ship-ready. It survived four rounds of review, a three-round security fight, and two of your amendments. Here is where it landed, and the one decision that unlocked it.

## Scene 2 — The final shape
- Type: code
- Files: spike/walkthrough/final-plan-source.md
- Show: `bat --line-range 3:12 spike/walkthrough/final-plan-source.md`
- Highlight: 5-9
- Narration: Five packages, Effect from top to bottom. Wire holds the codec and the schemas, so the browser bundle stays lean. Pipeline runs the whole sequence. Player renders it. C l i is the binary. Eval grades the prompts. And the planner is not code at all. The agent writes the transcript through a skill. The code is just a thin parser.

## Scene 3 — The security story
- Type: code
- Files: spike/walkthrough/final-plan-source.md
- Show: `bat --line-range 14:22 spike/walkthrough/final-plan-source.md`
- Highlight: 20-22
- Narration: The hard part was security. Brief runs git against the very repo it narrates, and three review rounds each found a new way a malicious repo could run code. Shell characters, then binary names, then git flags, then git's own config. The cross-model codex pass caught the class no single model did. Your call closed it. Narrow version one to trusted, your own, repos. That ended the fight by scope, not by more code, and codex agreed it is a legitimate posture, the same trust you already give your editor and git itself.

## Scene 4 — Deferred by your decision
- Type: code
- Files: spike/walkthrough/final-plan-source.md
- Show: `bat --line-range 24:27 spike/walkthrough/final-plan-source.md`
- Highlight: 26-27
- Narration: Two things you chose to defer. The real-device Safari and mobile test moves to after ship, with a fallback already in the plan. And hardening against untrusted third-party pull requests is a roadmap item, explicitly out of scope for version one.

## Scene 5 — What held up under fire
- Type: code
- Files: spike/walkthrough/final-plan-source.md
- Show: `bat --line-range 29:33 spike/walkthrough/final-plan-source.md`
- Highlight: 31-33
- Narration: And what held up under fire. The new no P T Y capture path came back go, at version five quality. The Effect surface and the package boundaries passed all four rounds. And the whole thing cost you under two hours of attention, well inside the budget.

## Scene 6 — Outro
- Type: outro
- Title card: "NEXT: BUILD"
- Subtitle: "implement -> review -> verify · park before merge + launch"
- Narration: Next is the build. On your go, the repo gets seeded and implementation runs through review and verify, parking before the merge and the launch. Those two stay yours.
