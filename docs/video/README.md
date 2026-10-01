# Locant video production

Scripts for the Palantir Product Design Show & Tell submission (Lens A, "Make it work"). The brief asks for one
video under 3 minutes that is a pitch, not a product demo: why, how (decisions, challenges, where AI came in), a demo,
and optionally what you would do with more time. Less is more.

| File | What it is | Feeds |
|---|---|---|
| `01-full-script.md` | The submission video, shot by shot, with voice and on-screen columns. Opens on the frustration, no cold open. Four design decisions, the first being "the accessibility tree, not the pixels". Target 2:55. | The YouTube upload |
| `02-demo-script.md` | Recording script for the product flow: hotkey, hover, click, note, paste, Show before & after. | Section 4 of the full script, and `site/assets/demo.mp4` |
| `03-before-script.md` | The "life before" comparison: the same fix done from a screenshot and done from a Locant capture, with a fair measurement protocol for tokens and time. | Section 4 of the full script |
| `04-voiceover.md` | Clean narration only, timed, with pronunciation and delivery notes. Print this one for the mic. | The audio track |
| `05-build-recording-map.md` | Where each phase sits in the two build recordings in ~/Movies, with the on-screen timer values. | Section 2 cutaways |
| `06-film-script.md` | The product-film capture contract: stage, scenes, camera notes, and the capture log of what was shot. | The demo footage |
| `07-demo-film-audit.md` | Scene-by-scene audit of the v3 footage against the film script, plus a timecoded verification pass on the delivered reel (`-v2.md` is the previous round). | Read before cutting |
| `08-voiceover-to-reel.md` | The narration placed against the reel's timecodes, both as a stand-alone demo read and as the cut list into the pitch. | Recording and cutting |
| `10-measurement-v3.md` | The first controlled screenshot-versus-Locant measurement: method, 24 runs in two conditions, statistics, threats to validity. Superseded by `11`: its screenshot was the whole window, Locant's image one element. | Section 4 |
| `11-measurement-worktrees.md` | Screenshot versus Locant when the app on screen was built from another worktree than the agent's: 80 graded runs in two rounds, Locant 0.9.0 and the payload change that fixed what the first round found. The measurement the site quotes. | The site's Measured section |
| `09-rough-cut.md` | The full-pitch rough cut (`~/Desktop/locant-film/v4/rough/locant-pitch-roughcut-v1.mp4`), segment by segment, with the line to say over each. | Recording the voice-over |

## Delivered footage

`~/Desktop/locant-film/v4/locant-demo-reel-v5.mp4` is a silent 105 s review reel of seven scene files in the same folder
(`sceneA-comp.mp4` the ball trigger, the loop and the Cursor agent, `sceneB-comp.mp4` Before & After, `sceneC-comp.mp4`
the ball and ring, `sceneD-comp.mp4` three hovers, `sceneD2-comp.mp4` a web page, `sceneE1-comp.mp4` Codex,
`sceneE2-comp.mp4` Claude Code), all
2560x1440 at 60 fps from a 2x capture of a compact stage on the LG with Locant 0.7.1. Cut the scene files under the
narration; the reel is for review only. The v3 footage stays in `~/Desktop/locant-film/v3/`.

Section 2 cutaways are in `~/Desktop/locant-film/v4/build/`: seven clips from the Sep 13 build recording at the
beats in `05` (`build-canvas`, `build-scaffold`, `build-v01-timer`, `build-null-element`, `build-decision`,
`build-v03-plan`, `build-v04-timer`), a 20 s time-lapse of the three-hour window (`build-timelapse-3h.mp4`), and the
site's ladder and action cards as 2× stills and one-row-per-second reveals (`site-ladder*`, `site-actions*`).
The section 4 measurement lives in `~/Desktop/locant-film/v4/measure/` (`results.tsv`, the six run transcripts, the
screenshot and the Locant payload used).

## Order of work

1. Record the demo takes (`02`). These are the raw footage for everything else.
2. Run the before/after measurement (`03`) and fill the numbers into the table. Do this before recording voice, so
   the narration says real numbers.
3. Record the voice-over (`04`) in one sitting.
4. Cut the full video (`01`) to the voice track. Trim, never stretch.

## Two things the brief requires you to say on camera

- **Time.** The brief caps the exercise at 3 hours. The site ribbon says "v0.4 built in 3 hours" and the git log shows
  two days of commits. Say plainly which part was built inside the window and which part was already there.
- **Existing project.** The brief allows an existing project only if you are its sole author, and asks that this be
  called out explicitly in the submission. Locant is sole-authored, so say so.

Both lines are in section 2 of the scripts and were confirmed on Sep 15: "Versions 0.1 to 0.4 were built inside
the three-hour window, timer running. 0.5 came the next day. I'm the only author."

## Recording setup (applies to every take)

- One display, 2056×1329 pt, 2×. Hide desktop icons, use the Tahoe Day wallpaper (the site captures use it, so the
  video and the site read as one thing).
- Record with Screen Studio or QuickTime at 60 fps, cursor at default size, keystroke display on for hotkeys.
- Light appearance. The overlay label and the Before & After window are easier to read in a compressed video.
- Quit every other Locant build. Only `/Applications/Locant.app` runs (same bundle id, see the memory note on TCC).
- Claude Code in a terminal at 16 pt or larger, one pane, no tmux status bars. Start every take from a fresh session.
- The target app: the iOS Simulator running your own app, because that is the case Locant infers as `fix` and where
  the automatic after-capture can re-find the element after a rebuild. The README's example (`captureButton`) is the scripted target;
  substitute your real identifier everywhere it appears.
