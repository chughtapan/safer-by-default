# Architecture — bot-token routing for safer-publish

**Spec:** https://github.com/chughtapan/safer-by-default/issues/15
**Sub-issue:** https://github.com/chughtapan/safer-by-default/issues/19
**Parent epic:** https://github.com/chughtapan/safer-by-default/issues/14
**Status:** planning (this doc is the architect-tier artifact; no code bodies)

> Iron rule (architect SKILL.md): *interfaces, not implementations*. Every
> function signature below documents the contract. Bodies land in the
> `implement-senior` sub-task that follows this doc.

## Module layout — safer-by-default

Single file: `bin/safer-publish`. No new binaries, no shared library file.
The functions below are bash functions inside `safer-publish`; the binary
stays self-contained. Rationale: (a) there is no other consumer of these
helpers today — premature extraction is row-3 debt per PRINCIPLES; (b) `bin/`
scripts in this repo are flat files, matching the convention.

### Bash function signatures

```bash
# detect_zapbot — filesystem probe for zapbot presence.
#
# Inputs: none. Reads $HOME.
# Outputs: sets global ZAPBOT_DETECTED=1 or ZAPBOT_DETECTED=0. No stdout.
# Exit: always 0 (detection is informational).
# Invariant: cannot wrongly assert "installed" when it isn't
#            (invariant 7 of spec §4). Checks both ~/.zapbot/.env and
#            ~/.zapbot/config.json; either match counts.
detect_zapbot

# resolve_bridge_url — same ladder as zapbot's bin/zapbot-publish.sh:11-20
#                      (cross-repo reference; that file lives in the zapbot
#                      codebase, not in this repo).
#
# Inputs: none. Reads cwd/agent-orchestrator.yaml, $ZAPBOT_BRIDGE_URL.
# Outputs: echoes the resolved URL on stdout. Never empty on a 0 exit.
# Exit: 0 if resolved (default http://localhost:3000 is a resolved value);
#       non-zero only if the yaml exists but is malformed.
resolve_bridge_url

# fetch_broker_token — GET $BRIDGE_URL/api/tokens/installation with Bearer auth.
#
# Inputs: $1 = bridge URL. Reads $ZAPBOT_API_KEY from env.
# Outputs on stdout: the bare token string (no JSON, no newlines).
# Outputs on stderr: single structured error line on non-2xx. Format:
#   "safer-publish: broker <condition> at <URL>"
#   where <condition> is one of: connection_refused, unauthorized,
#   app_not_configured, server_error, schema_invalid.
# Exit codes:
#   0  — 2xx + schema-valid body
#   10 — connection refused / DNS / TCP
#   11 — 401
#   12 — 409 app_not_configured
#   13 — 5xx
#   14 — schema-invalid 2xx body
# Invariant: never writes the token to disk. curl -s -o -; pipe through
#            jq -r .token; no tempfile.
fetch_broker_token

# verify_attribution — post-hoc check that a created resource is authored by
# a GitHub App installation (user.type == "Bot").
#
# Inputs: $1 = resource URL returned by `gh issue create` / `gh ... comment`.
# Outputs on stdout: nothing on success.
# Outputs on stderr: one-line error with the resource URL on mismatch.
# Exit: 0 on user.type == "Bot"; non-zero otherwise.
# Invariant: report-only. Never deletes the artifact (open-question Q6 default).
verify_attribution

# resolve_identity_mode — decide the identity path for this invocation.
#
# Inputs: reads ZAPBOT_DETECTED (set by detect_zapbot), $SAFER_ATTRIBUTE_TO_USER
#         (from --attribute-to-user), $SAFER_ALLOW_PAT_FALLBACK
#         (from --allow-pat-fallback). Decision is deterministic in those
#         three bits plus the broker outcome; documented as a state table
#         in the data-flow section below.
# Outputs: echoes one of: "bot", "user", "user-fallback". No stderr unless
#          the state is genuinely ambiguous (which it never is by construction;
#          every combination maps to exactly one mode).
# Exit: 0 on a resolved mode; non-zero is a bug (architect's stop-rule).
resolve_identity_mode

# handle_fallback_flags — parse and validate the two new per-call flags.
#
# Inputs: reads $@ from the caller. Removes the flags from the positional
#         args after consumption so the rest of safer-publish's existing
#         option parser is unaffected.
# Outputs: no stdout. Sets SAFER_ALLOW_PAT_FALLBACK, SAFER_ATTRIBUTE_TO_USER.
# Exit: non-zero if both flags are set together (documented error: the
#       combination is ill-defined — --attribute-to-user already bypasses
#       the broker, so --allow-pat-fallback is redundant and its
#       co-presence is a caller bug).
# Invariant: flags are per-invocation; no env var reads, no config file reads
#            (open-question Q4 default (a)).
handle_fallback_flags

# run_gh_as_bot — invoke the existing `gh ...` path with GH_TOKEN set,
# GITHUB_TOKEN unset, for a single call, then restore.
#
# Inputs: $1 = token; remaining args = gh subcommand+flags (the same array
#         safer-publish currently builds).
# Outputs: stdout/stderr of the gh call, unchanged.
# Exit: exit status of the gh call.
# Invariant 4 of spec §4: outer env neutralized. Implementation uses
#   `env -u GITHUB_TOKEN GH_TOKEN="$token" gh ...` so the neutralization is
#   bounded to the child process; no parent-env leakage.
run_gh_as_bot
```

### Binary shape after the changes

```
bin/safer-publish
  ├── existing arg parser                 (unchanged)
  ├── handle_fallback_flags  <— NEW       (consumes --allow-pat-fallback,
  │                                         --attribute-to-user; removes
  │                                         them from "$@")
  ├── detect_zapbot           <— NEW
  ├── resolve_identity_mode   <— NEW
  │
  ├── case "$KIND" in ...                 (existing gh dispatch, now
  │     (wrapped per mode)                 gated by resolve_identity_mode)
  │
  ├── verify_attribution      <— NEW      (only in bot mode)
  └── existing error reporting            (unchanged)
```

No changes to the `--kind` grammar, the `--parent` prepend logic, the label
argument shape, or the body-file pathway. The diff to `safer-publish` is
purely additive above and gates around the existing `gh` dispatch.

## Module layout — zapbot

Single new file: `src/http/routes/installation-token.ts`.

Rationale for `src/http/routes/` (the path pre-exists in the tree but is
currently empty): the bridge's fetch handler in `bin/webhook-bridge.ts`
switches on `pathname` against inline handler bodies today. The new endpoint
is the first that warrants extraction (it has auth middleware + schema +
error discrimination that don't fit inline). Extracting it to
`src/http/routes/` establishes the convention; the existing inline routes
stay inline until they each justify the move (no preemptive extraction —
that is row-3 debt).

Interface stubs live on branch `arch/token-broker` in the zapbot repo:

- `src/http/routes/installation-token.ts` — full TypeScript interface (see
  zapbot PR for contents). Exports:
  - `handleInstallationTokenRequest(req, deps): Promise<InstallationTokenStatus>`
  - `installationTokenRoute(deps): (req) => Promise<Response>`
  - `verifyBearer(authHeader, expected): null | UnauthorizedError`
  - Branded types: `InstallationToken`, `Iso8601`.
  - Discriminated union: `InstallationTokenError`.

Reuse, per spec invariant 2: `deps.mintToken` is `getInstallationToken` from
zapbot's `src/github/client.ts:200-218` (cross-repo reference; that file
lives in the zapbot codebase, not in this repo) — the existing
`_authInstance` singleton. No new mint path. The route never touches
`createAppAuth` directly.

## Data flow

### Happy path (zapbot detected, bot mode)

```
skill
  │  (exec bin/safer-publish --kind issue --title ... --body-file ...)
  ▼
safer-publish
  ├── handle_fallback_flags    (no flags set)
  ├── detect_zapbot            → ZAPBOT_DETECTED=1
  ├── resolve_identity_mode    → "bot"
  ├── resolve_bridge_url       → http://localhost:3000
  ├── fetch_broker_token ───────────────────┐
  │                                         │
  │                                         ▼
  │                                  bridge (Bun.serve)
  │                                    │
  │                                    ▼
  │                          installationTokenRoute
  │                            ├── verifyBearer (ZAPBOT_API_KEY)
  │                            ▼
  │                          getInstallationToken()
  │                            (existing _authInstance singleton,
  │                             in zapbot's src/github/client.ts:200-218 —
  │                             cross-repo, lives in the zapbot codebase)
  │                            ▼
  │                          @octokit/auth-app mints / returns cached
  │                            ▼
  │                          { token, expires_at }  ─── 200
  │                                         │
  │  <──────────────────────────────────────┘
  ├── run_gh_as_bot            (env -u GITHUB_TOKEN GH_TOKEN=<token> gh ...)
  │   └── gh issue create ... → https://github.com/.../issues/N
  ├── verify_attribution       (gh api .../issues/N --jq .user.type == "Bot")
  ▼
exit 0 (resource URL on stdout)
```

### Fallback branches

```
fetch_broker_token fails ─────────────────────────────────────────────┐
  │                                                                   │
  ├── SAFER_ALLOW_PAT_FALLBACK=1                                       │
  │     ├── stderr warn: "broker <condition> at <URL>; falling back"  │
  │     └── run_gh_as_user (no GH_TOKEN export; gh uses stored auth)  │
  │                                                                   │
  └── SAFER_ALLOW_PAT_FALLBACK=0 (default)                             │
        └── exit non-zero with structured error (see §error shape)    │
                                                                      │
SAFER_ATTRIBUTE_TO_USER=1 (set on CLI) ───────────────────────────────┤
  ├── skip detect_zapbot / broker entirely                            │
  ├── run_gh_as_user                                                  │
  └── skip verify_attribution                                         │
                                                                      │
ZAPBOT_DETECTED=0 ────────────────────────────────────────────────────┘
  ├── skip broker
  ├── run_gh_as_user (silent; this is the pre-existing behavior)
  └── skip verify_attribution
```

### Identity-mode decision table

Inputs: `D = ZAPBOT_DETECTED`, `U = --attribute-to-user`, `F = --allow-pat-fallback`,
`B = broker outcome (hit | miss)`.

| D | U | F | B    | mode            | verify_attribution |
|---|---|---|------|-----------------|--------------------|
| 0 | 0 | 0 | n/a  | user (silent)   | no                 |
| 0 | 0 | 1 | n/a  | user (silent)   | no                 |
| 0 | 1 | * | n/a  | user (silent)   | no                 |
| 1 | 1 | * | n/a  | user            | no                 |
| 1 | 0 | 0 | hit  | bot             | yes                |
| 1 | 0 | 0 | miss | **exit non-0**  | —                  |
| 1 | 0 | 1 | hit  | bot             | yes                |
| 1 | 0 | 1 | miss | user-fallback (warn) | no            |

Every row is handled. The table is exhaustive over (D, U, F, B) with
`F` irrelevant when `B=hit` (collapsed above).

## Errors

### Bridge side (TypeScript, discriminated union)

```ts
type InstallationTokenError =
  | { error: "unauthorized";        message: string }
  | { error: "app_not_configured";  message: string }
  | { error: "internal_error";      message: string };
```

HTTP status mapping is exhaustive via `InstallationTokenStatus` (see stub
file). No `Promise<never>`, no raw `throw` in the public surface —
principle 3 of PRINCIPLES.md.

### safer-publish side (exit codes + stderr shape)

| Code | Condition               | Stderr line                                                     |
|------|-------------------------|-----------------------------------------------------------------|
| 0    | success                 | —                                                               |
| 10   | bridge TCP fail         | `safer-publish: broker connection_refused at <URL>`             |
| 11   | bridge 401              | `safer-publish: broker unauthorized at <URL>`                   |
| 12   | bridge 409              | `safer-publish: broker app_not_configured at <URL>`             |
| 13   | bridge 5xx              | `safer-publish: broker server_error at <URL>`                   |
| 14   | bridge schema-invalid   | `safer-publish: broker schema_invalid at <URL>`                 |
| 20   | attribution mismatch    | `safer-publish: attribution verify failed <RESOURCE_URL>`       |
| 21   | gh call failed (bot)    | `safer-publish: gh failed under bot mode` (plus gh's own stderr)|
| 22   | flags conflict          | `safer-publish: --allow-pat-fallback and --attribute-to-user are mutually exclusive` |

Multi-line error UX for bridge-unreachable (open question Q2, default (b)):

```
safer-publish: cannot reach zapbot token broker.

  Bridge:    http://localhost:3000
  Probe:     connection_refused
  Detected:  ~/.zapbot/.env

  Hint: re-run with --allow-pat-fallback to use your gh auth,
        or start the bridge: ~/.zapbot/start.sh
```

`app_not_configured` uses the same shape with `Probe:` = `409 app_not_configured`
and the hint pointing at zapbot's setup docs.

## Migration order (open question Q5)

**Decision: bridge endpoint ships first, in zapbot.** Rationale below.

1. **zapbot PR** (branch `arch/token-broker` → follow-on implement PR):
   - Lands `src/http/routes/installation-token.ts` with real bodies.
   - Wires `installationTokenRoute(deps)` into `bin/webhook-bridge.ts`'s
     pathname switch.
   - Behind `ZAPBOT_FEATURE_TOKEN_BROKER=1` env flag. Flag default `0` keeps
     behavior identical pre-rollout. Once safer-publish ships and a release
     cycle passes without incident, flag is deleted in a follow-up (one-line
     PR, per PRINCIPLES §back-compat corollary — no long-lived flag).
   - Acceptance: `curl -H "Authorization: Bearer $ZAPBOT_API_KEY" $BRIDGE_URL/api/tokens/installation` returns `{token, expires_at}` when the App is configured, 409 otherwise.

2. **safer-by-default PR** (branch `arch/bot-token-routing` → follow-on implement PR):
   - Adds the bash functions above to `bin/safer-publish`.
   - Assumes the endpoint exists (spec invariant: zapbot detected ⇒ broker
     expected). No feature-detection probe on the safer-publish side.
   - If a safer-publish built against this ships and hits an older zapbot
     without the endpoint, the response is 404, which maps to `server_error`
     (code 13) with a message that includes the URL — operator-recoverable.

Why this order: one-way dependency direction (safer-publish depends on
bridge; bridge does not depend on safer-publish). Smaller, sequential PRs.
Clean rollout under the feature flag. Rejected alternatives: coordinated
single-commit cross-repo PR (cannot atomically deploy two repos), or
safer-publish first with feature-detection (adds a 404 branch to
safer-publish that would never fire after the bridge ships — row-3 debt).

## Blast radius — existing callers of safer-publish

Grep: `grep -rE "safer-publish" /home/tapanc/safer-by-default/skills/` →
9 skills touch it (architect, dogfood, investigate, orchestrate, research,
review-senior, spec, spike, verify). Classification per call site:

| Skill | Call shape | Class | Action |
|---|---|---|---|
| architect | `safer-publish --kind comment` / `--kind issue` | **works unchanged** | none |
| dogfood | read-only reference in docs | **works unchanged** | none |
| investigate | `safer-publish --kind comment` | **works unchanged** | none |
| orchestrate | `safer-publish --kind epic` / `issue` | **works unchanged** | none |
| research | `safer-publish --kind comment --issue` | **works unchanged** | none |
| review-senior | `safer-publish --kind pr-comment` | **works unchanged** | none |
| spec | `safer-publish --kind comment` | **works unchanged** | none |
| spike | `safer-publish --kind issue` | **works unchanged** | none |
| verify | `safer-publish --kind pr-comment` | **works unchanged** | none |

No skill today passes `--attribute-to-user` or `--allow-pat-fallback` — the
flags are additive, default-off for the former and default-off for the latter.
Existing invocations transparently gain bot attribution when zapbot is
installed and the bridge is reachable. Skill authors do not need to update
call sites.

**New-flag recommendation:** none. Zero skills have a reason to request user
attribution. If one surfaces later (e.g. a skill posting on behalf of a
human-authored decision), the flag is already shipped.

## Answered open questions (from spec §7)

**Q1 — Bootstrap UX (spec default (a) confirmed).**
Hard fail every time; no first-run grace period. Error shape is the multi-line
block under §Errors above. A separable `safer-publish --doctor` is out of
scope for this design (not required by any acceptance criterion); if wanted,
it is a follow-up feature, not a change to strict-mode.

**Q2 — Bridge-unreachable message text.** Multi-line checklist (spec default
(b) confirmed). Exact text in the §Errors section. Field labels are fixed:
`Bridge:`, `Probe:`, `Detected:`, `Hint:`. JSON envelope is deferred; not
requested by any current caller.

**Q3 — `gh auth` precondition.** No precheck (spec default (a) confirmed).
A failing `gh` call surfaces its own error; adding `gh auth status` per
invocation is a round-trip tax for marginal benefit. Revisit only if a real
user hits a confusing `gh` failure in PAT-fallback mode.

**Q4 — `--allow-pat-fallback` global default.** Flag-only (spec default (a)
confirmed). No env var, no config file. Reason: research round 5 rejected
env-driven identity toggles; a YAML-driven default is the same hazard with
a longer read path. Users wanting always-fallback wrap `safer-publish` in
their own shim — explicit, local, auditable.

**Q5 — Cross-repo coordination.** Endpoint-first with feature flag (spec
default (a) confirmed). See §Migration order for the rollout shape.

**Q6 — Unwind on verify failure.** Report-only (spec default (a) confirmed).
`verify_attribution` prints the resource URL and exits non-zero; operator
decides whether to delete. Auto-delete has worse blast radius: an issue that
someone has already cross-linked cannot be undeleted cleanly, and the
mismatch itself is a sign something upstream is wrong (outer env leaked,
wrong token returned) — a noisy error is the correct surface.

### Architect-flagged (non-blocking from spec §7)

- **`expires_at` usage in safer-publish:** unused by `fetch_broker_token`.
  The field is parsed (to validate schema presence) and discarded. The
  response shape keeps it for future consumers; caller-side cache is
  still invariant 1.
- **Endpoint path:** `/api/tokens/installation` (as specified). Not renamed.
- **Schema validation:**
  - Bridge: inline TypeScript discriminated union; no Zod dependency to
    introduce a new package just for one endpoint (weigh against
    Principle 2; single endpoint with three response shapes is below the
    threshold that demands a schema library. Architect may revisit when
    a second endpoint lands).
  - safer-publish: `jq -e '.token | type == "string"'` guard on the
    response body. `schema_invalid` (exit 14) fires if the guard fails.

## Dependencies

| Library | Version | License | Why |
|---|---|---|---|
| `@octokit/auth-app` | (already pinned in zapbot) | MIT | Existing dependency. Handler consumes the already-instantiated `_authInstance` via `getInstallationToken`. No version bump. |
| `jq` | (system) | MIT | Already assumed by `zapbot-publish.sh`. Used in safer-publish for broker response parsing. |
| `curl` | (system) | MIT/X | Already assumed by gh / zapbot shell tooling. |

No new packages in either repo's `package.json` / `package-install`. This is
per architect SKILL.md: library installs land in `implement-*`, not here; but
there is nothing to install because all dependencies are pre-existing.

## Traceability

Mapping each acceptance criterion of spec #15 to the module or function that
satisfies it.

| Spec AC | Satisfied by |
|---|---|
| Endpoint exists, Bearer-auth, returns `{token, expires_at}` | `installationTokenRoute` + `handleInstallationTokenRequest` + `verifyBearer` in zapbot |
| 409 `app_not_configured` when null | `handleInstallationTokenRequest` (null branch → `InstallationTokenError { error: "app_not_configured" }`) |
| Detection via `~/.zapbot/.env` OR `~/.zapbot/config.json` | `detect_zapbot` |
| Bot-mode export / unset / run / unset | `run_gh_as_bot` + `resolve_identity_mode` "bot" arm |
| Strict-mode hard failure shape | `fetch_broker_token` exit codes 10-14 + `resolve_identity_mode` gating |
| `--allow-pat-fallback` warns and proceeds | `handle_fallback_flags` + `resolve_identity_mode` "user-fallback" arm |
| `--attribute-to-user` skips broker and verify | `handle_fallback_flags` + `resolve_identity_mode` "user" arm |
| Post-hoc `gh api .user.type == "Bot"` assertion | `verify_attribution` |
| No token written to disk | Handler: in-memory only. safer-publish: `curl -s` piped through `jq -r` into a bash variable; never redirected to a file. |
| Zapbot not detected → silent gh-default | `resolve_identity_mode` D=0 rows of table |

Every criterion maps to a named, signature-documented function.

## Open questions

None blocking. All six spec-level open questions are answered above per the
spec's recommended defaults. The three architect-flagged items are resolved
inline (expires_at, path, schema library). If the user disagrees with any of
the six defaults, they override in a comment on #19 before implement-senior
kickoff; nothing in this design is load-bearing on a specific default such
that flipping one would require a re-design (the table in §Data flow is
parametric on the flag bits, and flipping the default of Q4 is a one-line
change to `handle_fallback_flags`).

## Confidence

HIGH — every interface is derivable from the spec's acceptance criteria;
every data-flow arrow corresponds to a function call across two named
modules; every failure branch is enumerated with its exit code. The zapbot
mint path (`_authInstance` singleton) is read-verified in zapbot's
`src/github/client.ts:200-218` (cross-repo; that path lives in the zapbot
codebase, not in this repo). The bridge fetch-handler pattern is
read-verified in zapbot's `test/bridge-endpoints.test.ts` (also cross-repo;
inline pathname switch; Bun.serve). The bridge-URL ladder is read-verified
in zapbot's `bin/zapbot-publish.sh:11-20` (cross-repo). No unresolved spec
ambiguity.

---

**Status marker:** `DONE`
