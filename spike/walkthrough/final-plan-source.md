# brief v1 — ship-ready plan (survived 4 review rounds)

THE FINAL SHAPE — 5 packages, Effect end to end:

  wire      codec + schema + branded types (keeps the browser bundle lean)
  pipeline  parse -> tts -> capture -> scrub -> envelope -> emit
  player    decoder -> audio-sync -> shell
  cli       the brief binary (@effect/cli)
  eval      prompt-quality harness

  planner = the AGENT (a /brief skill authors the transcript)
  code    = a thin parser, no scene-kind schema

THE SECURITY STORY (the part that took the work):

  the threat: brief runs git against the repo it narrates
  3 review rounds, each found a new exec vector:
    shell metachars -> argv0 -> git flags -> git repo-config
  codex (cross-model) caught the class no single model did
  YOUR call: narrow v1 to TRUSTED / own repos
    -> closed the cycle by re-scope, not more code
    -> codex validated: same trust class as editors, LSPs, git itself

DEFERRED BY YOUR DECISION (not blockers):

  Safari / iOS / Android device test ... post-ship (rAF/AAC fallback ready)
  untrusted third-party PR hardening .... roadmap (v1 non-goal)

WHAT HELD UP UNDER FIRE:

  capture fidelity (no-PTY in-process) ... spike #9: GO, v5 quality
  Effect surface + 5-package boundary .... validated across 4 rounds
  ~80-105 min of your time / ~8.25h CC ... inside the Day-10 budget
