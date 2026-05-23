# Walkthrough: Narrated PR walkthrough pipeline

**Target**: spike/walkthrough-narration @ 3abdc58 · **Scenes**: 7

## Scene 1 — The reviewer's problem
- Type: title
- Title card: "1000 LINES"
- Subtitle: "and one approving thumb"
- Narration: You open a thousand line pull request. You skim every file because there is no time. You approve it. A week later something breaks in production, and you find the line you skipped. This is the review you do every day.

## Scene 2 — What you actually wanted
- Type: pr-card
- Narration: What you wanted was a peer to walk you through it. Show you the load bearing change, tell you why it matters, point at the line you would have missed. This pull request is that peer. It generates a narrated video walkthrough straight from the diff and the commit history, and ships the link in the description. You watch it once, and you actually understand the change.

## Scene 3 — Render each scene on its own
- Type: code
- Files: spike/walkthrough/render_scenes.ts
- Show: `bat --line-range 22:47 spike/walkthrough/render_scenes.ts`
- Highlight: 32-47
- Narration: One vhs recording per scene, not one for the whole video. This matters because terminal recordings drift. A monolithic recording is two minutes of accumulated timing error, and the narrator and the diff stop matching halfway through. Per scene isolation means scene seven aligns as tightly as scene one. The reviewer never catches the audio talking about code that already scrolled away.

## Scene 4 — Audio drives the clock
- Type: code
- Files: spike/walkthrough/tts.ts
- Show: `bat --line-range 200:225 spike/walkthrough/tts.ts`
- Highlight: 217-224
- Narration: The narrator records first, then ffprobe measures the wav, and the renderer sizes each segment to that measurement. The eight hundred millisecond tail silence is deliberate. Without it the cut lands the instant the last word ends and the viewer never registers what they just heard. With it, every scene gives you a beat to absorb the line on screen.

## Scene 5 — Hold the frame, never speed the voice
- Type: code
- Files: spike/walkthrough/composite.ts
- Show: `bat --line-range 84:110 spike/walkthrough/composite.ts`
- Highlight: 86-109
- Narration: When the video segment is shorter than the audio, we clone the last frame to cover the gap. We do not speed up the narrator. Audible speed ups are the first thing reviewers notice, and the second thing they bounce off. Holding the frame is invisible. The audio finishes naturally, the xfade lands on a clean boundary, and the viewer hears a peer talking, not a chipmunk reading a commit log.

## Scene 6 — The line the narrator is pointing at
- Type: code
- Files: spike/walkthrough/scene_planner.ts
- Show: `bat --line-range 119:147 spike/walkthrough/scene_planner.ts`
- Highlight: 120-135
- Narration: Each scene picks a renderer. Code scenes pipe through bat with highlight line set to the exact range the narrator is talking about, so the lines you are hearing about are also visibly lit on screen. The reviewer's eyes and ears land on the same five lines at the same second. That is the difference between watching a slideshow and following an argument.

## Scene 7 — Try it on your next big PR
- Type: outro
- Title card: "YOUR PR NEXT"
- Subtitle: "ship the link in the description"
- Narration: Next time you open a pull request over five hundred lines, run safer walkthrough on it and paste the video link into the description. Your reviewers will watch it once, understand the change, and leave you a better review.
