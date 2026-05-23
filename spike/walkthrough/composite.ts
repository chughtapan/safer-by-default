#!/usr/bin/env bun
import { existsSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";

interface Manifest {
  title: string;
  totalDurationSec: number;
  scenes: { id: number; title: string; durationSec: number }[];
}

const XFADE_DURATION = 0.4; // seconds — applied between each adjacent scene
const FOOTER_HEIGHT_PX = 36;
const PR_NUMBER = process.env.PR_NUMBER ?? "?";
const BRANCH =
  process.env.BRANCH ??
  (() => {
    const r = spawnSync("git", ["branch", "--show-current"], {
      encoding: "utf8",
    });
    return r.stdout.trim() || "?";
  })();

const args = process.argv.slice(2);
const manifestPath = args[0] ?? "manifest.json";
const audioPath = args[1] ?? "narration.wav";
const outputPath = args[2] ?? "final.mp4";

const manifest: Manifest = JSON.parse(readFileSync(manifestPath, "utf8"));

// Probe each segment's actual rendered duration; xfade math needs exact lengths.
function videoDuration(path: string): number {
  const r = spawnSync(
    "ffprobe",
    [
      "-v",
      "error",
      "-show_entries",
      "format=duration",
      "-of",
      "default=noprint_wrappers=1:nokey=1",
      path,
    ],
    { encoding: "utf8" },
  );
  return parseFloat(r.stdout.trim());
}

const segments: { id: number; title: string; path: string; videoSec: number; audioSec: number }[] = [];
for (const s of manifest.scenes) {
  const segPath = resolve(`segments/scene_${s.id}.mp4`);
  if (!existsSync(segPath)) {
    throw new Error(`Missing segment ${segPath} — run render_scenes.ts first`);
  }
  segments.push({
    id: s.id,
    title: s.title,
    path: segPath,
    videoSec: videoDuration(segPath),
    audioSec: s.durationSec,
  });
}

console.log("Segments to composite:");
for (const s of segments) {
  console.log(
    `  scene ${s.id} (${s.title}): video=${s.videoSec.toFixed(2)}s audio=${s.audioSec.toFixed(2)}s`,
  );
}

// xfade chained: each adjacent pair crossfades for XFADE_DURATION seconds.
// Offset for segment N is sum(durations[0..N-1]) - XFADE_DURATION * N.
// Output duration is sum(videoSec) - XFADE_DURATION * (sceneCount - 1).
//
// We'll pad each segment with tpad clone to match max(videoSec, audioSec + XFADE) so
// that audio crossfades cleanly into the next scene.

const inputs: string[] = [];
for (const s of segments) {
  inputs.push("-i", s.path);
}
inputs.push("-i", audioPath);

const filters: string[] = [];

// Pad each video segment to a normalized length per scene so xfade math is predictable.
// Target per-scene length = max(videoSec, audioSec) so neither stream gets cut.
const scenePadded: { id: number; label: string; lengthSec: number }[] = [];
for (let i = 0; i < segments.length; i++) {
  const s = segments[i];
  const target = Math.max(s.videoSec, s.audioSec) + (i === segments.length - 1 ? 0 : XFADE_DURATION);
  const label = `v${i}pad`;
  filters.push(
    `[${i}:v]tpad=stop_mode=clone:stop_duration=${(target - s.videoSec).toFixed(3)},setpts=PTS-STARTPTS[${label}]`,
  );
  scenePadded.push({ id: s.id, label, lengthSec: target });
}

// Chain xfade across all padded segments.
let cumulativeOffset = 0;
let prevLabel = scenePadded[0].label;
for (let i = 1; i < scenePadded.length; i++) {
  const curr = scenePadded[i];
  cumulativeOffset += scenePadded[i - 1].lengthSec - XFADE_DURATION;
  const outLabel = i === scenePadded.length - 1 ? "vstitched" : `vx${i}`;
  filters.push(
    `[${prevLabel}][${curr.label}]xfade=transition=fade:duration=${XFADE_DURATION}:offset=${cumulativeOffset.toFixed(3)}[${outLabel}]`,
  );
  prevLabel = outLabel;
}

if (scenePadded.length === 1) {
  // Single scene: just rename the pad label to vstitched
  filters.push(`[${scenePadded[0].label}]copy[vstitched]`);
}

// Footer overlay via drawtext — persistent across the whole stitched video
const footerText = `PR #${PR_NUMBER}  •  ${BRANCH}  •  spike/walkthrough`;
const footerEscaped = footerText
  .replace(/\\/g, "\\\\")
  .replace(/:/g, "\\:")
  .replace(/'/g, "\\'");
filters.push(
  `[vstitched]drawtext=text='${footerEscaped}':fontsize=20:fontcolor=white@0.75:x=(w-text_w)/2:y=h-${FOOTER_HEIGHT_PX}:box=1:boxcolor=black@0.55:boxborderw=8[vout]`,
);

const filterComplex = filters.join(";\n");

// Audio: just use the pre-concatenated narration.wav (which is the audio input index sceneCount).
// We don't bother with per-scene audio xfade because the per-scene wavs already have 0.8s tail
// silence — that already provides a soft transition window. The visual xfade is the focal change.

const audioInputIndex = segments.length;
const cmd = [
  "ffmpeg",
  "-y",
  ...inputs,
  "-filter_complex",
  filterComplex,
  "-map",
  "[vout]",
  "-map",
  `${audioInputIndex}:a`,
  "-c:v",
  "libx264",
  "-preset",
  "fast",
  "-pix_fmt",
  "yuv420p",
  "-c:a",
  "aac",
  "-b:a",
  "128k",
  "-shortest",
  outputPath,
];

console.log("\nffmpeg filter graph:");
console.log(filterComplex);
console.log("");

const r = spawnSync(cmd[0], cmd.slice(1), {
  stdio: ["ignore", "ignore", "inherit"],
});
if (r.status !== 0) {
  console.error("ffmpeg composite failed");
  process.exit(1);
}

const finalDur = videoDuration(outputPath);
console.log(`\nWrote ${outputPath} (${finalDur.toFixed(2)}s)`);
