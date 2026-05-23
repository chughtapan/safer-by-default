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

Then call the planning subagent (Agent tool, `subagent_type=general-purpose`) with `prompts/planner.md` as the system prompt and the evidence files as input. Save the returned markdown to `narrative_plan.md`.

**Human checkpoint**: show `narrative_plan.md` to the user via AskUserQuestion. Options: ship as-is / let me edit it / abort and re-prompt. Default flow pauses here.

### Stage 2 — RECORD (markdown plan → .tape → mp4)

```bash
bun run scene_planner.ts narrative_plan.md          # writes walkthrough.tape + manifest.json
env -i PATH="$PATH" HOME="$HOME" TERM=xterm-256color vhs walkthrough.tape
# vhs reads the `Output` directive inside the tape and writes walkthrough.mp4
```

Smoke test before the real run:

```bash
bun run scene_planner.ts --dry-run narrative_plan.md   # prints tape, no file write
```

### Stage 3 — NARRATE (subagent → SSML → Cartesia → wav)

Voice: defaults to Cartesia's "Barbershop Man" (`a0e99841-438c-4a64-b679-ae501e7d6091`). Override by exporting `CARTESIA_VOICE_ID` from any voice on https://play.cartesia.ai/voices.

Call the narration subagent (Agent tool) with `prompts/narrator.md`, `narrative_plan.md`, and `walkthrough.tape` as inputs. Save returned SSML to `transcript.ssml`.

Then synthesize:

```bash
bun run tts.ts transcript.ssml manifest.json      # writes audio/scene_N.wav and narration.wav (concatenated)
```

Smoke test:

```bash
bun run tts.ts --text "hello from the spike" --out /tmp/hi.wav
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
| `prompts/narrator.md` | 3 | Narration subagent system prompt |
| `evidence/` | 1 | Diff, commits, reviews captured for the planner |
| `narrative_plan.md` | 1 → 2,3 | Structured story; subagent output; reviewable artifact |
| `scene_planner.ts` | 2 | Markdown plan → vhs `.tape` + `manifest.json` |
| `walkthrough.tape` | 2 → vhs | Generated tape script |
| `manifest.json` | 2 → 3 | Per-scene durations for audio padding |
| `walkthrough.mp4` | 2 → 4 | vhs output, silent |
| `transcript.ssml` | 3 | Narration SSML with `<!-- scene: N -->` markers |
| `tts.ts` | 3 | Cartesia WebSocket TTS |
| `audio/scene_N.wav` | 3 | Per-scene narration |
| `narration.wav` | 3 → 4 | Concatenated narration |
| `final.mp4` | 4 → 5 | Merged video |
| `VERDICT.md` | 6 | GO/MIXED/NO-GO with evidence |

## Re-running

`evidence/` and `narrative_plan.md` are cheap to keep. `audio/`, `*.wav`, `*.mp4`, `*.tape` are regenerated and gitignored. Same-sha re-runs reuse the existing GH release via `--clobber`.
