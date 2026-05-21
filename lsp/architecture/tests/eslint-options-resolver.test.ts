import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import {
  globMatches,
  resolveArchitectureOptionsFromEslint,
} from "../eslint-options-resolver.js";

const tempDirs = new Set<string>();

afterEach(() => {
  for (const dir of tempDirs) fs.rmSync(dir, { recursive: true, force: true });
  tempDirs.clear();
});

function makeTempTree(files: Record<string, string>): string {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "acg-eslint-resolver-"));
  tempDirs.add(root);
  for (const [rel, contents] of Object.entries(files)) {
    const absolute = path.join(root, rel);
    fs.mkdirSync(path.dirname(absolute), { recursive: true });
    fs.writeFileSync(absolute, contents);
  }
  return root;
}

describe("globMatches", () => {
  it("matches literal segments", () => {
    expect(globMatches("src/index.ts", "src/index.ts")).toBe(true);
    expect(globMatches("src/index.ts", "src/other.ts")).toBe(false);
  });

  it("matches single * within a segment", () => {
    expect(globMatches("src/*.ts", "src/index.ts")).toBe(true);
    expect(globMatches("src/*.ts", "src/sub/index.ts")).toBe(false);
  });

  it("matches ** across segments", () => {
    expect(globMatches("src/**/*.ts", "src/index.ts")).toBe(true);
    expect(globMatches("src/**/*.ts", "src/sub/deep/index.ts")).toBe(true);
    expect(globMatches("**/*.ts", "anything/here.ts")).toBe(true);
  });

  it("strips leading ./", () => {
    expect(globMatches("./src/**", "src/foo.ts")).toBe(true);
  });

  it("requires a full match anchored at both ends", () => {
    expect(globMatches("src/*.ts", "x/src/index.ts")).toBe(false);
  });
});

describe("resolveArchitectureOptionsFromEslint", () => {
  it("returns null when no eslint config file exists", async () => {
    const root = makeTempTree({ "src/index.ts": "export {};\n" });
    const result = await resolveArchitectureOptionsFromEslint(root);
    expect(result).toBeNull();
  });

  it("returns null when settings carry no agent-code-guard.architecture", async () => {
    const root = makeTempTree({
      "src/index.ts": "export {};\n",
      "eslint.config.mjs": `
        export default [
          { files: ["src/**/*.ts"], settings: { other: {} } },
        ];
      `,
    });
    const result = await resolveArchitectureOptionsFromEslint(root);
    expect(result).toBeNull();
  });

  it("returns architecture options when present on a matching entry", async () => {
    const root = makeTempTree({
      "src/index.ts": "export {};\n",
      "eslint.config.mjs": `
        export default [
          {
            files: ["src/**/*.ts"],
            settings: {
              "agent-code-guard": {
                architecture: {
                  publicTypePackages: [
                    { package: "effect", reason: "core runtime" },
                  ],
                },
              },
            },
          },
        ];
      `,
    });
    const result = await resolveArchitectureOptionsFromEslint(root);
    expect(result).toEqual({
      publicTypePackages: [{ package: "effect", reason: "core runtime" }],
    });
  });

  it("merges settings across matching entries in array order", async () => {
    const root = makeTempTree({
      "src/index.ts": "export {};\n",
      "eslint.config.mjs": `
        export default [
          {
            files: ["src/**/*.ts"],
            settings: {
              "agent-code-guard": { architecture: { publicTypePackages: [{ package: "a", reason: "x" }] } },
            },
          },
          {
            files: ["src/**/*.ts"],
            settings: {
              "agent-code-guard": { architecture: { publicTypePackages: [{ package: "b", reason: "y" }] } },
            },
          },
        ];
      `,
    });
    const result = await resolveArchitectureOptionsFromEslint(root);
    // Later entries overwrite earlier ones (shallow merge of settings).
    expect(result).toEqual({
      publicTypePackages: [{ package: "b", reason: "y" }],
    });
  });

  it("applies entries with no `files` field (apply-to-all)", async () => {
    const root = makeTempTree({
      "src/index.ts": "export {};\n",
      "eslint.config.mjs": `
        export default [
          {
            settings: {
              "agent-code-guard": { architecture: { publicTypePackages: [{ package: "global", reason: "x" }] } },
            },
          },
        ];
      `,
    });
    const result = await resolveArchitectureOptionsFromEslint(root);
    expect(result).toEqual({
      publicTypePackages: [{ package: "global", reason: "x" }],
    });
  });

  it("skips entries whose ignores match the representative file", async () => {
    const root = makeTempTree({
      "src/index.ts": "export {};\n",
      "eslint.config.mjs": `
        export default [
          {
            files: ["src/**/*.ts"],
            ignores: ["src/index.ts"],
            settings: {
              "agent-code-guard": { architecture: { publicTypePackages: [{ package: "skip", reason: "x" }] } },
            },
          },
        ];
      `,
    });
    const result = await resolveArchitectureOptionsFromEslint(root);
    expect(result).toBeNull();
  });

  it("returns null on malformed eslint config", async () => {
    const root = makeTempTree({
      "src/index.ts": "export {};\n",
      "eslint.config.mjs": "throw new Error('boom');",
    });
    const result = await resolveArchitectureOptionsFromEslint(root);
    expect(result).toBeNull();
  });

  it("returns null when default export is not an array", async () => {
    const root = makeTempTree({
      "src/index.ts": "export {};\n",
      "eslint.config.mjs": "export default { not: 'an array' };",
    });
    const result = await resolveArchitectureOptionsFromEslint(root);
    expect(result).toBeNull();
  });

  it("prefers eslint.config.mjs over .js when both exist", async () => {
    const root = makeTempTree({
      "src/index.ts": "export {};\n",
      "eslint.config.mjs": `
        export default [
          { settings: { "agent-code-guard": { architecture: { publicTypePackages: [{ package: "mjs", reason: "x" }] } } } },
        ];
      `,
      "eslint.config.js": `
        export default [
          { settings: { "agent-code-guard": { architecture: { publicTypePackages: [{ package: "js", reason: "x" }] } } } },
        ];
      `,
    });
    const result = await resolveArchitectureOptionsFromEslint(root);
    expect(result).toEqual({
      publicTypePackages: [{ package: "mjs", reason: "x" }],
    });
  });
});
