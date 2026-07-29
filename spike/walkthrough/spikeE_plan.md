# Walkthrough: Spike E — the autonomous build, measured

**Target**: chughtapan/brief spike gauntlet · **Scenes**: 5

## Scene 1 — Hook
- Type: title
- Title card: "WHAT DID IT COST?"
- Subtitle: "Spike E — the autonomous build, measured"
- Narration: You asked where Spike E lives. Here it is, narrated instead of written. Spike E is the one spike that does not test code. It tests the build itself, and asks a single question. What does an autonomous engineering chain actually cost you, the human?

## Scene 2 — The chain
- Type: code
- Files: spike/walkthrough/spikeE-source.md
- Show: `bat --line-range 3:11 spike/walkthrough/spikeE-source.md`
- Highlight: 7-10
- Narration: Seven steps ran mostly on their own. A contract, an epic, four risk spikes in parallel, then an architect plan. You see them as GitHub issues one through seven. The four highlighted spikes all came back go. The only place the chain stops and waits for you is issue seven, the architect plan. That is the park.

## Scene 3 — Your hour
- Type: code
- Files: spike/walkthrough/spikeE-source.md
- Show: `bat --line-range 13:20 spike/walkthrough/spikeE-source.md`
- Highlight: 20
- Narration: Now add up only the human minutes. Fifteen at contract intake. Five to decompose. Twenty reviewing the spike gate. Twenty more at the park, including the switch to Effect. The highlighted line is the whole of it. Forty five to sixty five minutes across the entire night.

## Scene 4 — The machine, and the budget
- Type: code
- Files: spike/walkthrough/spikeE-source.md
- Show: `bat --line-range 22:28 spike/walkthrough/spikeE-source.md`
- Highlight: 28
- Narration: Against your one hour, the machine carried about eight hours of wall clock and four and a half hours of compute on the architect alone, with four spikes running at once. The Day ten budget allows fifteen human hours. You spent under one. The highlighted line is the verdict. The burn gate is not at risk.

## Scene 5 — Outro
- Type: outro
- Title card: "UNDER ONE HOUR"
- Subtitle: "of fifteen budgeted · gate not at risk"
- Narration: Under one human hour out of fifteen. That is the calibration Spike E exists to produce. Next time, watch the brief instead of reading the table.
