# Walkthrough: narrated PR walkthrough pipeline — v2 audio-first redesign

**Target**: spike/walkthrough-narration @ 91dee66 · **Scenes**: 6

## Scene 1 — Intro and the flip
- Title card: "V2 AUDIO 1ST"
- Files: none
- Show: `git log --oneline main..HEAD`
- Narration: This PR scaffolds a narrated walkthrough pipeline, ships a first end to end run, writes a verdict, and then flips the architecture. The headline is the last commit. Narration now drives timing instead of the planner guessing seconds up front.

## Scene 2 — Why v1 had to be redesigned
- Title card: "WHY FLIP"
- Files: spike/walkthrough/VERDICT.md
- Show: `bat --line-range 22:37 spike/walkthrough/VERDICT.md`
- Narration: In v1 the planner allocated per scene seconds. Both the recorder and the narrator then had to fit that guess, and the merge stage reconciled with ffmpeg atempo. Scene two got compressed one point six times. That is the inverted architecture v2 deletes.

## Scene 3 — TTS first, measure, then manifest
- Title card: "TTS FIRST"
- Files: spike/walkthrough/tts.ts
- Show: `bat --line-range 201:225 spike/walkthrough/tts.ts`
- Narration: Cartesia now runs first. For each scene we synthesize the prose, append eight hundred milliseconds of tail silence so the viewer has a beat, then measure the wav with ffprobe. The measured duration is the contract every later stage reads from manifest dot json.

## Scene 4 — Recorder sizes Sleeps from measured audio
- Title card: "MATCH AUDIO"
- Files: spike/walkthrough/scene_planner.ts
- Show: `bat --line-range 68:80 spike/walkthrough/scene_planner.ts`
- Narration: The scene planner reads the manifest and sizes each vhs Sleep to match. The one point two one factor corrects for vhs rendering about seventeen percent under wall clock. No atempo, no padding negotiation, no drift. The video lands on audio boundaries per scene.

## Scene 5 — Plain prose contract for narration
- Title card: "PLAIN PROSE"
- Files: spike/walkthrough/prompts/planner.md
- Show: `bat --line-range 45:62 spike/walkthrough/prompts/planner.md`
- Narration: The planner prompt now forbids durations and forbids all markup inside narration. No SSML, no backticks, no asterisks. Cartesia reads whatever you write, literally. So you write it the way a peer engineer would say it out loud.

## Scene 6 — Compare v1 and v2
- Title card: "WATCH ME"
- Files: none
- Show: `figlet -f slant 'WATCH ME'`
- Narration: Two walkthroughs are linked in the PR body. Watch v1 for the atempo crunch on scene two, then watch v2 and see if the alignment problem really did go away.
