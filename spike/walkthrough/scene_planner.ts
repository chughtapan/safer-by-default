#!/usr/bin/env bun
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";

type SceneType = "title" | "pr-card" | "log" | "code" | "diff" | "outro";

interface Scene {
  id: number;
  title: string;
  type: SceneType;
  titleCard?: string;
  subtitle?: string;
  files: string[];
  show?: string;
  highlight?: string; // "47-52" or "47"
  narration?: string;
}

interface Plan {
  title: string;
  scenes: Scene[];
}

interface Manifest {
  title: string;
  totalDurationSec: number;
  scenes: { id: number; title: string; durationSec: number }[];
}

const VALID_TYPES: SceneType[] = [
  "title",
  "pr-card",
  "log",
  "code",
  "diff",
  "outro",
];

function parsePlan(md: string): Plan {
  const titleMatch = md.match(/^# Walkthrough:\s*(.+)$/m);
  const title = titleMatch?.[1]?.trim() ?? "Walkthrough";

  const headerRe = /^## Scene (\d+)\s*[—-]\s*(.+?)(?:\s*\([^)]*\))?\s*$/gm;
  const headers = [...md.matchAll(headerRe)];
  const scenes: Scene[] = [];

  for (let i = 0; i < headers.length; i++) {
    const h = headers[i];
    const start = h.index! + h[0].length;
    const end = i + 1 < headers.length ? headers[i + 1].index! : md.length;
    const body = md.slice(start, end);

    const field = (name: string): string | undefined => {
      const re = new RegExp(`^\\s*[-*]\\s*${name}:\\s*(.+)$`, "m");
      const m = body.match(re);
      if (!m) return undefined;
      let v = m[1].trim();
      if (v.startsWith("`") && v.endsWith("`")) v = v.slice(1, -1);
      if (v.startsWith('"') && v.endsWith('"')) v = v.slice(1, -1);
      return v;
    };

    const filesRaw = field("Files") ?? "";
    const files =
      filesRaw === "" || filesRaw.toLowerCase() === "none"
        ? []
        : filesRaw.split(",").map((s) => s.trim()).filter(Boolean);

    const typeRaw = (field("Type") ?? "code").toLowerCase();
    if (!VALID_TYPES.includes(typeRaw as SceneType)) {
      throw new Error(
        `Scene ${h[1]}: invalid Type "${typeRaw}". Must be one of ${VALID_TYPES.join("|")}.`,
      );
    }

    scenes.push({
      id: parseInt(h[1], 10),
      title: h[2].trim(),
      type: typeRaw as SceneType,
      titleCard: field("Title card"),
      subtitle: field("Subtitle"),
      files,
      show: field("Show"),
      highlight: field("Highlight"),
      narration: field("Narration"),
    });
  }

  return { title, scenes };
}

function tapeHeader(outputPath: string): string[] {
  return [
    `Output ${outputPath}`,
    `Set Shell bash`,
    `Set FontSize 22`,
    `Set Width 1920`,
    `Set Height 1080`,
    `Set Theme "Catppuccin Mocha"`,
    `Set TypingSpeed 15ms`,
    `Set Padding 30`,
    `Set WindowBar Colorful`,
    `Set BorderRadius 12`,
    `Set Margin 40`,
    `Set MarginFill "#1d1f2a"`,
    `Set CursorBlink false`,
    `Env BAT_PAGER ""`,
    `Env BAT_STYLE "numbers,grid"`,
    `Env PAGER cat`,
    `Env DELTA_PAGER cat`,
  ];
}

function shellEscapeSingle(s: string): string {
  // For wrapping a string in '...'  bash single quotes
  return s.replace(/'/g, "'\\''");
}

function buildShowCommand(scene: Scene): string {
  switch (scene.type) {
    case "title":
    case "outro": {
      const tc = scene.titleCard ?? scene.title;
      const sub = scene.subtitle ?? "";
      const accent = scene.type === "outro" ? "#a6e3a1" : "#cba6f7";
      const lines = sub
        ? `'${shellEscapeSingle(tc)}' '' '${shellEscapeSingle(sub)}'`
        : `'${shellEscapeSingle(tc)}'`;
      return `gum style --align center --border double --border-foreground '${accent}' --foreground '#cdd6f4' --padding '3 6' --margin '4 0' --width 70 --bold ${lines}`;
    }
    case "pr-card": {
      // pr-card.txt is pre-rendered by scene_planner before tape emission
      return `cat spike/walkthrough/segments/pr-card.txt | gum style --border rounded --border-foreground '#89b4fa' --padding '2 4' --width 110`;
    }
    case "log": {
      return scene.show ?? `git log --graph --oneline --decorate -C2 main..HEAD`;
    }
    case "code": {
      if (!scene.show) {
        throw new Error(`Scene ${scene.id} (code): missing Show field`);
      }
      if (!scene.highlight) {
        throw new Error(
          `Scene ${scene.id} (code): missing Highlight field (use a diff scene if you don't want line emphasis)`,
        );
      }
      const range = scene.highlight.replace(/-/g, ":");
      return scene.show.replace(/\bbat\b/, `bat --highlight-line ${range}`);
    }
    case "diff": {
      if (!scene.show) {
        throw new Error(`Scene ${scene.id} (diff): missing Show field`);
      }
      return scene.show;
    }
  }
}

function emitSceneTape(
  scene: Scene,
  sleepSec: number,
  outputPath: string,
): string {
  const lines: string[] = [];
  lines.push(
    `# Scene ${scene.id} (${scene.type}): ${scene.title} — sleep ${sleepSec.toFixed(2)}s`,
  );
  lines.push(``);
  for (const h of tapeHeader(outputPath)) lines.push(h);
  lines.push(``);
  lines.push(`Hide`);
  lines.push(`Type "clear"`);
  lines.push(`Enter`);
  lines.push(`Sleep 200ms`);
  lines.push(`Show`);
  const cmd = buildShowCommand(scene).replace(/"/g, '\\"');
  lines.push(`Type "${cmd}"`);
  lines.push(`Enter`);
  lines.push(`Sleep ${sleepSec.toFixed(2)}s`);
  return lines.join("\n") + "\n";
}

async function prerenderPrCard(): Promise<void> {
  // For pr-card scenes, shell out to gh to fetch and format the PR data.
  // Write to spike/walkthrough/segments/pr-card.txt so the tape just cats it.
  const proc = Bun.spawnSync({
    cmd: [
      "gh",
      "pr",
      "view",
      "--template",
      `PR #{{.number}}: {{.title}}

branch: {{.headRefName}}    by: {{.author.login}}
diff:   +{{.additions}} / -{{.deletions}} across {{len .files}} files

{{.body}}`,
    ],
    stdout: "pipe",
    stderr: "pipe",
  });
  if (proc.exitCode !== 0) {
    throw new Error(
      `gh pr view failed for pr-card scene: ${new TextDecoder().decode(proc.stderr)}`,
    );
  }
  let body = new TextDecoder().decode(proc.stdout);
  // Truncate body to ~12 lines so the card fits the canvas at FontSize 22
  const allLines = body.split("\n");
  if (allLines.length > 18) {
    body = allLines.slice(0, 18).join("\n") + "\n...";
  }
  writeFileSync("segments/pr-card.txt", body);
  console.log(`  pre-rendered segments/pr-card.txt (${body.length} bytes)`);
}

// vhs's render-vs-wallclock varies. Per-scene short renders see less drift than
// monolithic recordings. 1.15 is the starting heuristic for v3.
const VHS_TIMESCALE = 1.15;
const TYPE_RENDER_OVERHEAD_SEC = 0.3;

const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const positional = args.filter((a) => !a.startsWith("--"));
const planPath = positional[0] ?? "narrative_plan.md";
const manifestPath = positional[1] ?? "manifest.json";

const md = readFileSync(planPath, "utf8");
const plan = parsePlan(md);

if (plan.scenes.length === 0) {
  console.error(`No scenes found in ${planPath}`);
  process.exit(1);
}

let manifest: Manifest;
try {
  manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
} catch {
  console.error(
    `Could not read manifest at ${manifestPath}. Run tts.ts first.`,
  );
  process.exit(1);
}

const durationById = new Map(
  manifest.scenes.map((s) => [s.id, s.durationSec]),
);

if (!existsSync("segments")) mkdirSync("segments", { recursive: true });

// Pre-render any pr-card scenes
if (plan.scenes.some((s) => s.type === "pr-card")) {
  await prerenderPrCard();
}

for (const scene of plan.scenes) {
  const audioSec = durationById.get(scene.id);
  if (audioSec === undefined) {
    throw new Error(`Scene ${scene.id} has no manifest entry`);
  }
  const sleepSec = Math.max(
    1.0,
    (audioSec - TYPE_RENDER_OVERHEAD_SEC) * VHS_TIMESCALE,
  );
  const outputPath = `spike/walkthrough/segments/scene_${scene.id}.mp4`;
  const tape = emitSceneTape(scene, sleepSec, outputPath);
  const tapePath = `segments/scene_${scene.id}.tape`;

  if (dryRun) {
    console.log(`=== ${tapePath} (${scene.type}) ===`);
    console.log(tape);
  } else {
    writeFileSync(tapePath, tape);
  }
}

if (!dryRun) {
  console.log(
    `Wrote ${plan.scenes.length} per-scene tapes to segments/ (audio target ${manifest.totalDurationSec}s)`,
  );
}
