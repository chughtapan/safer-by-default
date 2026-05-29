import guard from "eslint-plugin-agent-code-guard";
import tsParser from "@typescript-eslint/parser";
import comments from "@eslint-community/eslint-plugin-eslint-comments";
import tseslint from "@typescript-eslint/eslint-plugin";
import sonarjs from "eslint-plugin-sonarjs";

// Architecture-policy declarations for the agent-code-guard architecture suite
// (the plugin ships no policy defaults; each entry is a deliberate decision).
const ARCHITECTURE_OPTIONS = {
  // This package runs on Node (the LSP server and the bun harness), so `node:*`
  // built-in types in the public surface are native to the runtime, not a
  // vendor leak.
  packageRuntime: "node",
  // `analyzer/` is the shared kernel that `server/` and the root entrypoints
  // consume — that dependency IS the package's purpose, so sibling imports
  // into it are intended, not a cross-domain boundary violation.
  sharedFolderNames: [
    {
      folder: "analyzer",
      reason: "shared kernel: the analyzer is the core that server/ and the entrypoints consume",
    },
  ],
};

export default [
  // Global ignores: build output, deps, and the analyzer's intentionally
  // malformed fixtures (3.4k files that exist to be analyzed, not linted).
  { ignores: ["dist/**", "node_modules/**", "dogfood-fixtures/**"] },

  // TypeScript parser for every linted file; both blocks below inherit it.
  {
    languageOptions: {
      parser: tsParser,
      parserOptions: { ecmaVersion: 2022, sourceType: "module" },
    },
  },

  // Block 1: application source — analyzer, LSP server, root entrypoints.
  // Effect is a runtime dependency here, so the Effect-shaped guard rules
  // (async-keyword, promise-type, then-chain) stay enabled.
  {
    files: ["analyzer/**/*.ts", "server/**/*.ts", "*.ts"],
    ignores: ["**/*.test.ts", "**/*.spec.ts", "**/test-support/**"],
    plugins: {
      "agent-code-guard": guard,
      "@typescript-eslint": tseslint,
      sonarjs,
    },
    rules: {
      ...guard.configs.recommended.rules,
      // Tuned to its useful core: 0/1/-1/2, array indexes, default values, enum
      // members, readonly class fields, and type indexes are not "magic".
      "@typescript-eslint/no-magic-numbers": [
        "warn",
        {
          ignore: [0, 1, -1, 2],
          ignoreArrayIndexes: true,
          ignoreDefaultValues: true,
          ignoreEnums: true,
          ignoreReadonlyClassProperties: true,
          ignoreTypeIndexes: true,
        },
      ],
      // Honor the codebase's `_`-prefix convention for intentionally-unused
      // bindings (signature params, best-effort error-discard helpers).
      "@typescript-eslint/no-unused-vars": [
        "error",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_", caughtErrorsIgnorePattern: "^_" },
      ],
      "sonarjs/no-duplicate-string": ["warn", { threshold: 4 }],
      // Architecture policy (see ARCHITECTURE_OPTIONS above).
      "agent-code-guard/no-cross-domain-sibling-import": ["warn", ARCHITECTURE_OPTIONS],
      "agent-code-guard/no-public-vendor-type-leak": ["error", ARCHITECTURE_OPTIONS],
      // These two rules hardcode a `src/`-rooted layout: sourceFolderPath,
      // normalizedFacadeFile, and folderHasReadme in eslint-plugin-agent-code-guard
      // all prepend `src/`. This package is flat (analyzer/, server/ live directly
      // under the root), so folder-readme-required looks for READMEs at a
      // non-existent src/<folder>/ (never seeing the real analyzer/*/README.md),
      // and file-implicit-boundary-module's facadeFiles escape can never match
      // (module.relativePath carries no src/ prefix). Off until the plugin
      // supports non-src layouts (tracked: chughtapan/agent-code-guard#80);
      // boundary READMEs are maintained under analyzer/*.
      "agent-code-guard/folder-readme-required": "off",
      "agent-code-guard/file-implicit-boundary-module": "off",
    },
  },

  // Block 3: every linted .ts file must carry a written reason on each
  // eslint-disable directive.
  {
    files: ["analyzer/**/*.ts", "server/**/*.ts", "*.ts"],
    ignores: ["**/*.test.ts", "**/*.spec.ts"],
    plugins: { "eslint-comments": comments },
    rules: {
      "eslint-comments/require-description": ["error", { ignore: [] }],
    },
  },
];
