# Spike verdict: narrated PR walkthrough pipeline

**Verdict**: **GO** — v3 visual-polish redesign shipped. Pipeline mixes slide-style (gum) and terminal-style (bat + delta) scenes with crossfade transitions, line highlighting on code excerpts, and a persistent footer. Narration structure follows the Even-a-Geek-Can-Speak framework (Hook → Thesis → Evidence → Call to action).

**Wall-clock**: ~135 minutes total across v1, v2, v3.

**Assets**:
- **v3** (visual polish, current): https://github.com/chughtapan/safer-by-default/releases/download/untagged-d1f8aadce2f7e28c941c/final.mp4
- v2 (audio-first): https://github.com/chughtapan/safer-by-default/releases/download/untagged-303de75c9b1a2f846dd7/final.mp4
- v1 (duration-first): https://github.com/chughtapan/safer-by-default/releases/download/untagged-597640ef0b7282bf4809/final.mp4

**PR**: https://github.com/chughtapan/safer-by-default/pull/314
**Branch**: spike/walkthrough-narration

## v1 vs v2 vs v3

| Aspect | v1 (duration-first) | v2 (audio-first) | v3 (per-scene segments) |
|---|---|---|---|
| Source of truth for per-scene duration | Planner guess in `(Ns)` | Measured WAV from Cartesia | Measured WAV from Cartesia |
| Narration markup | SSML with `<emphasis>` and `<break>` | Plain prose only | Plain prose only |
| Subagent stages | planner + narrator | planner only | planner only |
| Narration framework | none | none | Even-a-Geek-Can-Speak (Hook→Thesis→Evidence→CTA) |
| Total narration length | ~72s | ~80s | ~120s (more depth per scene) |
| Recording shape | one monolithic vhs run | one monolithic vhs run | per-scene vhs runs (one per scene type) |
| Scene types | only code+log+figlet | only code+log+figlet | title (gum slide), pr-card (gh+gum), log, code (highlighted), diff (delta), outro (gum slide) |
| Line highlighting on code scenes | no | no | yes (`bat --highlight-line`) |
| Title cards | figlet ASCII | figlet ASCII | gum styled centered box (double border, accent color) |
| Transitions between scenes | hard cuts | hard cuts | 0.4s crossfade (`ffmpeg xfade`) |
| Persistent footer | no | no | yes (PR # / branch / spike name via `drawtext`) |
| Window chrome | basic | basic | macOS-style WindowBar Colorful, BorderRadius 12, MarginFill slate |
| Canvas size | 1280×720 | 1280×720 | 1920×1080 |
| Scene 2 outcome | atempo'd 1.6x (audibly fast) | natural read | natural read |
| Tail handling | `-shortest` truncated narration | `tpad` clones last frame so audio finishes | per-scene `tpad` per segment, audio plays fully |

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

## New finding from v2 — vhs render timescale isn't constant [PARTIALLY SHIPPED in v3]

V1 took 88s of Sleep and produced 72.6s of video (1.21x). V2 took 95.8s of Sleep and produced 74.6s (1.28x). Same machine, same vhs version, same theme/font/typing-speed.

V3 ships the per-scene segmentation fix called out above (`render_scenes.ts`). Each scene is its own vhs invocation, ffprobed independently, padded to its audio length in `composite.ts`. Drift across scenes is impossible.

**New caveat at v3**: per-scene render at 1920×1080 lands at roughly *50%* of the requested Sleep duration — significantly worse than the 80% v1/v2 saw at 1280×720. The composite stage absorbs this by padding each segment with clone-last-frame to match audio. Body scenes therefore show ~10s of held frame while the narrator finishes talking about the code. Functional, but not invisible.

**The next fix** for the real `/safer:walkthrough`: either drop back to 1280×720 (the v1/v2 size where the timescale was closer to 1.0x) or run a per-scene timescale probe before recording (record a 5s test scene, measure actual duration, adapt). Both options are in scope for the contract.

## New findings from v3 — visual polish trade-offs

1. **gum slides need pre-rendering**, not in-band typing. First attempt typed the full `gum style ...` command in the tape — viewer saw the 200-character invocation as the slide loaded. Fix: scene_planner.ts runs gum at planner time, writes the styled output to `segments/scene_N_slide.txt`, and the tape just `cat`s it. Visible command shrinks from "gum style --align center --border double ..." to "cat spike/walkthrough/segments/scene_N_slide.txt". Lesson for the real skill: anything visual that doesn't need to *demonstrate the command* should be pre-rendered, not typed live.

2. **ffmpeg xfade needs constant frame rate** — tpad inside the complex filter graph produces variable-rate output that xfade rejects with "current rate of 1/0 is invalid". Single-pass `[i:v]tpad,fps=30,setpts=PTS-STARTPTS` didn't fix it. Working solution: two-pass composite — first ffmpeg call per-segment to pad + force `-r 30 -fps_mode cfr`, second call to chain `xfade` across the now-CFR padded segments. Slower (~2x per render) but reliable.

3. **bat `--highlight-line A:B` is the right primitive** for "look here" emphasis. It dims surrounding lines and brightens the target range. No additional ffmpeg overlay needed — the bat output already encodes the visual emphasis.

4. **Persistent footer via `drawtext`** works but is purely additive: `drawtext=text='PR #N · branch · spike':fontsize=20:fontcolor=white@0.8:y=h-36:box=1:boxcolor=black@0.6`. The boxborderw padding matters — without it the text crowds the background box.

5. **Narration framework changed outputs materially**. v2 had 80s of summary narration; v3 has 120s of structured narration following Hook → Thesis → Evidence → CTA. The Evidence scenes (50-80 words each) actually *explain trade-offs* instead of just describing code surfaces. Worth keeping as a default in the real skill.

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
