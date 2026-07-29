# Step 4c: Wire the living-spec layer (optional)

The living-spec layer is the per-folder `MODULE.md` + `.safer-spec/<slug>.json` sidecar codemod (`@chughtapan/safer-spec-development`), validated by `safer-spec validate`, whose typed exit codes route HOLD verdicts through `/safer:verify` (PRINCIPLES.md Part 2, "Living-spec is the ratchet's machine-readable surface"). As of v0.4.0 the codemod is published to npm, so this step installs it from the registry and applies to **any** TypeScript + vitest project. The v0.2.0/v0.3.0 dogfood-only pre-flight halt and the `link:`-protocol install against the vendored submodule are gone.

**This step is optional and never aborts setup.** It applies only to TypeScript projects that test with vitest (the layer wires a vitest reporter and a per-folder `MODULE.md` gate). If the project is not TS+vitest, or the install fails, the step records a skip and the lint floor and strict flags from the other steps still stand. Nothing here exits the skill.

**Applicability check (skip, never exit).**

```bash
SPEC_LAYER_STATUS=""
SPEC_LAYER_SKIP_REASON=""
if [ ! -f tsconfig.json ]; then
  SPEC_LAYER_SKIP_REASON="not a TypeScript project (no tsconfig.json)"
elif [ ! -f vitest.config.ts ] && [ ! -f vitest.config.js ] && [ ! -f vitest.config.mts ]; then
  SPEC_LAYER_SKIP_REASON="the living-spec reporter targets vitest, and no vitest.config.{ts,js,mts} is present"
fi
if [ -n "$SPEC_LAYER_SKIP_REASON" ]; then
  echo "Step 4c: living-spec layer skipped — $SPEC_LAYER_SKIP_REASON."
  echo "  (The lint floor and strict flags from the other steps still apply.)"
  SPEC_LAYER_STATUS="skipped ($SPEC_LAYER_SKIP_REASON)"
fi
```

Run every block below **only when `$SPEC_LAYER_SKIP_REASON` is empty**. Each block re-checks the flag so a mid-step failure (install or doctor) cleanly skips the rest without aborting setup.

**Install the codemod from npm.** Pinned to the `~0.2.0` tilde range (Spec Invariant 3: codemod and plugin version-lock in pairs). Uses the package manager detected in Step 1; idempotent — skips when the dependency is already declared.

```bash
if [ -z "$SPEC_LAYER_SKIP_REASON" ]; then
  HAS_CODEMOD=$(node -e '
    const pkg = require("./package.json");
    const dep = (pkg.devDependencies && pkg.devDependencies["@chughtapan/safer-spec-development"])
              || (pkg.dependencies && pkg.dependencies["@chughtapan/safer-spec-development"]) || "";
    process.stdout.write(dep ? "1" : "0");
  ' 2>/dev/null || echo "0")
  if [ "$HAS_CODEMOD" = "0" ]; then
    $PM add -D @chughtapan/safer-spec-development@~0.2.0 || {
      echo "WARN: living-spec install failed; skipping the rest of Step 4c (lint floor stands)." >&2
      SPEC_LAYER_SKIP_REASON="install failed"
      SPEC_LAYER_STATUS="skipped (install failed)"
    }
  fi
fi
```

**Probe the codemod (liveness).** Confirm the CLI installed and runs. A non-running CLI is a concern, not a skill-fatal error: it records the layer as wired-but-unhealthy and skips the rest of Step 4c. The `safer-spec` bin is invoked from `node_modules/.bin/` directly, which is package-manager-agnostic. (`safer-spec doctor` — the intended health + version-skew probe — is not implemented in the published codemod yet, so this uses `--version` for liveness; upgrade the probe to `doctor` once the sister package ships it.)

```bash
if [ -z "$SPEC_LAYER_SKIP_REASON" ]; then
  if ./node_modules/.bin/safer-spec --version >/dev/null 2>&1; then
    SPEC_LAYER_STATUS="installed"
  else
    echo "WARN: safer-spec installed but the CLI did not run; skipping the rest of Step 4c (lint floor stands)." >&2
    SPEC_LAYER_STATUS="DONE_WITH_CONCERNS (CLI did not run)"
    SPEC_LAYER_SKIP_REASON="CLI did not run"
  fi
fi
```

**Seed `safer-spec.config.json` (never overwrite).** Workspace monorepos repeat the seed per workspace package that carries a vitest config.

```bash
if [ -z "$SPEC_LAYER_SKIP_REASON" ] && [ ! -f "safer-spec.config.json" ]; then
  ./node_modules/.bin/safer-spec init >/dev/null 2>&1 || true
fi
```

**Wire the vitest reporter (sentinel-bounded; mirrors the Step 10b managed-`CLAUDE.md` section).** The patch detects `vitest.config.{ts,js,mts}` and `vitest.workspace.ts`, preserves existing reporters, and never double-applies the SAFER sentinel. Apply per workspace package when `vitest.workspace.ts` is present.

```bash
# The SAFER sentinel pair brackets the wired reporter block:
#   // <SAFER:vitest-reporter:begin>  ...managed block...  // <SAFER:vitest-reporter:end>
# Detect: if the block already exists, do not touch. Otherwise insert after the
# `test:` (or `reporters:`) key, preserving every existing reporter entry.
```

**Record for the receipt.** `SPEC_LAYER_STATUS` is one of `installed`, `skipped (<reason>)`, or `DONE_WITH_CONCERNS (<reason>)`. Step 10b writes it into the managed `CLAUDE.md` section (the `Spec layer:` line) and Step 11 prints it in the receipt. A skip or concern affects only the living-spec layer; the rest of setup's verdict is independent.


