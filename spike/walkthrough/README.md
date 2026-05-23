# spike/walkthrough — narrated PR walkthrough pipeline

Throwaway prototype answering one question:

> Can we produce a watchable narrated walkthrough MP4 for a PR — terminal-recorded diff + Cartesia voice-over + ffmpeg merge + GH release upload + link pasted in PR body — end-to-end in ≤2h, with output quality you'd actually use for review?

Scope, GO criteria, graduation modality: see `VERDICT.md` (written at the end of the run).

## Prerequisites

- `CARTESIA_API_KEY` exported (default: from `~/.bashrc`)
- `gh` CLI authed against this repo
- `bun` ≥ 1.3
- `vhs` (Charm), `ffmpeg`, `figlet`, `bat`, `ttyd` on `PATH`

Verify in one line:

```bash
for b in bun vhs ffmpeg figlet bat ttyd gh; do command -v "$b" >/dev/null || echo "MISSING: $b"; done
test -n "$CARTESIA_API_KEY" || echo "MISSING: CARTESIA_API_KEY"
```

## Runbook (the agent follows these steps in order)

The orchestrator is the agent running the spike, not a shell script. Each stage emits a reviewable artifact on disk.

**Audio-first**: NARRATE runs before RECORD. Cartesia's per-scene WAV duration is measured, then scene_planner sizes each vhs `Sleep` to match. The merge has both streams already aligned per scene, no atempo, no padding negotiation.

### Stage 1 — PLAN (gather evidence + dispatch planning subagent)

```bash
cd spike/walkthrough
mkdir -p evidence audio
git log main..HEAD --format='%H%n%s%n%b%n---' > evidence/commits.txt
git diff main...HEAD --stat                    > evidence/diff-stat.txt
git diff main...HEAD                           > evidence/diff.txt
PR_NUM=$(gh pr view --json number -q .number 2>/dev/null || echo "")
[ -n "$PR_NUM" ] && gh pr view "$PR_NUM" --json reviews,comments > evidence/reviews.json || echo "[]" > evidence/reviews.json
```

Then call the planning subagent (Agent tool, `subagent_type=general-purpose`) with `prompts/planner.md` as the system prompt and the evidence files as input. Save the returned markdown to `narrative_plan.md`. The plan has scenes with `Show:` and `Narration:` fields — **no durations** (those come from TTS).

**Human checkpoint**: show `narrative_plan.md` to the user via AskUserQuestion. Options: ship as-is / let me edit it / abort and re-prompt. Default flow pauses here.

### Stage 2 — NARRATE (plan → per-scene wav + manifest)

Voice: defaults to Cartesia's "Barbershop Man" (`a0e99841-438c-4a64-b679-ae501e7d6091`). Override by exporting `CARTESIA_VOICE_ID` from any voice on https://play.cartesia.ai/voices.

```bash
eval "$(grep '^export CARTESIA_API_KEY=' ~/.bashrc)"
bun run tts.ts narrative_plan.md
# writes audio/scene_N.wav per scene + narration.wav (concatenated) + manifest.json (measured durations)
```

Each scene's narration is sent to Cartesia as plain prose (no SSML, no markup). A 0.8s tail of silence is appended to each scene so the viewer has a beat to register the on-screen state before the next scene cuts in.

Smoke test:

```bash
bun run tts.ts --text "hello from the spike" --out /tmp/hi.wav
```

### Stage 3 — RECORD (plan + manifest → .tape → mp4)

```bash
bun run scene_planner.ts narrative_plan.md manifest.json   # writes walkthrough.tape sized to measured audio
cd ../..   # vhs needs to run from repo root so bat paths resolve
env -i PATH="$PATH" HOME="$HOME" TERM=xterm-256color vhs spike/walkthrough/walkthrough.tape
mv walkthrough.mp4 spike/walkthrough/walkthrough.mp4
```

Smoke test before the real run:

```bash
bun run scene_planner.ts --dry-run narrative_plan.md manifest.json
```

### Stage 4 — MERGE (video + audio → final.mp4)

```bash
ffmpeg -y \
  -i walkthrough.mp4 -i narration.wav \
  -vf "tpad=stop_mode=clone:stop_duration=2s" \
  -c:v libx264 -c:a aac -shortest \
  final.mp4
```

### Stage 5 — PUBLISH (gh release + PR body)

```bash
SHA7=$(git rev-parse --short HEAD)
TAG=spike-walkthrough-${SHA7}
gh release create "$TAG" --draft --notes "Auto-uploaded by spike/walkthrough on $(git branch --show-current)" final.mp4 || gh release upload "$TAG" --clobber final.mp4
ASSET_URL=$(gh release view "$TAG" --json assets -q '.assets[0].url')

PR_NUM=$(gh pr view --json number -q .number 2>/dev/null || gh pr create --draft --fill --json number -q .number)
BODY=$(gh pr view "$PR_NUM" --json body -q .body)
case "$BODY" in
  *"## Walkthrough"*) echo "PR body already has walkthrough section";;
  *) gh pr edit "$PR_NUM" --body "$(printf '%s\n\n## Walkthrough\n%s\n\n<details><summary>Narrative plan</summary>\n\n%s\n</details>\n' "$BODY" "$ASSET_URL" "$(cat narrative_plan.md)")";;
esac

echo "WATCH: $ASSET_URL"
```

### Stage 6 — VERDICT + dogfood

Write `VERDICT.md` scoring each GO criterion. Print the asset URL in chat with a one-line invitation. Stop. Do not invoke `/safer:contract` without re-auth (per autonomy-scope memory).

## Files

| File | Stage | Purpose |
|---|---|---|
| `prompts/planner.md` | 1 | Planning subagent system prompt |
| `evidence/` | 1 | Diff, commits, reviews captured for the planner |
| `narrative_plan.md` | 1 → 2,3 | Structured story (no durations); planner subagent output |
| `tts.ts` | 2 | Reads plan, hits Cartesia per scene, measures WAVs, writes manifest |
| `audio/scene_N.wav` | 2 | Per-scene narration (raw Cartesia output, plus 0.8s tail silence) |
| `narration.wav` | 2 → 4 | Concatenated narration |
| `manifest.json` | 2 → 3 | Per-scene **measured** durations (source of truth for vhs Sleeps) |
| `scene_planner.ts` | 3 | Plan + manifest → vhs `.tape` with measured-duration Sleeps |
| `walkthrough.tape` | 3 → vhs | Generated tape script |
| `walkthrough.mp4` | 3 → 4 | vhs output, silent |
| `final.mp4` | 4 → 5 | Merged video |
| `VERDICT.md` | 6 | GO/MIXED/NO-GO with evidence |

## Re-running

`evidence/` and `narrative_plan.md` are cheap to keep. `audio/`, `*.wav`, `*.mp4`, `*.tape` are regenerated and gitignored. Same-sha re-runs reuse the existing GH release via `--clobber`.
