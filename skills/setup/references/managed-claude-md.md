# Step 10b: Write the managed `CLAUDE.md` section

Write a sentinel-bounded `## Project structural choices` block into the project's `CLAUDE.md`. Claude Code loads `CLAUDE.md` automatically at session start, so this block is the per-repo structural contract that complements `PRINCIPLES.md`. Reruns of `/safer:setup` replace the block in place; every other line of `CLAUDE.md` is untouched.

Resolve the installed plugin version. Read the installed `package.json` directly (the plugin was installed in Step 2, so the path resolves); fall back to `$PM ls` only if the read fails:

```bash
PLUGIN_VERSION=$(node -p "require('eslint-plugin-agent-code-guard/package.json').version" 2>/dev/null)
if [ -z "$PLUGIN_VERSION" ]; then
  PLUGIN_VERSION=$($PM ls eslint-plugin-agent-code-guard --depth=0 --json 2>/dev/null \
    | grep -oE '"version": *"[^"]+"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
fi
[ -z "$PLUGIN_VERSION" ] && PLUGIN_VERSION="unknown"
```

Build the section in a temp file (avoids shell-quoting hazards in `awk`). Trap cleanup so a Ctrl-C between `mktemp` and the final `rm` does not leak:

```bash
SECTION_FILE=$(mktemp)
trap 'rm -f "$SECTION_FILE"' EXIT INT TERM
cat > "$SECTION_FILE" <<EOF
## Project structural choices (managed by /safer:setup — do not edit manually; rerun the skill to change)

- Schema library: ${SCHEMA_LIB}
- Database access: ${DB_TOOL}
- Integration tests: ${INTEGRATION_GLOB:-not set}
- ESLint floor: eslint-plugin-agent-code-guard@${PLUGIN_VERSION}
- Effect runtime: ${EFFECT_RUNTIME}
- Env var access: ${ENV_VAR_ACCESS}
- Spec layer: ${SPEC_LAYER_STATUS:-skipped}
EOF
```

Apply the section. If `CLAUDE.md` does not exist, the section IS the file. Otherwise, hand the file to `awk`, which replaces only the sentinel-bounded region:

```bash
TARGET="CLAUDE.md"
if [ ! -e "$TARGET" ]; then
  cp "$SECTION_FILE" "$TARGET"
  echo "CLAUDE.md: created"
else
  awk -v section_file="$SECTION_FILE" '
    BEGIN {
      while ((getline line < section_file) > 0) {
        section = section sep line
        sep = "\n"
      }
      close(section_file)
      printed = 0
      in_managed = 0
    }
    /^## Project structural choices \(managed by \/safer:setup/ {
      print section
      printed = 1
      in_managed = 1
      next
    }
    in_managed && /^## / {
      in_managed = 0
      print ""
      print
      next
    }
    in_managed { next }
    { print }
    END {
      if (!printed) {
        if (NR > 0) print ""
        print section
      }
    }
  ' "$TARGET" > "$TARGET.tmp" && mv "$TARGET.tmp" "$TARGET"
  echo "CLAUDE.md: updated"
fi
```

(The `trap` set after `mktemp` removes `$SECTION_FILE` on EXIT, INT, or TERM; no explicit `rm` is needed.)

Idempotency contract:

- No `CLAUDE.md` → file created containing only the managed section.
- Existing `CLAUDE.md` with no sentinel heading → section appended at EOF; one blank line separates it from prior content.
- Existing `CLAUDE.md` with the sentinel heading anywhere → content from the sentinel up to (but not including) the next `## ` heading or EOF is replaced; one blank line separates the new section from any following `## ` heading.

The `awk` pattern matches the prefix `## Project structural choices (managed by /safer:setup` so the disclaimer wording can be revised in future versions without breaking idempotency on already-installed repos.

This skill never `git add`s or commits `CLAUDE.md`. The user stages and commits.

