# Walkthrough: spike — narrated PR walkthrough pipeline (the meta one)

**Target**: spike/walkthrough @ 25ad65b · **Total duration**: ~88s · **Scenes**: 6

## Scene 1 — Intro & meta (10s)
- Title card: "SPIKE META"
- Files: none
- Show: `figlet -f slant 'SPIKE META'`
- Highlight: this very video is the pipeline's own dogfood
- Narration: This PR scaffolds a narrated walkthrough pipeline. The video you're watching is its first dogfood run.

## Scene 2 — Pipeline architecture (18s)
- Title card: "5 STAGES"
- Files: spike/walkthrough/README.md
- Show: `bat --line-range 49:75 spike/walkthrough/README.md`
- Highlight: five stages — PLAN, RECORD, NARRATE, MERGE, PUBLISH — each leaving a reviewable artifact
- Narration: Five stages. PLAN gathers evidence and dispatches a subagent. RECORD turns the markdown plan into a vhs tape. NARRATE produces SSML. MERGE and PUBLISH glue it together. Every handoff is a file on disk.

## Scene 3 — scene_planner.ts (18s)
- Title card: "PLAN TO TAPE"
- Files: spike/walkthrough/scene_planner.ts
- Show: `bat --line-range 40:65 spike/walkthrough/scene_planner.ts`
- Highlight: regex-parses scene headers, emits a vhs tape plus a per-scene duration manifest
- Narration: scene_planner walks the markdown plan. It pulls out per-scene fields with one regex, emits a vhs tape, and writes a manifest the narrator stage needs to align audio to video.

## Scene 4 — tts.ts and padding (18s)
- Title card: "TTS + PAD"
- Files: spike/walkthrough/tts.ts
- Show: `bat --line-range 135:160 spike/walkthrough/tts.ts`
- Highlight: synthesize per scene, then pad with silence so each scene's audio matches its on-screen duration exactly
- Narration: tts hits Cartesia once per scene, measures the wav, then pads with silence to the manifest target. Drift accumulates fast in a ninety-second video. This kills it at the boundary.

## Scene 5 — Planner contract (14s)
- Title card: "CONTRACT"
- Files: spike/walkthrough/prompts/planner.md
- Show: `bat --line-range 45:60 spike/walkthrough/prompts/planner.md`
- Highlight: lead with the load-bearing change, four to seven scenes, narration budget at 140 wpm
- Narration: The planner's job is structure, not prose. Lead with what's load-bearing, cap at seven scenes, budget narration honestly at one-forty words per minute.

## Scene 6 — Outro & verify (10s)
- Title card: "WATCH ME"
- Files: none
- Show: `figlet -f slant 'WATCH ME'`
- Highlight: prompt the viewer to open the asset URL in the PR body and judge the output quality
- Narration: The pipeline shipped its own walkthrough. Open the asset in the PR body and judge whether you'd actually watch this for review.
