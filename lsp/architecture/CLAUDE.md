## Project structural choices (managed by /safer:setup — do not edit manually; rerun the skill to change)

- Schema library: Effect Schema
- Database access: none
- Integration tests: not set
- ESLint floor: eslint-plugin-agent-code-guard@0.0.8
- Effect runtime: yes
- Env var access: Config.string in an Effect Layer
- Spec layer: skipped (the living-spec reporter targets vitest, and no vitest.config.{ts,js,mts} is present)
