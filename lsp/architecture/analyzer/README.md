# Architecture Rules

This folder owns graph-backed architecture diagnostics. These rules analyze
the whole TypeScript project, not only the currently linted file.

The implementation is organized by analysis surface:

- `exports/` inspects index and public export curation.
- `folder-shape/` inspects folder size, README, and facade pressure.
- `imports/` builds and analyzes local import topology.
- `module-shape/` inspects accidental boundary modules and shared kernels.
- `package-api/` inspects `package.json` public entries.
- `project/` builds the source model, config, cache, and diagnostic contracts.
- `type-surface/` inspects public API type ownership.

`index.ts` is the architecture analyzer facade. It exports
`analyzeWorkspace(options)`, which the LSP server, CI shim, and tests
call to get the full `ArchitectureReport` for a project root.

## Performance

The architecture analyzer runs once per project and is cached. The cache
TTL defaults to 5 seconds so long-lived hosts (LSP, VS Code) see fixes
promptly. CI lints finish in one pass, so a longer TTL is safe:

```ts
analyzeWorkspace({
  projectRoot,
  cacheTtlMs: Infinity, // CI: never rebuild within a single lint run
});
```

Valid range: `0` (always rebuild) through `Infinity`.
