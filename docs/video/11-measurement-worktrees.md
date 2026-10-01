# Measurement v7–v8: screenshot versus Locant when the app on screen comes from another worktree

Sep 30 – Oct 1, 2026. Two batches of 40 graded runs each, plus two uncounted trials. It replaces `10-measurement-v3.md` as the measurement the site quotes: v3 gave the screenshot side the whole Simulator window and the Locant side one element, so it measured the size of the image as much as the tool.

## Summary

- **The question.** The app on screen was built from one git worktree and the agent works in another, the normal layout when Claude Code desktop gives each session its own worktree. Does the agent change the code that is on screen, or a look-alike in its own copy?
- **v7, Locant 0.9 as shipped.** Locant did not reliably steer the agent: 9 of 20 Locant runs changed the wrong copy (screenshot 13 of 20), and the end-to-end pass rate was even (17 vs 16). The agents read Locant's `Project:` path only when their own search came up empty.
- **The fix.** One sentence under the `Project:` line saying that folder built the app on screen, and what to do from another checkout. PR [#48](https://github.com/Malik1942/locant/pull/48).
- **v8, Locant with the fix.** 20 of 20 passed, 19 of 20 with no reply, 0 wrong-copy changes. The screenshot side, whose input did not change, scored as before (16 of 20 passed, 14 changed a wrong copy, 4 silent failures).
- **v8, paired over 20 pairs.** Locant was right with no reply in 15 pairs where the screenshot was not, never the reverse (p < 0.001). It never changed a wrong copy; the screenshot did in 14 pairs (p < 0.001). It reached the right file first in 17 of 20 pairs (p < 0.001; median 39 s vs 80 s). It cost half as much ($10.95 vs $22.54 for 20 runs).
- **The primary outcome** (pass after at most one reply) was 20 vs 16, p = 0.125. Under the one-reply rule the screenshot side recovers on T1, T2 and T4, so only T3's 4 pairs can differ, and that caps the test at p = 0.125.

## 1. Setup

| | |
|---|---|
| App | Apple's Food Truck sample (SwiftUI), copied without its history: one commit |
| On screen for T1–T4 | Worktree `.claude/worktrees/order-cards-redesign-4f2a`, branch `feat/order-cards-redesign` (`94aafab`): an order pill, filled header badges with a chevron capsule, colored flavor bars, an Orders summary banner |
| The agent's folder | Worktree `.claude/worktrees/session-7c1d`, branch `am/session-7c1d` = main (`b5c2719`), without the redesign. On screen only for T5, the control |
| Agent | Claude Code CLI 2.1.284 (the desktop app's own), `claude-opus-5`, medium effort, headless, a fresh session per run, no MCP servers, auto-memory off, permissions skipped, 15-minute cap. Its system prompt says it is in a git worktree and should run commands from that folder |
| Inputs | Both sides: the same PNG (Locant's crop, component + 40 pt), the same note, the same build sentence, which names no folder. Locant side: plus the Markdown Locant puts on the clipboard (element, app, `Project:` line, text in the image) |
| Captures | Real Locant Point captures on the simulator (Xcode 27 Device Hub), one per task, the note typed in Locant. A hover screenshot and the sidecar verify each element |
| Design | 20 pairs per batch, 4 per task, order alternated (pairs 1–5 and 16–20 Locant first) |
| One reply | Stopped without a change: the task's answer. Changed a wrong copy and said the screen didn't match: the answer plus "Undo what you changed anywhere else." Changed the right copy only, or a wrong copy without a word: no reply. Whether it "said" is a blind model judgment made during the run |
| Grading | Opus 5.5 at high effort, blind to the side: the final diffs of all three checkouts against a 3-point rubric per task, and separately the agent's first message for "told you". Which checkout changed comes from git and a file watcher, not the judge |
| Pass | After at most one reply: the change is only in the checkout the screen came from, on the right component, every rubric point is met, and it compiles |

## 2. Tasks

| | Component on screen | What the agent's folder has | Note typed in Locant |
|---|---|---|---|
| T1 | Order pill, New Orders card | No pill: a plain order line in the same file | A status dot colored by order status; a slightly taller pill |
| T2 | Forecast card header | The same style file, with no badge and no capsule | Badge about 24 pt and outlined; no gray capsule behind the chevron |
| T3 | Sweet flavor bar, Donut Editor | A system `Gauge` in the same place: a look-alike | Each number in white inside its bar; thicker bars |
| T4 | Orders summary banner | No banner; "new orders" matches a different card | A green count of ready orders; "All caught up" when there are no new orders |
| T5 (control) | An Orders row, built from the agent's own folder | The same code | A status capsule at the right end; the donut count moved under the order number |

## 3. Results

### 3.1 v7: Locant 0.9 as shipped (Sep 30, 40 runs, 60 sessions, $40.45)

| | Screenshot | Locant | Paired test |
|---|---|---|---|
| **Passed (at most one reply)** | 16 / 20 | 17 / 20 | McNemar p = 1.0 |
| Right with no reply | 4 | 9 | p = 0.06 (5 pairs only Locant, 0 only screenshot) |
| Changed a wrong copy at some point | 13 | 9 | p = 0.125 (4 pairs only screenshot, 0 only Locant) |
| Changed a wrong copy and said nothing | 4 | 3 | |
| Told you the screen didn't match | 12 | 13 | |
| Stopped to ask before changing anything | 3 | 2 | |
| Replies needed | 12 | 8 | |
| Reached the code on screen | 16 | 17 | |
| Time to the right file, median (runs that got there) | 79 s | 59 s | Locant first in 12 of 20 pairs, Wilcoxon p = 0.29 |
| Whole run, median | 94 s | 80 s | |
| Tokens, median | 657k | 491k | |
| Cost, 20 runs | $22.01 | $18.44 | |

### 3.2 The fix

`MarkdownBuilder` now writes, right under `Project: <folder>`:

> The app on screen was built from this folder. If you are working in a different checkout of this repo (another worktree or clone), your copy is not the code on screen: change it in this folder, or ask which copy to change.

v8 changes only that one sentence:

- **Same captures.** v8 reuses v7's five captures, with the same images and notes.
- **Rendered by Locant itself.** Each capture's text comes from the build's own MCP `get_capture`, which runs the same `MarkdownBuilder` as the clipboard.
- **Checked against v7.** The old build, rendered this way, reproduces v7's clipboard text byte for byte. The fixed build adds exactly the one line.
- **Screenshot side untouched.** Its messages are byte-identical to v7's.
- **Plan fixed first, no tuning.** v8's plan was written before the first run (`PLAN.md`, 02:45:12; runs started 02:45:18), and there was no trial on these tasks.

### 3.3 v8: Locant with the fix (Oct 1, 40 runs, 53 sessions, $33.48)

| | Screenshot | Locant | Paired test |
|---|---|---|---|
| **Passed (at most one reply)** | 16 / 20 | **20 / 20** | McNemar p = 0.125 (4 pairs only Locant, 0 only screenshot) |
| Right with no reply | 4 | **19** | p < 0.001 (15 pairs only Locant, 0 only screenshot) |
| Changed a wrong copy at some point | 14 | **0** | p < 0.001 (14 pairs only screenshot, 0 only Locant) |
| Changed a wrong copy and said nothing | 4 | **0** | |
| Told you the screen didn't match | 12 | 16 | |
| Found the redesign worktree on its own | 3 | 16 | |
| Stopped to ask before changing anything | 2 | 1 | |
| Replies needed | 12 | **1** | |
| Reached the code on screen | 16 | 20 | |
| Time to the right file, median (runs that got there) | 80 s | **39 s** | Locant first in 17 of 20 pairs, Wilcoxon p < 0.001 |
| Whole run, median | 92 s | 65 s | |
| Tokens, median | 662k | 388k | |
| Cost, 20 runs | $22.54 | **$10.95** | |

### 3.4 Before and after the fix (unpaired, two-sided Fisher exact)

| Side | Outcome | v7 | v8 | p |
|---|---|---|---|---|
| Locant | Changed a wrong copy at some point | 9 / 20 | 0 / 20 | 0.001 |
| Locant | Right with no reply | 9 / 20 | 19 / 20 | 0.001 |
| Locant | Changed a wrong copy and said nothing | 3 / 20 | 0 / 20 | 0.23 |
| Locant | Passed | 17 / 20 | 20 / 20 | 0.23 |
| Screenshot | Changed a wrong copy at some point | 13 / 20 | 14 / 20 | 1.0 |
| Screenshot | Right with no reply | 4 / 20 | 4 / 20 | 1.0 |
| Screenshot | Changed a wrong copy and said nothing | 4 / 20 | 4 / 20 | 1.0 |
| Screenshot | Passed | 16 / 20 | 16 / 20 | 1.0 |

The screenshot side's input did not change between batches, and its results did not move, so Locant's change comes from the sentence, not from drift between the two days.

### 3.5 Per task (4 runs each: passed · changed a wrong copy · median time to the right file)

| | v7 Screenshot | v7 Locant | v8 Screenshot | v8 Locant |
|---|---|---|---|---|
| T1 pill missing | 4 · 4 · 100 s | 2 · 4 · 86 s | 4 · 4 · 106 s | **4 · 0 · 40 s** |
| T2 header differs | 4 · 2 · 63 s | 4 · 1 · 52 s | 4 · 4 · 79 s | **4 · 0 · 38 s** |
| T3 look-alike | 0 · 4 · never | 3 · 3 · 108 s | 0 · 4 · never | **4 · 0 · 46 s** |
| T4 banner missing | 4 · 3 · 87 s | 4 · 1 · 61 s | 4 · 2 · 89 s | **4 · 0 · 38 s** |
| T5 control | 4 · 0 · 30 s | 4 · 0 · 35 s | 4 · 0 · 32 s | 4 · 0 · 33 s |

## 4. What the runs show

1. **Before the fix, agents used the `Project:` path only when their search failed.** In v7, Locant runs found the redesign on their own in 8 of 20 runs, 7 of them on T2 and T4, where nothing in their folder matched the picture. When the folder had something close enough, they changed that instead: main's Gauge on T3, or main's plain `Text(order.id)` line, taken for "the pill" on T1, twice without a word.
2. **With the sentence, every mismatch run went to the right worktree.** All 16 Locant runs on T1–T4 changed the redesign: 15 went there directly and 1 asked first. Replies needed fell from 8 to 1.
3. **A screenshot cannot tell which copy is on screen.** Every screenshot run on T1–T4, in both batches, changed its own folder first. On T1, T2 and T4 it usually said the screen didn't match and fixed it after the reply. On T3, where its folder has a look-alike, it never noticed in 8 runs.
4. **The control did not move.** T5 passed 16 of 16 across both sides and batches, with no false alarm, and Locant's time there matched the screenshot's (33 s vs 32 s in v8).

## 5. Limitations

- **The fix was written from these tasks.** It was derived from failures on these five tasks, so v8 shows it works here. Whether it generalizes needs new tasks or another app.
- **The primary outcome was capped.** Pass after one reply could not go below p = 0.125 in this design. The outcomes the fix targets (wrong-copy changes, right with no reply) were secondary.
- **v7 and v8 ran on different days.** Their comparison crosses batches. The unchanged screenshot side matching across them supports it.
- **Narrow scope.** One app, one model at one effort level, 20 pairs per batch.
- **Locant's `Project:` is the newest build of the app, not the installed one.** In this test they were always the same.
- **Replies were instant.** The simulated reply arrives immediately, and time counts agent time only.
- **The judge is a model.** Every change made in the right copy met all 3 rubric points. The only miss was a v7 Locant run that changed the wrong copy (0 of 3).
- **The redesign got accessibility grouping.** I added standard grouping to the pill, banner and bars so Point selects whole components. Without it, the custom-drawn bar has no element at all.

## 6. Process record

- **Trials, not counted.** Two rounds ran before v7 (4 pairs, then 5 pairs). The first showed the screenshot side had no way to recover after saying the screen didn't match, so the one-reply rule was added before v7's counted runs.
- **Plans fixed first.** v7's analysis plan was fixed before its counted runs. v8 kept it and added the before/after comparison, written before its runs.
- **Infrastructure.** Xcode 27 sometimes fails a build with a transient "disk I/O error" on its build database. It hit three agent builds in v7 (two Locant runs, one screenshot run) and none in v8. The agents retried, every run's final code compiled, and my own compile checks never hit it.

## 7. Code and data

- The payload change: PR [#48](https://github.com/Malik1942/locant/pull/48) (`MarkdownBuilder.projectAdvice`, its test, the same rule in the Locant skill).
- Raw data, per batch (`v7/`, `v8/`), kept outside the repo with the earlier measurements: `results.tsv` (one row per agent session: times, tokens, cost, which checkout changed), `judged-results.tsv` (both blind judgments), one `.jsonl` transcript, one diff per checkout, one file-watcher log and one build log per run, the five captures with their hover screenshots and sidecars, the exact messages each side received, `tasks.py` (notes, answers, rubrics), `run.sh`, `check.py`, `judge.py`, `flagcheck.py`, `stats.py`, and v8's `PLAN.md`.
