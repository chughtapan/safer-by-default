# vendor/safer-spec-skills

Committed snapshots of the two wrapper-skill bodies that `bin/safer-gen-skills`
inlines into `skills/contract-init/SKILL.md` and `skills/contract-migrate/SKILL.md`
via `{{> vendor-skill:<slug>}}` directives.

- `safer-spec-init/SKILL.md` → inlined by `skills/contract-init/SKILL.tmpl`
- `safer-spec-migrate/SKILL.md` → inlined by `skills/contract-migrate/SKILL.tmpl`

## Source

Each file is a verbatim copy of the same path under `skills/` in the published
codemod `@chughtapan/safer-spec-development` (repo `chughtapan/safer-spec-development`).
The npm package ships `skills/**`, so these bodies live at
`node_modules/@chughtapan/safer-spec-development/skills/<slug>/SKILL.md` in any
adopter install. The runtime codemod installs from npm; these snapshots exist
only as the build-time source for skill-body inlining.

Snapshot pin: `chughtapan/safer-spec-development@c63ad4882dacf94efbd492b863bd3a4dae67062b` (npm `0.2.0`).

## Why a snapshot, not a submodule

The full git submodule dragged `node_modules/`, `dist/`, and a lockfile onto disk
to serve two markdown files at generation time. A committed snapshot is the whole
build-time dependency, with no submodule init, no install step, and no sha that can
silently drift from the published `0.2.0`.

## Refreshing

When the codemod publishes a new release that changes either skill body:

1. `npm pack @chughtapan/safer-spec-development@<version>` (or read the installed
   `node_modules/@chughtapan/safer-spec-development/skills/<slug>/SKILL.md`).
2. Overwrite the two files here verbatim.
3. Update the pin line above and the `description` provenance in the two `.tmpl`s.
4. Re-run `bin/safer-gen-skills` and commit the regenerated `SKILL.md` files.

These files are regular committed files end-to-end. `bin/safer-gen-skills` refuses
to inline any path component that is a symlink, so keep them that way.
