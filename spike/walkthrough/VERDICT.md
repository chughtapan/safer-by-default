# Spike verdict: narrated PR walkthrough pipeline

**Verdict**: **GO** — v2 audio-first architecture validated. Pipeline produces a watchable narrated walkthrough end-to-end with one acceptable rough edge (vhs's variable timescale leaves the last ~7s of video as a held still frame while audio plays out; mitigated cleanly by ffmpeg tpad).

**Wall-clock**: ~75 minutes for v1 + v2 combined.

**Assets**:
- **v2** (audio-first, current): https://github.com/chughtapan/safer-by-default/releases/download/untagged-303de75c9b1a2f846dd7/final.mp4
- v1 (duration-first, reference): https://github.com/chughtapan/safer-by-default/releases/download/untagged-597640ef0b7282bf4809/final.mp4

**PR**: https://github.com/chughtapan/safer-by-default/pull/314
**Branch**: spike/walkthrough-narration

## v1 vs v2

| Aspect | v1 (duration-first) | v2 (audio-first) |
|---|---|---|
| Source of truth for per-scene duration | Planner guess in `(Ns)` | Measured WAV from Cartesia |
| Narration markup | SSML with `<emphasis>` and `<break>` | Plain prose only, no markup |
| Subagent stages | planner + narrator (two LLM calls) | planner only (one LLM call) |
| Scene 2 outcome | atempo'd 1.6x (audibly fast) | natural read, no compression |
| Audio/video alignment per scene | Forced via atempo + padding | Sleeps sized to measured audio |
| Tail handling | `-shortest` truncated final scene narration | `tpad` clones last frame so audio finishes |
| Architecture complexity | 5 stages of negotiation | 5 stages of straight-through pipes |

## GO criteria — scoreboard (v2)

| Criterion | Result | Evidence |
|---|---|---|
| `narrative_plan.md` reads like a story, not a commit log; load-bearing first; ≤7 scenes | ✅ | 6 scenes, leads with the v2 flip, ends with v1-vs-v2 CTA |
| Final MP4 plays, audio aligns to on-screen diff, no dead air >5s | ✅ | Audio plays naturally; per-scene Sleeps sized from measured audio; tpad covers the ~7s tail |
| Cartesia TTS sounds natural enough to watch | ✅ | Plain prose reads cleanly across all scenes; no SSML artifacts |
| GH release asset returns a working public URL; pasted into PR body | ✅ | v1 and v2 draft releases both linked in PR #314 body |
| ASCII title cards render legibly | ✅ | figlet -f slant for intro/outro renders cleanly in 1280×720 |
| Total wall-clock <2h | ✅ | ~75min combined for both runs |

## Headline finding (v1) — time-budget architecture was inverted [SHIPPED in v2]

V1 asked the planner to allocate per-scene seconds, then made both the recorder and the narrator fight to match that guess. The merge stage reconciled with atempo (1.6x on scene 2, audibly fast).

V2 flipped it: narrator runs first, measures actual per-scene WAV durations, recorder sizes vhs Sleeps to match. Drift per scene goes from ±20% to ±0% (in the audio dimension). Atempo deleted. The narrator subagent was deleted entirely — the planner writes the final prose directly because there's no SSML to expand.

## New finding from v2 — vhs render timescale isn't constant

V1 took 88s of Sleep and produced 72.6s of video (1.21x). V2 took 95.8s of Sleep and produced 74.6s (1.28x). Same machine, same vhs version, same theme/font/typing-speed. The ratio depends on Sleep:Type proportion and possibly Chrome scheduling.

scene_planner.ts applies a fixed `VHS_TIMESCALE = 1.21` correction. When the actual ratio drifts to 1.28, video comes in ~7s short. We absorb this with `ffmpeg tpad=stop_mode=clone:stop_duration=15s` + `-shortest` so the final frame holds while audio plays out. Not ideal but acceptable: the call-to-action figlet is on screen during the held tail.

**The real fix** for `/safer:walkthrough`: record each scene as a separate MP4 (one vhs run per scene), concatenate with matched per-scene audio via ffmpeg concat demuxer. Each segment is independently timed, no fudge factor needed, drift impossible. Three-line change to the recorder.

## Other findings to fold into /safer:walkthrough

1. **vhs needs `--no-sandbox`** on standard Linux distros without unprivileged user namespaces. Setup script must wrap the rod-downloaded chromium with a `--no-sandbox --disable-gpu --disable-dev-shm-usage` flag wrapper. Otherwise the recording crashes at Chromium zygote init with no useful error.
2. **bat must run with `BAT_PAGER=""` and `PAGER=cat`** inside the vhs shell. Without it, bat enters less and subsequent Type commands go INTO the pager, silently breaking all later scenes (we lost scenes 3-6 on the first take this way).
3. **Cartesia SSML `<emphasis>` materially extends read time** (~50% on scene 2). Either budget more time for emphasized words, drop emphasis, or accept atempo as the fallback.
4. **vhs Sleep ≠ wall-clock**: rendered MP4 came in at 72.6s for 88s of planned Sleep, a consistent 17.5% underrun. Worth investigating whether vhs's FPS encoding compresses or whether Sleep is interpreted differently in the renderer.
5. **figlet `-f slant` titles** with ≤10 chars render cleanly at FontSize 18 × Width 1280; longer cards (>14 chars) wrap or clip.
6. **Concat-list paths must be absolute** when the list file lives in `/tmp` but the audio sits in cwd. ffmpeg resolves relative paths against the list file's directory.

## Graduation modality

**`/safer:contract`** — scope a real `/safer:walkthrough` skill with the audio-first architecture above, and codify the runtime requirements (Chromium wrapper, bat pager env, SSML→duration policy) as part of `/safer:setup`'s install-time work.

The contract should also decide:
- Pluggable storage backend (GH release default; Supabase / S3 as options)
- Whether to support multi-voice (reviewer + author dialog) — out of scope here but interesting
- Whether the human checkpoint after PLAN is opt-in or default-on
- Whether the skill auto-runs on PR open (CI integration) or stays human-triggered

Per the spike doctrine and the user's autonomy-scope memory: this verdict **stops here**. Do NOT auto-invoke `/safer:contract`. Re-authorization is required.

## Re-runnability (v2)

```bash
cd spike/walkthrough
eval "$(grep '^export CARTESIA_API_KEY=' ~/.bashrc)"
bun run tts.ts narrative_plan.md             # writes audio/scene_N.wav + manifest.json (~30s, ~$0.01)
bun run scene_planner.ts narrative_plan.md manifest.json   # writes walkthrough.tape sized to measured audio
cd ../.. && env -i PATH="$PATH" HOME="$HOME" TERM=xterm-256color vhs spike/walkthrough/walkthrough.tape
mv walkthrough.mp4 spike/walkthrough/walkthrough.mp4
cd spike/walkthrough
ffmpeg -y -i walkthrough.mp4 -i narration.wav -filter_complex "[0:v]tpad=stop_mode=clone:stop_duration=15s[v]" -map "[v]" -map 1:a -c:v libx264 -c:a aac -shortest final.mp4
```

Total cost per re-run: ~3 min compute + one Cartesia call (~$0.01 at current pricing).
