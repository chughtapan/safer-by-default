# Spike verdict: narrated PR walkthrough pipeline

**Verdict**: **GO WITH REDESIGN** (between GO and MIXED — pipeline works end-to-end and the asset shipped, but the time-budget architecture is inverted and the first-run scene 2 had to be atempo-compressed 1.6x to hold sync)

**Wall-clock**: ~70 minutes (well inside the 2h budget)

**Asset**: https://github.com/chughtapan/safer-by-default/releases/download/untagged-597640ef0b7282bf4809/final.mp4
**PR**: https://github.com/chughtapan/safer-by-default/pull/314
**Branch**: spike/walkthrough-narration @ 933eaf1

## GO criteria — scoreboard

| Criterion | Result | Evidence |
|---|---|---|
| `narrative_plan.md` reads like a story, not a commit log; load-bearing first; ≤7 scenes | ✅ | 6 scenes, leads with pipeline architecture, ends with WATCH ME CTA |
| Final MP4 plays, audio aligns to on-screen diff, no dead air >5s | ⚠ partial | Audio plays cleanly, but scene 2 audio is atempo'd 1.6x and audible as "fast" |
| Cartesia TTS sounds natural enough to watch | ✅ | Default voice "Barbershop Man" reads cleanly outside scene 2's atempo |
| GH release asset returns a working public URL; pasted into PR body | ✅ | Draft release + asset URL in PR #314 body |
| ASCII title cards render legibly | ✅ | figlet -f slant for intro/outro renders cleanly in 1280×720 |
| Total wall-clock <2h | ✅ | ~70min |

## Headline finding — time-budget architecture is inverted

The current pipeline asks the **planner** to allocate per-scene seconds, then the **recorder** uses those seconds for vhs `Sleep`, then the **narrator** is told "fit your prose into N seconds." This is backwards:

- vhs `Sleep` is trivial to set to any value, and the actual rendered duration drifts ~17% from what `Sleep` advertises (88s planned → 72.6s rendered). Video duration is a known unknown until vhs runs.
- TTS duration is also a known unknown until Cartesia runs. SSML emphases add ~50% to scene 2's read time.
- Making BOTH durations downstream of an upstream guess means the two downstreams disagree, and the merge stage has to reconcile via lossy techniques (atempo, truncation, padding).

**Correct shape**: narration is the harder thing to time precisely; record AROUND it.

1. **PLAN**: planner outputs scenes with `action` + `narration` only — **no `(Ns)` duration**.
2. **NARRATE**: TTS each scene's narration first; measure actual per-scene WAV duration with ffprobe.
3. **RECORD**: scene_planner sizes each vhs `Sleep` to `wavDuration + 1s breathing room`. vhs records exactly the right length.
4. **MERGE**: trivial — both streams have matched length per scene.

Drift goes to zero. atempo compression goes away. The pipeline becomes 5 stages of straightforward functions instead of 5 stages of negotiation.

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

## Re-runnability

```bash
cd spike/walkthrough
# evidence/ already captured from the original run
bun run scene_planner.ts narrative_plan.md      # regenerates tape + manifest
env -i PATH="$PATH" HOME="$HOME" TERM=xterm-256color vhs walkthrough.tape  # re-records (≈90s)
eval "$(grep '^export CARTESIA_API_KEY=' ~/.bashrc)" && bun run tts.ts transcript.ssml manifest.json
ffmpeg -y -i walkthrough.mp4 -i narration.wav -vf "tpad=stop_mode=clone:stop_duration=2s" -c:v libx264 -c:a aac -shortest final.mp4
```

Total cost per re-run: ~3 min of compute + one Cartesia call (~$0.01 at current pricing).
