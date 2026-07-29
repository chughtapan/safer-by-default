# brief — architect plan (the build shape)

FIVE PACKAGES, Effect end to end:

  core    pipeline engine   planner -> tts -> capture -> scrub -> envelope
  player  static browser    decoder -> audio-sync -> shell
  emit    output artifacts  local-html (primary) | fragment (secondary)
  cli     the brief binary  @effect/cli commands -> pipeline -> emit
  eval    prompt harness    reference walkthroughs -> manual pass/fail

DATA FLOW  (brief <file.md>, the dogfood path):

  artifact
    -> planner.plan       NarrativePlan         subagent + schema
    -> tts.synthesize     mp3 + duration         Cartesia sonic-3
    -> capture.capture    asciinema cast         per-scene "m" markers
    -> scrub              secret-pattern warn    Invariant 4
    -> encodeEnvelope     [len|manifest|cast|audio]
    -> emit local-html    self-contained brief.html
    -> open file://       player boots, audio synced to the cast

TYPE DISCIPLINE  (Effect, not Zod):

  every fallible fn ....  Effect<A, E, R>
  errors ...............  Data.TaggedError, caller exhausts _tag
  boundaries ...........  Schema.decodeUnknown
  branded primitives ...  Schema.brand (SceneId, Seconds, VoiceId)
  IO adapters ..........  Context.Tag services + Live Layers (real-dep tests)

DEV-INFRA  (brief dogfoods the safer-* stack):

  eslint-plugin-agent-code-guard   23-rule architecture lint floor
  architecture LSP                 live diagnostics, hrefs -> PRINCIPLES.md
  safer-spec living-spec           MODULE.md + .safer-spec, validate gates CI

SPIKE-LOCKED DECISIONS:

  audio sync .....  native asciinema-player audioUrl (12ms) + rAF fallback
  TTS model ......  sonic-3 (sonic-2 dies June 1)
  fragment codec .  gzip via native DecompressionStream (no zstd-wasm)
  share artifact .  --local HTML primary; hosted link NOT clickable markdown

STILL YOUR CALL  (the park):

  Q0  real-device Safari / iOS / Android audio-sync gate   blocks implement
  Q1  five packages vs the architect five-module budget    nod needed
  Q3  core effect/Schema vs standalone @effect/schema      used core
