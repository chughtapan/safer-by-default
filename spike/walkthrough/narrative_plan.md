# Walkthrough: narrated PR walkthroughs from the diff

**Target**: spike/walkthrough-narration @ 111c38b · **Scenes**: 7

## Scene 1 — Hook
- Type: title
- Title card: "WHO REVIEWS"
- Subtitle: "the thousand line PR"
- Narration: A thousand line pull request lands in your queue at five p m on a Friday. You skim it, you star it, you tell yourself you will get to it Monday. This spike asks the opposite question. What if the PR walked you through itself.

## Scene 2 — Thesis
- Type: pr-card
- Narration: This branch ships a five stage pipeline that turns a diff into a narrated walkthrough. A planner subagent writes the prose. Cartesia speaks it. v h s records each scene against its measured audio. f f m peg stitches the clips with crossfades and a footer, then it all posts back to the pull request as a release asset.

## Scene 3 — Per scene t t s loop
- Type: code
- Files: spike/walkthrough/tts.ts
- Show: `bat --line-range 200:225 spike/walkthrough/tts.ts`
- Highlight: 207-221
- Narration: The for loop on line two oh one walks every scene in the plan. Lines two oh seven through two oh nine name the raw w a v, the padded w a v, and a tail silence path. Line two fifteen awaits synthesize, which streams Cartesia bytes into raw. Line two nineteen pins a point eight second tail, and concat w a v s glues raw plus silence into padded. That tail is why each scene lets the viewer breathe.

## Scene 4 — Per scene v h s render loop
- Type: code
- Files: spike/walkthrough/render_scenes.ts
- Show: `bat --line-range 22:47 spike/walkthrough/render_scenes.ts`
- Highlight: 32-43
- Narration: For each scene in the manifest, line twenty three resolves a tape path and twenty four the m p four output. Line twenty six refuses to proceed if the tape is missing. The spawn sync on line thirty two is where recording happens. The env hyphen i on line thirty five strips every environment variable, then hands back only path, home, and term. That is how the Cartesia API key in your shell never leaks into the recording.

## Scene 5 — Scene type dispatch
- Type: code
- Files: spike/walkthrough/scene_planner.ts
- Show: `bat --line-range 119:147 spike/walkthrough/scene_planner.ts`
- Highlight: 121-146
- Narration: Write slide markdown decides what each slide scene looks like. Line one twenty one branches on title or outro and builds a heading plus an optional blockquote subtitle. Line one twenty five handles p r card by shelling g h p r view with a curated j s o n field list, and line one forty three templates the p r number, title, branch, author, and line counts. The else on one forty five throws, because code and diff do not belong here.

## Scene 6 — Two pass crossfade composite
- Type: code
- Files: spike/walkthrough/composite.ts
- Show: `bat --line-range 84:110 spike/walkthrough/composite.ts`
- Highlight: 86-99
- Narration: Pass one pads every segment to its audio length. Line eighty six chains t pad with stop mode clone, then forces f p s thirty and resets p t s. The hyphen r thirty and f p s mode c f r on lines ninety four through ninety seven lock constant frame rate, so x fade in pass two does not reject the inputs as variable rate. Without those flags the whole composite fails with rate invalid.

## Scene 7 — Outro
- Type: outro
- Title card: "WATCH IT"
- Subtitle: "v3 link in PR 314"
- Narration: Open pull request three fourteen, scroll to the v three asset, and watch a diff explain itself. Then run b u n run t t s dot t s against your own narrative plan and hear how it sounds.
