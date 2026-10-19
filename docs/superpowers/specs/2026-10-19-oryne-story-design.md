# Oryne story page: design

**Date:** 2026-10-19 · **Branch:** `am/locant-oryne-redesign-story-f88439` · **Status:** design approved in chat on 2026-10-19. This spec waits for Malik's review. No images are built and no page is written before that.

## Goal

A page on Locant's site that tells one real working session: the tweak pass on Oryne on Oct 18, 2026, from 22:18 to 23:57, done by pointing with Locant and pasting into Claude Code. It is a design story (what changed and why) and the evidence for Locant as a design-tweak tool. A promo film is cut from it later; its six close-ups are the film's beats.

## Decisions

| Decision | Choice | Source |
|---|---|---|
| Home | `locant.malikzhang.com/oryne/`: `site/oryne/index.html`, images in `site/oryne/assets/`. The home page gets one link (end of the Why Locant section); its hero and tagline stay. | Malik, chat |
| Arc | One night: the tweak pass after the Oct 18 usability test. Six close-ups, the rest as a timeline. | Malik, chat |
| After-shots | Featured pairs: rebuild the commit that answered the note and crop the same frame. Timeline: one build. | Malik, chat |
| Window | 22:18 to 23:57, not to 02:10. The captures stop at 23:46 and their last answer lands at 23:57; after midnight there is one capture (01:51), never pasted by id. | Facts table, changed from the chat design |
| Pinned "after" build | `d854071` (23:57), not the 02:10 commit, so nothing after midnight is credited to pointing. | Changed from the chat design |
| Hero pair | `f271e77` (21:43, the usability-test commit, the last one before the pass) against `d854071`. Not the App Store build: the Oct 17 work (Tide, the serif, the phone refocus) came from a spec, with no captures. | Changed from the chat design |
| The voice note | Not an origin story. Oryne's store on the iPhone 17 Pro simulator dates it Oct 18, 10:39 (not seed data, `ZISEXAMPLE` 0). The page may say: that morning I told Oryne why Locant exists; that night Locant did the tweak pass on Oryne. | Checked |

## Page

One column, `docs/brand.md` throughout: system font, the site's colors and its one blue, light and dark, a 16 px side gutter on phones, no horizontal scroll.

1. **Hero.** Working title "One night with Oryne". One line in the design-tweak pitch: after a usability test, I fixed Oryne's details by pointing at them. Two phones on the same screen: `f271e77` and `d854071`.
2. **Setup.** Three sentences. Oryne in one line, linked to oryne.malikzhang.com. The big direction came from a spec on Oct 17. The Oct 18 test with three testers left a list, so this pass was about the details.
3. **The night.** A vertical timeline, 22:18 to 23:57, one row per capture in the facts table: the time, the note (a Chinese note keeps the original with English under it), the before crop, and a small after crop from `d854071`.
4. **Six close-ups**, marked ★ in the facts table. Each one shows the note, the before crop, the after crop from the commit that answered it, that commit's message and both clock times, and one sentence from the chat on what happened. The reversal close-up also shows the middle frame (`04b9cc2`, the lit surface) and Malik's reply.
5. **What the agent received.** The real payload of capture `v0xc` (its Project line names the folder the agent worked in), shortened only where marked.
6. **Honesty line.** One real session, not a test; times come from Locant's capture files and git; a link to `docs/video/11-measurement-worktrees.md` for measured results. No durations offered as speed, no "faster".
7. **Download**, the same button as the home page.

Final copy is written in implementation and approved by Malik.

## Facts table

Times are Oct 18, 2026, Pacific. "Pasted" is the first chat message in Claude Code session `94a84403` that carries the capture id. The answer is the first commit on `feat/site-new-app` after the paste whose message names the change. Rows marked *confirm* get checked against the chat before the page uses them.

| # | Capture | Pointed | Pasted | Element | Note | Answer |
|---|---|---|---|---|---|---|
| 1 | `9xck` | 22:18 | 22:18 | drawn region | this part, refine the layout, 3 icons same size, smaller gap, consistent and coherent. | `359a3f9` 22:31 "…one even toolbar group" *confirm* |
| 2 | `aa9m` | 22:45 | 22:48 | Grow a branch, Ask Ocean | the 2 buttons needs to refined, a little taller, more coherent in the app | `f73eb28` 22:54 "Liquid Glass on every control, 44 pt throughout…" |
| 3 | `senb` | 22:46 | 22:48 | navigation stack | this part needs to be coherent as well, especially the size and layout of the buttons, and the paddings… | `f73eb28` 22:54 |
| 4 ★ | `q9d4` | 22:47 | 22:48 | card titles | title texts in the cards are a little too big and too bold to me, feels not delicate… | `f73eb28` 22:54 "…lighter tile titles…" |
| 5 | `tl9f` | 22:48 | 22:48 | theme line | the bubbles outside of the themes are all gone, why? I want the themes clickable… | `f73eb28` 22:54 "…tappable theme chips…" |
| 6 | `4rgb` | 22:50 | 22:58 | Open current | I don't see the needs for this, try a better way or better information hierarchy… | `bcfba3b` 23:00 "Currents: one entry per current, its name opens it…" |
| 7 | `w4n4` | 23:05 | 23:06 | Nearby | (no note) | `5b6ee1c` 23:11 "Content-layer buttons are matte capsules…" *confirm* |
| 8 ★ | `vtw2` | 23:12 | 23:16 | transcript, More | The "More" button here is not obvious, and hierarchy is not right… | `9355f69` 23:22 "…transcript fades with a read-more button…" |
| 9 | `k88t` | 23:13 | 23:16 | Tide heading | Is the position too high? Check if it meets the UX Standard of Mobile Design and Apple Mobile design rules | `9355f69` 23:22 "Native large-title layout for tab headers…" |
| 10 | `kxs3` | 23:15 | 23:16 | Library | In library, whenever I drag down, the whole page lags… | `9355f69` 23:22 "…Library scroll no longer re-renders the grid every frame" |
| 11 | `95js` | 23:16 | 23:16 | navigation stack | the button size here still are not aligned with the bottons on the main page. | `9355f69` 23:22 "…system-sized tools…" |
| 12 ★ | `c51c` | 23:17 | 23:27 | Nearby | Try to add some shadows or little light designs on all cards and buttons… | `04b9cc2` 23:29 lit surface → Malik 23:29:30 → `b2dd87f` 23:30 "Surfaces are one flat fill on a soft shadow; no top-down light" |
| 13 | `hq5y` | 23:31 | 23:32 | Ask suggestion | 这里的字体用的什么 design system?是单独的hierarchy吗？我感觉在这不够精致 | `7285f2b` 23:34 "Ask suggestions as quiet reference lines…" |
| 14 ★ | `bjzo` | 23:32 | 23:32 | All currents | 我觉得这个按钮的highlight太抢眼了，你觉得呢 | `7285f2b` 23:34 "…All currents in the section label's mist" |
| 15 ★ | `ehe6` | 23:33 | 23:34 | Ocean settings (gear) | 你觉得library里需要有settings吗？ | `74455d5` 23:37 "Library: one sort-and-filter menu, no gear (settings live on Tide)" |
| 16 ★ | `75vn` | 23:34 | 23:34 | Arrangement | 你觉得这个feature需要做成一个常驻的button吗？ | `74455d5` 23:37 (one close-up with row 15) |
| 17 ★ | `v0xc` | 23:37 | 23:38 | send button | 这个发送的button highlight之后你觉得和我整个app的风格搭吗？… | `b15f960` 23:39 "Send and release arrows stay glass…"; Locant's own after-shots to 23:43 |
| 18 | `fqpv` | 23:43 | 23:46 | Whisper button | (no note) | `175d1d2` 23:52 or `d854071` 23:57 *confirm* |

Capture ids are the last block of `yyyyMMdd-HHmmss-xxxx` in `~/Pictures/Locant`. Left out: `3839` and `0ifo` (00:11, Sort and filter, note "yes") and `f9j7` (01:51), none pasted by id; check session `aef09ad8` for an image-only paste before deciding they stay out.

**Translations** (drafts; Malik approves each):

- Row 13: What design system is the type here from? Is it a separate hierarchy? It doesn't feel refined enough here.
- Row 14: I think this button's highlight grabs too much attention. What do you think?
- Row 15: Do you think the Library needs settings?
- Row 16: Do you think this feature needs to be a button that's always there?
- Row 17: Now that the send button lights up, do you think it fits the style of my whole app? It's too bright, too much contrast. It's what Apple does, but it wipes out the original texture completely.
- Malik's reply at 23:29:30 (row 12): With the light added it feels a bit cheap, it doesn't look good. A soft shadow is fine, but light straight from the top definitely isn't. I don't like it like this; I want it flatter.

## Images

- **Befores:** the capture PNGs, unchanged (2×, element + 40 pt), exported for the web.
- **Featured afters:** builds of `f73eb28`, `9355f69`, `04b9cc2`, `b2dd87f`, `7285f2b`, `74455d5`, `b15f960`, each cropped to its capture's frame.
- **Timeline afters and the hero's right phone:** one build of `d854071`. **The hero's left phone:** one build of `f271e77`.
- **Builds:** `git archive <commit>` into the scratchpad (no new worktrees in inspire-ocean), `xcodegen generate` (the xcodeproj is not tracked), a simulator build.
- **Simulator:** a new iPhone 17 Pro, iOS 26.5, made for this and deleted afterwards. Its data is a sqlite `.backup` copy of `InspireOcean.store` from Malik's iPhone 17 Pro simulator, so the before and after crops show the same thoughts. Malik's simulator is never written to. **Never sign the new simulator into iCloud:** the store is CloudKit-backed, and an old build syncing could write into Malik's real Ocean.
- **Crops:** Device Hub showed the device at one size all night (full-width elements share x 136.3 and width 323.9 in every sidecar). Derive the Device Hub point to device pixel transform once by locating one before crop in a screenshot of its own commit, check it on two more, then apply it to every crop.
- **Navigation:** deep links where Oryne has them, otherwise the CGEvent recipes in the headless-testing notes. Say before a run, since Malik uses the same Mac.
- **Weight:** each image at most 200 KB, the page at most 5 MB.

## Rules

- **Privacy.** The crops show Malik's real thoughts, not seed data. Before the page is published, Malik reviews a contact sheet of every image; a crop he flags is replaced or dropped.
- **Facts.** Every time, quote and translation on the page appears in the facts table, and every row traces to a capture file, a commit or a chat line.
- **Claims.** Clock times only; no speed claim. Measurement v6 found no speed edge on design tweaks in an app without identifiers.

## Verification

- Headless Chrome at 1280 and 375 px, light and dark; no horizontal scroll at 375.
- Every image loads; the links between home and story, the download, and the report resolve.
- Each time on the page matches the facts table.
- The Vercel preview on the PR serves `/oryne/`.

## Out of scope

The film, any change to the home page's pitch, new measurements, changes to Oryne's code, and merging (Malik merges).

## Open for Malik

1. The six close-ups: keep them or swap one (alternates: row 10 Library lag, row 9 Tide position, row 6 Currents).
2. The hero's screen.
3. The title.
4. Whether the morning voice note gets a line on the page.
