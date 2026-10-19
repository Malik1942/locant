# Oryne Story Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `locant.malikzhang.com/oryne/`, a page that tells the Oct 18, 2026 tweak pass on Oryne (22:18 to 23:57) capture by capture, from Locant's own files, the Claude Code chats, and git.

**Architecture:** Every fact lives in one generated file, `~/Desktop/oryne-story/facts.json`, built from the sources and checked against them. Images come from Locant's capture PNGs (befores) and from 11 historical Oryne builds run on a throwaway simulator that holds a copy of Malik's data (afters). A small script fills the page's timeline and close-ups from `facts.json`; the rest of the page is hand-written static HTML in the site's style.

**Tech Stack:** Static HTML/CSS (no build step, as the site), Python 3 with numpy and Pillow (already in the user site-packages), zsh, `xcrun simctl`, XcodeGen, `xcodebuild`, Node 26 + headless Chrome over CDP for render checks.

**Spec:** `docs/superpowers/specs/2026-10-19-oryne-story-design.md` (approved 2026-10-19). If this plan and the spec disagree, the spec wins; say so and continue.

## Global Constraints

- Read only, never written: `/Users/malik/Documents/inspire-ocean` (only `git archive`, `git log`, `git rev-parse`, `git merge-base`), Malik's simulator `0EBF66EE-3E7D-48F9-9D44-E7B1A58DACF1`, `~/Pictures/Locant`, the chats in `~/.claude/projects/-Users-malik-Documents-inspire-ocean--claude-worktrees-oryne-product-opportunities-a913cb/`.
- Working files only in `~/Desktop/oryne-story/` (written `W` below). Create folders by testing with `[ -e path ]` first and then plain `mkdir` (APFS is case-insensitive).
- Locant repo changes only: `site/oryne/index.html`, `site/oryne/assets/*.webp`, one line in `site/index.html`, and this plan. Commit messages in the form `area: what changed`.
- **The Locant repo is public: pushing publishes.** No push and no PR before Malik says yes at the Task 10 checkpoint. Malik merges.
- **Never sign the story simulator into iCloud.** Its store is CloudKit-backed; an old build syncing could write into Malik's real Ocean.
- Brand: `docs/brand.md`; tokens and base rules copied from `site/index.html` (lines 22–92, 94–179, 445–460). One column, light and dark. Side padding 20 px, as the home page's `body` (the spec's "16 px" is replaced by the site's own 20 px so the two pages share edges).
- Each image at most 200 KB; the page's images at most 5 MB in total.
- Claims: clock times only; no "faster", no durations sold as speed; the honesty line links `docs/video/11-measurement-worktrees.md`.
- Words: "capture" for the act, "payload" for what lands on the clipboard; never "screenshot tool".
- Run Python as `python3` without `-I` (numpy and Pillow live in the user site-packages), from `W`.

## Where this plan departs from the spec, and why

- **Befores are clipped to the phone's screen.** Locant's crops (element + 40 pt) run past the phone into the next window; `q9d4` shows a sidebar of session titles. Clipping is the only edit to Locant's PNGs.
- **Each crop is located on its own, with one calibrated scale.** The spec said "derive the transform once". The Device Hub window moved during the night (the send-button capture's after-shots sit 56 pt left and 140 pt up of the capture), so position is found per capture; the scale `k` is calibrated once on two rows.
- **Navigation uses the iOS Simulator tool, not CGEvent recipes.** It is headless and does not touch Malik's screen.
- **Side padding is the site's 20 px**, not the spec's 16 px, so the two pages share edges.
- **Locant's Project line is not trusted for which build was on screen.** For 9 of the 18 captures it names the Watch worktree, whose branch does not have the redesign; the images (for example `q9d4`'s serif "Drifted in") show the redesign build. Locator builds therefore come from `feat/site-new-app` by time, not from the sidecar's `gitCommit`.

## File Structure

Working folder `~/Desktop/oryne-story/` (outside every repo, like `~/Desktop/locant-film/`):

| Path | Responsibility |
|---|---|
| `bin/make_facts.py` | Builds `facts.json` from sidecars, chats, git and `notes.json`; exits 1 on any problem |
| `bin/chat_after.py` | Prints the chat from the message that pasted a capture |
| `bin/build.sh` | Builds one Oryne commit into `builds/<hash>/Oryne.app` |
| `bin/sim.sh` | The "Oryne story" simulator: create, snapshot data, install, restore, launch, open, shot, delete |
| `bin/shotlist.py` | Lists the (build, screen) screenshots the page needs |
| `bin/locate.py` | Finds a before crop in a screenshot (multi-scale normalized cross-correlation) |
| `bin/crops.py` | Clips, crops and exports every web image into `out/` |
| `bin/sheet.py` | Writes `sheet.html`, the contact sheet for Malik's review |
| `bin/render_page.py` | Fills the page's timeline and close-ups from `facts.json` |
| `bin/check_page.py` | Static checks on the page (images, sizes, times, links) |
| `bin/render.mjs` | Renders the page in headless Chrome at 1280 and 375 px, light and dark |
| `tests/test_*.py` | unittest for make_facts, locate, crops, render_page |
| `notes.json` | Hand-written per row: screen, label, translation, chat lines, stories |
| `facts.json`, `rects.json` | Generated facts; located rectangles |
| `builds/`, `src/`, `dd/`, `data/`, `shots/`, `out/`, `render/` | Build products, sources, DerivedData, the data copy, screenshots, web images, page renders |

Locant repo (this worktree):

| Path | Responsibility |
|---|---|
| `site/oryne/index.html` | The story page; root-absolute URLs (`/oryne/assets/…`, `/assets/…`) so it works at `/oryne/` on Vercel and from a local server |
| `site/oryne/assets/*.webp` | The page's images, copied from `W/out/` |
| `site/index.html` | One added line at the end of the Why Locant section |

---

### Task 1: Working folder and facts.json

**Files:**
- Create: `W/bin/make_facts.py`, `W/tests/test_make_facts.py`, `W/notes.json`

**Interfaces:**
- Produces: `facts.json` = `{"rows": [row, …]}`, each row `{"n": int, "capture": str, "pointed": "HH:MM", "pasted": "HH:MM", "element": str, "note": str, "before_png": str, "answers": [{"hash", "time", "subject"}], "featured": bool, "locator": str, …notes.json fields}`. Module functions `hhmm(iso) -> str`, `first_paste(lines, capture_id) -> str|None`, `build_row(n, cid, answers, featured, locator, sidecar, paste_iso, commits, notes) -> (dict, list[str])`, constants `W`, `CHATS`, `REPO`.

- [ ] **Step 1: Create the working folder**

```bash
[ -e ~/Desktop/oryne-story ] && echo EXISTS || mkdir ~/Desktop/oryne-story && cd ~/Desktop/oryne-story && mkdir bin tests builds src shots out render && echo made
```
Expected: `made`. If it prints `EXISTS`, stop and ask Malik.

- [ ] **Step 2: Write the failing tests** — `W/tests/test_make_facts.py`

```python
import json, os, sys, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "bin"))
import make_facts as mf


class MakeFacts(unittest.TestCase):
    def test_hhmm_reads_utc_and_offsets_as_pacific(self):
        self.assertEqual(mf.hhmm("2026-10-19T06:38:12.345Z"), "23:38")
        self.assertEqual(mf.hhmm("2026-10-18T23:37:59-07:00"), "23:37")

    def test_first_paste_takes_the_first_user_line(self):
        lines = [
            "not json abc-1",
            json.dumps({"type": "assistant", "timestamp": "2026-10-19T06:00:00Z", "x": "abc-1"}),
            json.dumps({"type": "user", "timestamp": "2026-10-19T06:01:00Z", "x": "abc-1"}),
            json.dumps({"type": "user", "timestamp": "2026-10-19T06:02:00Z", "x": "abc-1"}),
        ]
        self.assertEqual(mf.first_paste(lines, "abc-1"), "2026-10-19T06:01:00Z")
        self.assertIsNone(mf.first_paste(lines, "zzz"))

    def test_build_row_flags_old_and_off_branch_answers(self):
        side = {"createdAt": "2026-10-18T23:37:59-07:00", "note": "n", "element": None,
                "image": {"path": "/x.png", "scale": 2}}
        commits = [{"hash": "aaa", "time": "23:30", "iso": "2026-10-18T23:30:00-07:00",
                    "subject": "s", "on_branch": False}]
        row, problems = mf.build_row(17, "id", ["aaa"], True, "b", side,
                                     "2026-10-19T06:38:00Z", commits, {"17": {"translation": "t"}})
        self.assertEqual((row["pointed"], row["pasted"]), ("23:37", "23:38"))
        self.assertEqual(row["element"], "drawn region")
        self.assertEqual(row["translation"], "t")
        self.assertIn("aaa not on feat/site-new-app", problems)
        self.assertIn("aaa is older than the paste", problems)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 3: Run it to see it fail**

Run: `cd ~/Desktop/oryne-story && python3 -m unittest tests/test_make_facts.py`
Expected: `ModuleNotFoundError: No module named 'make_facts'`

- [ ] **Step 4: Write `W/bin/make_facts.py`**

```python
#!/usr/bin/env python3
"""Build facts.json: one row per capture of the pass, from Locant's sidecars, the Claude Code chats,
git, and the hand-written notes.json. Exits 1 if any row has a problem."""
import glob, json, os, subprocess, sys
from datetime import datetime
from zoneinfo import ZoneInfo

PT = ZoneInfo("America/Los_Angeles")
W = os.path.expanduser("~/Desktop/oryne-story")
CAPS = os.path.expanduser("~/Pictures/Locant")
CHATS = os.path.expanduser(
    "~/.claude/projects/-Users-malik-Documents-inspire-ocean--claude-worktrees-oryne-product-opportunities-a913cb")
REPO = "/Users/malik/Documents/inspire-ocean"
BRANCH = "feat/site-new-app"

# n, capture id, answer commits, featured, locator build (the newest built commit before the capture)
ROWS = [
    (1, "20261018-221831-9xck", ["359a3f9"], False, "f271e77"),
    (2, "20261018-224527-aa9m", ["f73eb28"], False, "dbdc73f"),
    (3, "20261018-224627-senb", ["f73eb28"], False, "dbdc73f"),
    (4, "20261018-224746-q9d4", ["f73eb28"], True, "dbdc73f"),
    (5, "20261018-224840-tl9f", ["f73eb28"], False, "dbdc73f"),
    (6, "20261018-225029-4rgb", ["bcfba3b"], False, "dbdc73f"),
    (7, "20261018-230510-w4n4", ["5b6ee1c"], False, "f73eb28"),
    (8, "20261018-231257-vtw2", ["9355f69"], True, "8de92c3"),
    (9, "20261018-231342-k88t", ["9355f69"], False, "8de92c3"),
    (10, "20261018-231524-kxs3", ["9355f69"], False, "8de92c3"),
    (11, "20261018-231612-95js", ["9355f69"], False, "8de92c3"),
    (12, "20261018-231712-c51c", ["04b9cc2", "b2dd87f"], True, "8de92c3"),
    (13, "20261018-233140-hq5y", ["7285f2b"], False, "b2dd87f"),
    (14, "20261018-233204-bjzo", ["7285f2b"], True, "b2dd87f"),
    (15, "20261018-233356-ehe6", ["74455d5"], True, "b2dd87f"),
    (16, "20261018-233419-75vn", ["74455d5"], True, "b2dd87f"),
    (17, "20261018-233759-v0xc", ["b15f960"], True, "74455d5"),
    (18, "20261018-234349-fqpv", ["175d1d2"], False, "b15f960"),
]
CONFIRM = {1, 7, 18}  # answers still to check against the chat (Task 2)


def hhmm(iso):
    return datetime.fromisoformat(iso.replace("Z", "+00:00")).astimezone(PT).strftime("%H:%M")


def first_paste(lines, capture_id):
    for line in lines:
        if capture_id not in line:
            continue
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if d.get("type") == "user":
            return d["timestamp"]
    return None


def chat_lines():
    for f in sorted(glob.glob(os.path.join(CHATS, "*.jsonl"))):
        with open(f, encoding="utf-8") as fh:
            yield from fh


def git(*args):
    return subprocess.run(["git", "-C", REPO, *args], capture_output=True, text=True, check=True).stdout.strip()


def commit(h):
    t, s = git("log", "-1", "--format=%cI%x09%s", h).split("\t", 1)
    on = subprocess.run(["git", "-C", REPO, "merge-base", "--is-ancestor", h, BRANCH]).returncode == 0
    return {"hash": h, "time": hhmm(t), "iso": t, "subject": s, "on_branch": on}


def element_name(e):
    if not e:
        return "drawn region"
    return e.get("label") or e.get("identifier") or e.get("role")


def build_row(n, cid, answers, featured, locator, sidecar, paste_iso, commits, notes):
    problems = []
    if paste_iso is None:
        problems.append("never pasted by id")
    for c in commits:
        if not c["on_branch"]:
            problems.append(f"{c['hash']} not on {BRANCH}")
        if paste_iso and datetime.fromisoformat(c["iso"]) < datetime.fromisoformat(paste_iso.replace("Z", "+00:00")):
            problems.append(f"{c['hash']} is older than the paste")
    row = {
        "n": n, "capture": cid,
        "pointed": hhmm(sidecar["createdAt"]),
        "pasted": hhmm(paste_iso) if paste_iso else None,
        "element": element_name(sidecar.get("element")),
        "note": sidecar.get("note") or "",
        "before_png": sidecar["image"]["path"],
        "answers": [{k: c[k] for k in ("hash", "time", "subject")} for c in commits],
        "featured": featured, "locator": locator,
        **notes.get(str(n), {}),
    }
    return row, problems


def main():
    lines = list(chat_lines())
    notes_path = os.path.join(W, "notes.json")
    notes = json.load(open(notes_path, encoding="utf-8")) if os.path.exists(notes_path) else {}
    rows, bad = [], 0
    for n, cid, answers, featured, locator in ROWS:
        side = json.load(open(os.path.join(CAPS, f"locant-devicehub-{cid}.json"), encoding="utf-8"))
        row, problems = build_row(n, cid, answers, featured, locator, side,
                                  first_paste(lines, cid), [commit(h) for h in answers], notes)
        if n in CONFIRM:
            problems.append("answer not confirmed against the chat yet")
        for p in problems:
            print(f"row {n}: {p}")
        bad += len(problems)
        rows.append(row)
    with open(os.path.join(W, "facts.json"), "w", encoding="utf-8") as fh:
        json.dump({"rows": rows}, fh, ensure_ascii=False, indent=1)
    print(f"{len(rows)} rows, {bad} problems")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
```

- [ ] **Step 5: Run the tests**

Run: `cd ~/Desktop/oryne-story && python3 -m unittest tests/test_make_facts.py`
Expected: `Ran 3 tests … OK`

- [ ] **Step 6: Write the first `W/notes.json`** (the featured rows' screens and labels, the spec's draft translations; Task 2 completes it)

```json
{
 "4": {"screen": "tide-drifted", "label": "the card titles under Drifted in", "closeup": "titles"},
 "8": {"screen": "thought-voice", "label": "the transcript's More", "closeup": "more"},
 "12": {"screen": "tide-top", "label": "the Nearby button", "closeup": "light",
        "reply_time": "23:29", "reply": "加完光影感觉有点low，不好看了，柔的投影可以，光影直上直下肯定不行，我不喜欢现在这种，我想要更平面化",
        "reply_en": "With the light added it feels a bit cheap, it doesn't look good. A soft shadow is fine, but light straight from the top definitely isn't. I don't like it like this; I want it flatter."},
 "13": {"translation": "What design system is the type here from? Is it a separate hierarchy? It doesn't feel refined enough here."},
 "14": {"label": "All currents", "closeup": "currents",
        "translation": "I think this button's highlight grabs too much attention. What do you think?"},
 "15": {"screen": "library-top", "label": "the Library's settings gear", "closeup": "settings",
        "translation": "Do you think the Library needs settings?"},
 "16": {"screen": "library-top", "label": "the Arrangement button", "closeup": "settings",
        "translation": "Do you think this feature needs to be a button that's always there?"},
 "17": {"screen": "ask-typed", "label": "the send button", "closeup": "send",
        "translation": "Now that the send button lights up, do you think it fits the style of my whole app? It's too bright, too much contrast. It's what Apple does, but it wipes out the original texture completely."}
}
```

- [ ] **Step 7: Generate facts.json and compare with the spec**

Run: `cd ~/Desktop/oryne-story && python3 bin/make_facts.py; python3 -c "import json; [print(r['n'], r['pointed'], r['pasted'], ' '.join(a['hash']+' '+a['time'] for a in r['answers'])) for r in json.load(open('facts.json'))['rows']]"`

Expected: exit 1 with exactly three problems (`row 1/7/18: answer not confirmed against the chat yet`), then these lines, which must match the spec's facts table:
```
1 22:18 22:18 359a3f9 22:31
2 22:45 22:48 f73eb28 22:54
3 22:46 22:48 f73eb28 22:54
4 22:47 22:48 f73eb28 22:54
5 22:48 22:48 f73eb28 22:54
6 22:50 22:58 bcfba3b 23:00
7 23:05 23:06 5b6ee1c 23:11
8 23:12 23:16 9355f69 23:22
9 23:13 23:16 9355f69 23:22
10 23:15 23:16 9355f69 23:22
11 23:16 23:16 9355f69 23:22
12 23:17 23:27 04b9cc2 23:29 b2dd87f 23:30
13 23:31 23:32 7285f2b 23:34
14 23:32 23:32 7285f2b 23:34
15 23:33 23:34 74455d5 23:37
16 23:34 23:34 74455d5 23:37
17 23:37 23:38 b15f960 23:39
18 23:43 23:46 175d1d2 23:52
```
Any other difference: stop and report it.

(Nothing to commit: the working folder is outside every repo.)

---

### Task 2: Confirm the open rows and complete notes.json

**Files:**
- Create: `W/bin/chat_after.py`
- Modify: `W/bin/make_facts.py` (`ROWS` rows 1, 7, 18 if the chat says otherwise; `CONFIRM`), `W/notes.json`

**Interfaces:**
- Consumes: `make_facts.CHATS`, `make_facts.hhmm`.
- Produces: `notes.json` with, for every row 1–18, `screen` (one of `tide-top`, `tide-drifted`, `library-top`, `ask-typed`, `thought-voice`, `current`, or a new name you define here with how to reach it) and `label`; for rows 7 and 18 (no note) `chat_note` if Malik said what he wanted in the chat; for each close-up's first row, `story` (one sentence) and `story_time`.

- [ ] **Step 1: Write `W/bin/chat_after.py`**

```python
#!/usr/bin/env python3
"""Print the chat from the first user message containing KEY: time (Pacific), speaker, text.
Usage: chat_after.py KEY [max_messages] [--full]"""
import glob, json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_facts import CHATS, hhmm


def text_of(d):
    c = d.get("message", {}).get("content")
    if isinstance(c, str):
        return c
    return " ".join(x.get("text", "") for x in c or [] if isinstance(x, dict) and x.get("type") == "text")


def main():
    args = [a for a in sys.argv[1:] if a != "--full"]
    full = "--full" in sys.argv
    key, limit = args[0], int(args[1]) if len(args) > 1 else 12
    for f in sorted(glob.glob(os.path.join(CHATS, "*.jsonl"))):
        started, shown = False, 0
        for line in open(f, encoding="utf-8"):
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if d.get("type") not in ("user", "assistant"):
                continue
            if not started and d["type"] == "user" and key in line:
                started = True
                print(f"== {os.path.basename(f)[:8]}")
            if not started:
                continue
            t = text_of(d).strip()
            if not t:
                continue
            print(f"{hhmm(d['timestamp'])} {d['type']}: {t if full else t[:600]}")
            shown += 1
            if shown >= limit:
                return
        if started:
            return
    print("not found")


main()
```

- [ ] **Step 2: Confirm rows 1, 7, 18**

Run each: `cd ~/Desktop/oryne-story && python3 bin/chat_after.py 20261018-221831-9xck 10`, then `… 20261018-230510-w4n4 10`, then `… 20261018-234349-fqpv 10`.
For each, find the assistant message that says it made the change, and the first commit after it. Check with `git -C /Users/malik/Documents/inspire-ocean log --format='%h %cd %s' --date=format:%H:%M feat/site-new-app --since='2026-10-18 22:00' --until='2026-10-19 00:00'`. Edit `ROWS` in `bin/make_facts.py` if the answer differs from the spec's candidate, then remove the row from `CONFIRM`. If rows 7 or 18 have a chat line saying what Malik wanted, put it in `notes.json` as `"chat_note"` (verbatim, with the time as `"chat_note_time"`).

- [ ] **Step 3: Decide the left-out captures**

Run: `cd ~/Desktop/oryne-story && python3 bin/chat_after.py "Sort and filter" 6; python3 bin/chat_after.py "nav bar" 6`
If neither shows Malik pasting `20261019-001144-3839`, `20261019-001147-0ifo` or `20261019-015127-f9j7` into a chat before 23:57, they stay out (the spec's default). Write the result in one line in your report.

- [ ] **Step 4: Name each row's screen and label**

Open every before PNG (`ls ~/Pictures/Locant/locant-devicehub-20261018-2[23]*.png`, using the Read tool to view it) and fill `screen` and `label` in `notes.json` for all 18 rows. Screens and how to reach them (Task 5 uses this):

| screen | how to reach it |
|---|---|
| `tide-top` | `bin/sim.sh launch ocean`, no scroll |
| `tide-drifted` | `bin/sim.sh launch ocean`, swipe up until the "Drifted in" heading is where the before shows it |
| `library-top` | `bin/sim.sh launch library`, no scroll |
| `ask-typed` | `bin/sim.sh launch ask`, tap the capture bar, type `Asdfasf` |
| `thought-voice` | `bin/sim.sh launch ocean`, then `bin/sim.sh open oryne://node/47413ede-87a2-48fb-a3d9-17e79ed3e278` (the "Screenshot with context" voice note), scroll until "Transcript" is where the before shows it |
| `current` | `bin/sim.sh launch ocean`, tap the current named in the before |

A row that fits none of them gets a new screen name and a one-line recipe in `notes.json` as `"how"`.

- [ ] **Step 5: Write each close-up's story line**

For rows 4, 8, 12, 14, 15, 17 run `python3 bin/chat_after.py <capture id> 8` and write one plain sentence in `notes.json` as `"story"`, saying what the agent said it changed or why, in your words, with the time of the message it rests on as `"story_time"`. For row 8 add: `"voice_note": "The transcript in this capture is a voice note I recorded in Oryne that morning, about why Locant exists."`

- [ ] **Step 6: Regenerate and check**

Run: `cd ~/Desktop/oryne-story && python3 bin/make_facts.py && python3 -c "import json; rows=json.load(open('facts.json'))['rows']; missing=[r['n'] for r in rows if not r.get('screen') or not r.get('label')]; print('missing', missing)"`
Expected: `18 rows, 0 problems` and `missing []`.

---

### Task 3: Build the 11 commits

**Files:**
- Create: `W/bin/build.sh`

**Interfaces:**
- Produces: `W/builds/<hash>/Oryne.app` for `f271e77 dbdc73f f73eb28 8de92c3 9355f69 04b9cc2 b2dd87f 7285f2b 74455d5 b15f960 d854071`.

- [ ] **Step 1: Write `W/bin/build.sh`** and `chmod +x W/bin/*.sh`

```zsh
#!/bin/zsh
# Build one Oryne commit for the simulator into builds/<hash>/Oryne.app. Reads the repo, never writes to it.
# The custom DerivedData path keeps these builds away from the one Locant reads for its Project line.
set -euo pipefail
h=$1
W=~/Desktop/oryne-story
R=/Users/malik/Documents/inspire-ocean
out=$W/builds/$h
if [ -e $out/Oryne.app ]; then echo "have $out/Oryne.app"; exit 0; fi
src=$W/src/$h
rm -rf $src
mkdir -p $src
git -C $R archive "$h" | tar -x -C $src
(cd $src && xcodegen generate --quiet)
run() {
  xcodebuild -project $src/Oryne.xcodeproj -scheme Oryne -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath $W/dd build -quiet
}
run || run   # Xcode 27 sometimes fails once with "disk I/O error" on a fresh build.db
mkdir -p $out
cp -R $W/dd/Build/Products/Debug-iphonesimulator/Oryne.app $out/
echo "built $h -> $out/Oryne.app"
```

- [ ] **Step 2: Build one and check it**

Run: `~/Desktop/oryne-story/bin/build.sh d854071 && plutil -extract CFBundleIdentifier raw ~/Desktop/oryne-story/builds/d854071/Oryne.app/Info.plist`
Expected: `built d854071 -> …` then `com.inspireocean.app`. If the product has another name, `ls ~/Desktop/oryne-story/dd/Build/Products/Debug-iphonesimulator/` and fix the `cp` line.

- [ ] **Step 3: Build the rest** (run in the background; about 3–5 minutes each)

Run: `for h in f271e77 dbdc73f f73eb28 8de92c3 9355f69 04b9cc2 b2dd87f 7285f2b 74455d5 b15f960; do ~/Desktop/oryne-story/bin/build.sh $h || echo "FAILED $h"; done`
Expected: 10 `built …` lines, no `FAILED`.

---

### Task 4: The story simulator with a copy of Malik's data

**Files:**
- Create: `W/bin/sim.sh`

**Interfaces:**
- Consumes: `W/builds/<hash>/Oryne.app`.
- Produces: commands `sim.sh create|snapshot|install <hash>|restore|launch <ocean|library|ask>|open <url>|shot <hash> <screen>|delete`; `W/udid`; `W/data/` (the store, its support folder, two preference plists).

- [ ] **Step 1: Write `W/bin/sim.sh`**

```zsh
#!/bin/zsh
# The "Oryne story" simulator: a new iPhone 17 Pro holding a copy of Malik's data.
# NEVER sign it into iCloud: the store is CloudKit-backed.
set -euo pipefail
W=~/Desktop/oryne-story
SRC_DEV=0EBF66EE-3E7D-48F9-9D44-E7B1A58DACF1   # Malik's iPhone 17 Pro: read only
BUNDLE=com.inspireocean.app
GROUP=group.com.inspireocean.shared
udid() { cat $W/udid; }
containers() {
  D=$(xcrun simctl get_app_container $(udid) $BUNDLE data)
  G=$(xcrun simctl get_app_container $(udid) $BUNDLE $GROUP 2>/dev/null || echo "$D/Library/Application Support")
}
case ${1:-} in
create)
  if [ -e $W/udid ]; then echo "exists: $(udid)"; exit 0; fi
  xcrun simctl create "Oryne story" "iPhone 17 Pro" com.apple.CoreSimulator.SimRuntime.iOS-26-5 > $W/udid
  xcrun simctl boot $(udid)
  xcrun simctl status_bar $(udid) override --time 9:41 --cellularBars 4 --wifiBars 3 --batteryState charging --batteryLevel 100
  echo "created $(udid)";;
snapshot)
  SG=$(xcrun simctl get_app_container $SRC_DEV $BUNDLE $GROUP)
  SD=$(xcrun simctl get_app_container $SRC_DEV $BUNDLE data)
  mkdir -p $W/data
  sqlite3 -readonly "$SG/InspireOcean.store" ".backup '$W/data/InspireOcean.store'"
  cp -R "$SG/.InspireOcean_SUPPORT" $W/data/
  cp "$SG/Library/Preferences/$GROUP.plist" $W/data/group.plist
  cp "$SD/Library/Preferences/$BUNDLE.plist" $W/data/app.plist
  for k in CloudKitAccountInfoCache CKPerBootTasks CKStartupTime; do plutil -remove $k $W/data/app.plist 2>/dev/null || true; done
  sqlite3 $W/data/InspireOcean.store "select count(*), sum(ZISEXAMPLE) from ZNODE";;
install)
  xcrun simctl terminate $(udid) $BUNDLE 2>/dev/null || true
  xcrun simctl install $(udid) $W/builds/$2/Oryne.app
  "$0" restore
  echo "installed $2";;
restore)
  xcrun simctl terminate $(udid) $BUNDLE 2>/dev/null || true
  containers
  rm -rf "$G/InspireOcean.store" "$G/InspireOcean.store-wal" "$G/InspireOcean.store-shm" "$G/.InspireOcean_SUPPORT"
  mkdir -p "$G/Library/Preferences" "$D/Library/Preferences"
  cp $W/data/InspireOcean.store "$G/"
  cp -R $W/data/.InspireOcean_SUPPORT "$G/"
  cp $W/data/group.plist "$G/Library/Preferences/$GROUP.plist"
  cp $W/data/app.plist "$D/Library/Preferences/$BUNDLE.plist";;
launch)
  xcrun simctl terminate $(udid) $BUNDLE 2>/dev/null || true
  SIMCTL_CHILD_OCEAN_START_TAB=$2 xcrun simctl launch $(udid) $BUNDLE;;
open)
  xcrun simctl openurl $(udid) "$2";;
shot)
  mkdir -p $W/shots/$2
  xcrun simctl io $(udid) screenshot --type=png $W/shots/$2/$3.png >/dev/null 2>&1
  echo $W/shots/$2/$3.png;;
count)
  containers
  sqlite3 "$G/InspireOcean.store" "select count(*), sum(ZISEXAMPLE) from ZNODE";;
delete)
  xcrun simctl shutdown $(udid) 2>/dev/null || true
  xcrun simctl delete $(udid)
  rm $W/udid
  rm -rf $W/data;;
*)
  echo "usage: sim.sh create|snapshot|install <hash>|restore|launch <tab>|open <url>|shot <hash> <screen>|count|delete"; exit 2;;
esac
```
(`count` is an extra subcommand for the checks below.)

- [ ] **Step 2: Create the simulator and copy the data**

Run: `cd ~/Desktop/oryne-story && chmod +x bin/*.sh && bin/sim.sh create && bin/sim.sh snapshot`
Expected: `created <UDID>` then `15|0` (15 thoughts, none of them examples). A different count is fine if Malik added thoughts since Oct 19; a non-zero second number means example data, so stop and report.

- [ ] **Step 3: First install and the data check**

Run: `cd ~/Desktop/oryne-story && bin/sim.sh install d854071 && bin/sim.sh launch library`
Then, in a separate call (the round trip gives the app time to load; agent shells block `sleep`): `cd ~/Desktop/oryne-story && bin/sim.sh count && bin/sim.sh shot check library`
Expected: `installed d854071`, a launch line, then the same `N|0` as Step 2 (the app did not seed examples) and a PNG path. View `shots/check/library.png` with the Read tool: the Library shows Malik's thoughts (for example "Screenshot with context"), no onboarding. If onboarding shows or the Library is empty, stop and report: the store or the preferences are not where `sim.sh restore` puts them.

- [ ] **Step 4: Confirm no iCloud account**

Never open Settings › Apple Account on this simulator. Run: `xcrun simctl spawn $(cat ~/Desktop/oryne-story/udid) defaults read MobileMeAccounts 2>&1 | head -3`
Expected: an error saying the domain does not exist, or an empty `Accounts` list.

---

### Task 5: Take the screenshots

**Files:**
- Create: `W/bin/shotlist.py`

**Interfaces:**
- Consumes: `facts.json` (`screen`, `locator`, `answers`, `featured`).
- Produces: `W/shots/<hash>/<screen>.png` for every pair `shotlist.py` prints.

- [ ] **Step 1: Write `W/bin/shotlist.py`**

```python
#!/usr/bin/env python3
"""Print the (build, screen) screenshots the page needs, grouped by build so each build is installed once."""
import json, os
from collections import defaultdict

W = os.path.expanduser("~/Desktop/oryne-story")
HERO_SCREEN = "tide-top"   # the hero's screen until Malik picks another at the checkpoint
NOW = "d854071"
rows = json.load(open(os.path.join(W, "facts.json"), encoding="utf-8"))["rows"]
need = defaultdict(set)
need["f271e77"].add(HERO_SCREEN)
need[NOW].add(HERO_SCREEN)
for r in rows:
    need[r["locator"]].add(r["screen"])
    need[NOW].add(r["screen"])
    if r["featured"]:
        for a in r["answers"]:
            need[a["hash"]].add(r["screen"])
for h in sorted(need):
    missing = [s for s in sorted(need[h]) if not os.path.exists(os.path.join(W, "shots", h, s + ".png"))]
    print(h, " ".join(sorted(need[h])), "| missing:", " ".join(missing) or "none")
```

- [ ] **Step 2: List what to take**

Run: `cd ~/Desktop/oryne-story && python3 bin/shotlist.py`
Expected: 11 lines, one per build, every one with missing screens.

- [ ] **Step 3: Take them, one build at a time**

For each build line: `bin/sim.sh install <hash>`, then for each screen follow its recipe from Task 2 Step 4 and run `bin/sim.sh shot <hash> <screen>`. Drive taps, swipes and typing with the iOS Simulator tool (`mcp__Claude_Code_iOS_Simulator__control`, `device` = the UDID in `W/udid`, actions `tap`, `swipe`, `text`, `screenshot`); its first use asks Malik to allow the device. Before each `shot`, view the tool's screenshot and match the scroll position to the row's before PNG. Run `bin/sim.sh restore` and relaunch between screens that typed text, so typing never reaches the store.

- [ ] **Step 4: Check none are missing**

Run: `cd ~/Desktop/oryne-story && python3 bin/shotlist.py`
Expected: every line ends `| missing: none`.

---

### Task 6: Locate each before crop

**Files:**
- Create: `W/bin/locate.py`, `W/tests/test_locate.py`

**Interfaces:**
- Consumes: `facts.json` rows (`before_png`, `locator`, `screen`), `shots/`.
- Produces: `locate.locate(before: PIL.Image, shot: PIL.Image, kmin=0.70, kmax=1.00, step=0.005) -> {"k", "x", "y", "w", "h", "score"}` in screenshot pixels (x, y may be negative: the crop can run past the screen); `rects.json` = `{"<n>": {…locate result…, "shot": "shots/<hash>/<screen>.png", "offset": {}}}`.

- [ ] **Step 1: Write the failing tests** — `W/tests/test_locate.py`

```python
import os, sys, unittest
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "bin"))
import locate as lc


def blocky(h, w, seed):
    rng = np.random.default_rng(seed)
    small = rng.integers(0, 255, (h // 12 + 1, w // 12 + 1)).astype(np.uint8)
    return Image.fromarray(np.kron(small, np.ones((12, 12), np.uint8))[:h, :w])


class Locate(unittest.TestCase):
    def test_ncc_map_is_one_where_the_template_was_cut(self):
        img = np.asarray(blocky(60, 80, 1), dtype=float)
        m = lc.ncc_map(img, img[20:40, 30:60])
        y, x = np.unravel_index(np.argmax(m), m.shape)
        self.assertEqual((y, x), (20, 30))
        self.assertAlmostEqual(m[y, x], 1.0, places=6)

    def test_finds_a_scaled_crop_and_its_k(self):
        shot = blocky(2622, 1206, 2)
        k = 0.85
        patch = shot.crop((300, 900, 900, 1140))
        before = patch.resize((round(600 * 2 * k / 3), round(240 * 2 * k / 3)), Image.BILINEAR)
        r = lc.locate(before, shot)
        self.assertLessEqual(abs(r["x"] - 300), 4)
        self.assertLessEqual(abs(r["y"] - 900), 4)
        self.assertLessEqual(abs(r["k"] - k), 0.011)
        self.assertGreater(r["score"], 0.8)

    def test_finds_a_crop_that_runs_past_the_screen(self):
        shot = blocky(2622, 1206, 3)
        k = 0.85
        canvas = Image.new("L", (1406, 2622), 0)
        canvas.paste(shot, (0, 0))
        patch = canvas.crop((1000, 400, 1400, 700))   # its right 194 px are past the screen's edge, black
        before = patch.resize((round(400 * 2 * k / 3), round(300 * 2 * k / 3)), Image.BILINEAR)
        r = lc.locate(before, shot)
        self.assertLessEqual(abs(r["x"] - 1000), 4)
        self.assertLessEqual(abs(r["y"] - 400), 4)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd ~/Desktop/oryne-story && python3 -m unittest tests/test_locate.py`
Expected: `ModuleNotFoundError: No module named 'locate'`

- [ ] **Step 3: Write `W/bin/locate.py`**

```python
#!/usr/bin/env python3
"""Find a Locant before crop inside a simulator screenshot.
The crop has 2 px per Device Hub point; the screenshot has 3 px per device point;
k = Device Hub points per device point, so the crop scales by 3 / (2k) into screenshot pixels.
Usage: locate.py <n>...   (rows from facts.json; writes rects.json)   or   locate.py --calibrate <n>"""
import json, os, sys
import numpy as np
from PIL import Image

W = os.path.expanduser("~/Desktop/oryne-story")
PAD = 400  # screenshot pixels of black around the screen: a crop may include bezel or another window


def gray(img):
    return np.asarray(img.convert("L"), dtype=np.float64)


def ncc_map(image, tpl):
    """Normalized cross-correlation of tpl at every position where it fits inside image."""
    th, tw = tpl.shape
    ih, iw = image.shape
    t = tpl - tpl.mean()
    tnorm = np.sqrt((t * t).sum())
    out_shape = (ih - th + 1, iw - tw + 1)
    if tnorm == 0 or out_shape[0] < 1 or out_shape[1] < 1:
        return np.zeros((max(out_shape[0], 1), max(out_shape[1], 1)))
    corr = np.fft.irfft2(np.fft.rfft2(image) * np.conj(np.fft.rfft2(t, image.shape)), image.shape)
    corr = corr[: out_shape[0], : out_shape[1]]
    ii = np.pad(image, ((1, 0), (1, 0))).cumsum(0).cumsum(1)
    ii2 = np.pad(image * image, ((1, 0), (1, 0))).cumsum(0).cumsum(1)

    def window(a):
        return a[th:, tw:] - a[:-th, tw:] - a[th:, :-tw] + a[:-th, :-tw]

    s, s2 = window(ii), window(ii2)
    var = np.maximum(s2 - s * s / (th * tw), 1e-9)
    return corr / (np.sqrt(var) * tnorm)


def locate(before, shot, kmin=0.70, kmax=1.00, step=0.005, coarse=4):
    padded = Image.new("L", (shot.width + 2 * PAD, shot.height + 2 * PAD), 0)
    padded.paste(shot.convert("L"), (PAD, PAD))
    small = gray(padded.resize((padded.width // coarse, padded.height // coarse), Image.BILINEAR))
    best = None
    for k in np.arange(kmin, kmax + 1e-9, step):
        f = 3.0 / (2.0 * k)
        w, h = round(before.width * f), round(before.height * f)
        if w + 2 * coarse >= padded.width or h + 2 * coarse >= padded.height:
            continue
        tc = gray(before.resize((max(2, w // coarse), max(2, h // coarse)), Image.BILINEAR))
        m = ncc_map(small, tc)
        y, x = np.unravel_index(np.argmax(m), m.shape)
        if best is None or m[y, x] > best[0]:
            best = (m[y, x], float(k), int(x) * coarse, int(y) * coarse, w, h)
    _, k, x0, y0, w, h = best
    full = gray(padded)
    t = gray(before.resize((w, h), Image.BILINEAR))
    r = 2 * coarse
    y1, x1 = max(0, y0 - r), max(0, x0 - r)
    region = full[y1: min(full.shape[0], y0 + h + r), x1: min(full.shape[1], x0 + w + r)]
    m = ncc_map(region, t)
    y, x = np.unravel_index(np.argmax(m), m.shape)
    return {"k": round(k, 4), "x": int(x1 + x) - PAD, "y": int(y1 + y) - PAD, "w": w, "h": h,
            "score": round(float(m[y, x]), 3)}


def main():
    rows = {r["n"]: r for r in json.load(open(os.path.join(W, "facts.json"), encoding="utf-8"))["rows"]}
    path = os.path.join(W, "rects.json")
    rects = json.load(open(path)) if os.path.exists(path) else {}
    args = sys.argv[1:]
    calibrate = args[:1] == ["--calibrate"]
    kfix = rects.get("_k")
    for n in [int(a) for a in args if a != "--calibrate"]:
        r = rows[n]
        shot_rel = f"shots/{r['locator']}/{r['screen']}.png"
        kmin, kmax = (0.70, 1.00) if calibrate or kfix is None else (kfix - 0.01, kfix + 0.01)
        res = locate(Image.open(r["before_png"]), Image.open(os.path.join(W, shot_rel)), kmin, kmax)
        res.update({"shot": shot_rel, "offset": rects.get(str(n), {}).get("offset", {})})
        rects[str(n)] = res
        print(n, res)
    with open(path, "w") as fh:
        json.dump(rects, fh, indent=1)


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run the tests**

Run: `cd ~/Desktop/oryne-story && python3 -m unittest tests/test_locate.py`
Expected: `Ran 3 tests … OK`

- [ ] **Step 5: Calibrate k on two rows**

Run: `cd ~/Desktop/oryne-story && python3 bin/locate.py --calibrate 4 15`
Expected: both with `score` ≥ 0.6 and `k` values within 0.01 of each other (a bezel measurement suggests about 0.845). Write their mean into `rects.json` as `"_k": <mean>` (edit the file).

- [ ] **Step 6: Locate every row**

Run: `cd ~/Desktop/oryne-story && python3 bin/locate.py $(seq 1 18)`
Expected: 18 lines. For any `score` below 0.6: view the before PNG and the row's locator screenshot. If the screenshot shows the wrong scroll position or screen, retake it (Task 5 Step 3) and rerun that row. If the screen is right but the element changed too much, try the previous build in `locator` (edit `ROWS` in `make_facts.py`, rerun it, take the shot, rerun `locate.py <n>`). Report any row still below 0.6.

---

### Task 7: Crop, export and the contact sheet

**Files:**
- Create: `W/bin/crops.py`, `W/tests/test_crops.py`, `W/bin/sheet.py`

**Interfaces:**
- Consumes: `facts.json`, `rects.json`, `shots/`.
- Produces: `crops.clip(rect, sw, sh) -> ((x0, y0, x1, y1), (bx0, by0, bx1, by1))`; files in `W/out/`: `before-<n>.webp` and `now-<n>.webp` for n = 1…18, `after-<n>.webp` for each featured row (its last answer), `lit-12.webp` (04b9cc2), `hero-before.webp`, `hero-after.webp`; `W/sheet.html`.

- [ ] **Step 1: Write the failing tests** — `W/tests/test_crops.py`

```python
import os, sys, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "bin"))
import crops


class Clip(unittest.TestCase):
    def test_a_rect_past_the_left_edge_is_clipped_on_both_images(self):
        screen, before = crops.clip({"x": -30, "y": 10, "w": 300, "h": 100, "k": 0.85}, 1206, 2622)
        self.assertEqual(screen, (0, 10, 270, 110))
        self.assertEqual(before, (17, 0, 170, 57))

    def test_an_offset_moves_only_the_screen_box(self):
        screen, before = crops.clip({"x": 100, "y": 100, "w": 300, "h": 120, "k": 0.85}, 1206, 2622, (5, -40))
        self.assertEqual(screen, (105, 60, 405, 180))
        self.assertEqual(before, (0, 0, 170, 68))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd ~/Desktop/oryne-story && python3 -m unittest tests/test_crops.py`
Expected: `ModuleNotFoundError: No module named 'crops'`

- [ ] **Step 3: Write `W/bin/crops.py`**

```python
#!/usr/bin/env python3
"""Make every web image: befores clipped to the phone's screen (the only edit to Locant's PNG),
afters cropped from the same screen rectangle, the hero pair, all WebP at most 200 KB."""
import json, os
from PIL import Image

W = os.path.expanduser("~/Desktop/oryne-story")
SW, SH = 1206, 2622          # iPhone 17 Pro screenshot pixels
NOW, HERO_BEFORE = "d854071", "f271e77"
HERO_SCREEN = "tide-top"     # until Malik picks another at the checkpoint
LIMIT = 200_000


def clip(rect, sw, sh, offset=(0, 0)):
    """Intersect the located rect with the screen. Returns the box in screenshot pixels (moved by offset,
    for an after whose element moved) and the matching box in the before's own pixels."""
    x0, y0 = max(0, rect["x"]), max(0, rect["y"])
    x1, y1 = min(sw, rect["x"] + rect["w"]), min(sh, rect["y"] + rect["h"])
    f = 2.0 * rect["k"] / 3.0
    before = (round((x0 - rect["x"]) * f), round((y0 - rect["y"]) * f),
              round((x1 - rect["x"]) * f), round((y1 - rect["y"]) * f))
    dx, dy = offset
    return (x0 + dx, y0 + dy, x1 + dx, y1 + dy), before


def export(img, name, width):
    img = img.convert("RGB")
    if img.width > width:
        img = img.resize((width, round(img.height * width / img.width)), Image.LANCZOS)
    path = os.path.join(W, "out", name)
    for q in (82, 74, 66, 58):
        img.save(path, "WEBP", quality=q, method=6)
        if os.path.getsize(path) <= LIMIT:
            return path
    raise SystemExit(f"{name} is over {LIMIT} bytes even at quality 58")


def main():
    rows = json.load(open(os.path.join(W, "facts.json"), encoding="utf-8"))["rows"]
    rects = json.load(open(os.path.join(W, "rects.json")))
    for r in rows:
        n, rect = r["n"], rects[str(r["n"])]
        screen, bbox = clip(rect, SW, SH)
        size = (screen[2] - screen[0], screen[3] - screen[1])
        export(Image.open(r["before_png"]).crop(bbox).resize(size, Image.LANCZOS), f"before-{n}.webp", 720)

        def after(h):
            box, _ = clip(rect, SW, SH, tuple(rect.get("offset", {}).get(h, (0, 0))))
            return Image.open(os.path.join(W, "shots", h, r["screen"] + ".png")).crop(box)

        export(after(NOW), f"now-{n}.webp", 720)
        if r["featured"]:
            export(after(r["answers"][-1]["hash"]), f"after-{n}.webp", 720)
            if len(r["answers"]) > 1:
                export(after(r["answers"][0]["hash"]), f"lit-{n}.webp", 720)
    for h, name in ((HERO_BEFORE, "hero-before.webp"), (NOW, "hero-after.webp")):
        export(Image.open(os.path.join(W, "shots", h, HERO_SCREEN + ".png")), name, 600)
    total = sum(os.path.getsize(os.path.join(W, "out", f)) for f in os.listdir(os.path.join(W, "out")))
    print(f"{len(os.listdir(os.path.join(W, 'out')))} images, {total / 1e6:.2f} MB")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run the tests**

Run: `cd ~/Desktop/oryne-story && python3 -m unittest tests/test_crops.py`
Expected: `Ran 2 tests … OK`

- [ ] **Step 5: Export**

Run: `cd ~/Desktop/oryne-story && python3 bin/crops.py`
Expected: `45 images, N MB` with N ≤ 5.00 (18 befores, 18 nows, 7 afters, 1 lit, 2 hero). If over 5 MB, lower the 720 width to 600 for `now-*` and rerun.

- [ ] **Step 6: Look at every pair**

View `out/before-<n>.webp` beside `out/now-<n>.webp` (and `after-<n>`) with the Read tool. When an after shows the element shifted, measure the shift in screenshot pixels and add it to `rects.json` as `"offset": {"<hash>": [dx, dy]}` for that row, then rerun `bin/crops.py`.

- [ ] **Step 7: Write `W/bin/sheet.py`** (the contact sheet for Malik)

```python
#!/usr/bin/env python3
"""sheet.html: every image the page will publish, row by row, for Malik's privacy and content review."""
import html, json, os

W = os.path.expanduser("~/Desktop/oryne-story")
rows = json.load(open(os.path.join(W, "facts.json"), encoding="utf-8"))["rows"]
cells = ['<h2>Hero</h2><div class="r"><img src="out/hero-before.webp"><img src="out/hero-after.webp"></div>']
for r in rows:
    imgs = [f"before-{r['n']}", f"now-{r['n']}"]
    if r["featured"]:
        imgs += [f"after-{r['n']}"] + ([f"lit-{r['n']}"] if len(r["answers"]) > 1 else [])
    note = html.escape(r["note"] or r.get("chat_note") or "(no note)")
    en = f"<br><i>{html.escape(r['translation'])}</i>" if r.get("translation") else ""
    cells.append(f"<h2>{r['n']} · {r['pointed']} · {html.escape(r['label'])}{' ★' if r['featured'] else ''}</h2>"
                 f"<p>{note}{en}</p><div class=r>" + "".join(f'<figure><img src="out/{i}.webp"><figcaption>{i}</figcaption></figure>' for i in imgs) + "</div>")
page = ("<!doctype html><meta charset=utf-8><title>Oryne story: contact sheet</title><style>"
        "body{font:15px -apple-system,sans-serif;margin:24px;background:#111;color:#eee}"
        ".r{display:flex;gap:12px;flex-wrap:wrap}img{max-width:360px;border-radius:8px}"
        "figure{margin:0}figcaption{font-size:12px;color:#999}h2{font-size:16px;margin:28px 0 6px}</style>"
        "<h1>Every image the page will publish</h1><p>Flag any image that shows something private.</p>" + "".join(cells))
open(os.path.join(W, "sheet.html"), "w", encoding="utf-8").write(page)
print(os.path.join(W, "sheet.html"))
```

Run: `cd ~/Desktop/oryne-story && python3 bin/sheet.py`
Expected: the path of `sheet.html`. Open it in the browser pane (`file://` URL) and check that every image loads.

---

### Task 8: The page

**Files:**
- Create: `site/oryne/index.html`, `site/oryne/assets/*.webp`, `W/bin/render_page.py`, `W/tests/test_render_page.py`
- Modify: `site/index.html` (one line after line 686, the `.method` paragraph that links the report)

**Interfaces:**
- Consumes: `facts.json`, `W/out/*.webp`.
- Produces: `render_page.row_html(row, sizes) -> str`, `render_page.closeup_html(key, rows, sizes) -> str`, `render_page.fill(page, block, html) -> str`; the page with blocks between `<!-- timeline -->`/`<!-- /timeline -->` and `<!-- closeups -->`/`<!-- /closeups -->`.

- [ ] **Step 1: Copy the images into the site**

```bash
cd /Users/malik/Documents/Locant/.claude/worktrees/locant-oryne-redesign-story-f88439 && [ -e site/oryne ] && echo EXISTS || (mkdir site/oryne && mkdir site/oryne/assets && cp ~/Desktop/oryne-story/out/*.webp site/oryne/assets/ && ls site/oryne/assets | wc -l)
```
Expected: `45`.

- [ ] **Step 2: Write `site/oryne/index.html`** (static parts; the two marked blocks are filled in Step 6; the copy is a draft for Malik's checkpoint)

```html
<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>One night with Oryne · Locant</title>
<meta name="description" content="A real tweak pass on an iPhone app: eighteen Locant captures pasted into Claude Code, and the commits that answered them.">
<link rel="icon" type="image/png" sizes="32x32" href="/assets/favicon-32.png">
<link rel="icon" type="image/png" sizes="64x64" href="/assets/favicon-64.png">
<link rel="apple-touch-icon" href="/assets/apple-touch-icon.png">
<meta property="og:type" content="article">
<meta property="og:url" content="https://locant.malikzhang.com/oryne/">
<meta property="og:site_name" content="Locant">
<meta property="og:title" content="One night with Oryne">
<meta property="og:description" content="A real tweak pass on an iPhone app, capture by capture.">
<meta property="og:image" content="https://locant.malikzhang.com/oryne/assets/hero-after.webp">
<style>
  /* COPY site/index.html lines 22–92 here verbatim (the light, dark and data-theme tokens),
     then change the three --icon values to url("/assets/icon-light.png") / url("/assets/icon-dark.png").
     COPY lines 94–179 (base, type, nav, hero, buttons, sections) and 445–460 (.end and footer) verbatim. */

  /* story */
  .kicker { font-size: 14px; color: var(--muted); letter-spacing: 0; }
  .phones { display: grid; grid-template-columns: 1fr 1fr; gap: 28px; max-width: 560px; margin: 36px auto 0; }
  .phones figure { margin: 0; display: grid; gap: 10px; justify-items: center; }
  .phone { width: 100%; border-radius: 15% / 7%; padding: 2.4%; background: linear-gradient(150deg, #6b6c70, #2a2a2d 22%, #1c1c1e 60%, #3a3a3d);
    box-shadow: inset 0 0 0 1px rgba(255,255,255,.22), inset 0 0 0 3px #0c0c0d, 0 0 0 1px rgba(0,0,0,.5), var(--shadow); }
  .phone img { display: block; width: 100%; height: auto; border-radius: 13% / 6%; }
  .phones figcaption, .pair figcaption { font-size: 13px; color: var(--muted); }
  .prose { max-width: 640px; display: grid; gap: 14px; }
  .timeline { list-style: none; margin: 0; padding: 0; }
  .timeline li { display: grid; grid-template-columns: 64px minmax(0, 1fr); gap: 16px; padding-block: 22px; border-top: 1px solid var(--hair); }
  .timeline time { font-variant-numeric: tabular-nums; color: var(--muted); font-size: 15px; padding-top: 1px; }
  .note { font-size: 17px; max-width: 62ch; }
  .note .en { display: block; margin-top: 4px; font-size: 15px; color: var(--muted); }
  .pair { display: grid; grid-template-columns: repeat(var(--n, 2), minmax(0, 1fr)); gap: 12px; margin: 14px 0 0; max-width: 560px; }
  .pair figure { margin: 0; display: grid; gap: 6px; align-content: start; }
  .pair img { display: block; width: 100%; height: auto; border-radius: 10px; background: #000; }
  .timeline .pair { max-width: 420px; }
  .answer { margin-top: 10px; font-size: 14px; color: var(--muted); }
  .answer code { color: var(--ink); }
  .close-up { padding-top: 56px; display: grid; gap: 12px; max-width: 720px; }
  .close-up .meta { font-size: 14px; color: var(--muted); }
  .close-up .story { max-width: 62ch; }
  .reply { border-left: 2px solid var(--hair); padding-left: 14px; }
  .payload { margin: 0; padding: 18px 20px; background: var(--code-bg); border: 1px solid var(--hair); border-radius: 14px;
    font-size: 13.5px; line-height: 1.55; white-space: pre-wrap; overflow-wrap: anywhere; }
  .method { font-size: 15px; color: var(--muted); max-width: 62ch; }
  .method a { color: var(--link); }
  @media (max-width: 720px) {
    .hero { padding-block: 56px 36px; }                  /* as the home page, line 464 */
    footer .links { margin-left: 0; flex-basis: 100%; }  /* as the home page, line 467 */
    .phones { gap: 16px; }
    .timeline li { grid-template-columns: minmax(0, 1fr); gap: 6px; }
    .pair { grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); }
    .pair[style*="--n: 3"] { grid-template-columns: minmax(0, 1fr); }
  }
</style>

<nav class="nav" aria-label="Site">
  <div class="in">
    <a class="brand" href="/"><span class="mark" aria-hidden="true"></span>Locant</a>
    <div class="links">
      <a href="/#how">Try it</a>
      <a href="/#why">Why Locant</a>
      <a href="/#privacy">Privacy</a>
    </div>
    <a class="dl" href="https://github.com/Malik1942/locant/releases/latest/download/Locant.dmg">Download</a>
  </div>
</nav>

<main id="top">
  <header class="hero col">
    <p class="kicker">A Locant story</p>
    <h1>One night with Oryne</h1>
    <p class="lede">After a usability test, I fixed the details of Oryne, my iPhone app, by pointing at them. Eighteen captures between 22:18 and 23:46, each pasted into Claude Code, and the commits that answered them.</p>
    <div class="phones">
      <figure><div class="phone"><img src="/oryne/assets/hero-before.webp" width="600" height="1305" alt="Oryne's Tide screen at 21:43, before the pass."></div><figcaption>21:43, before the pass</figcaption></figure>
      <figure><div class="phone"><img src="/oryne/assets/hero-after.webp" width="600" height="1305" alt="Oryne's Tide screen at 23:57, after the pass."></div><figcaption>23:57, after it</figcaption></figure>
    </div>
  </header>

  <section class="col" id="setup">
    <div class="sect-head"><h2>The setup</h2></div>
    <div class="prose">
      <p>Oryne is an iPhone app for catching ideas before they drift away. Its big redesign came from a written spec on October 17.</p>
      <p>On October 18, three people tried it, and what tripped them up became a list. That night was for the details: I pointed at each one in the simulator with Locant, typed what was wrong, and pasted the capture into Claude Code.</p>
    </div>
  </section>

  <section class="col" id="night">
    <div class="sect-head">
      <h2>The night</h2>
      <p class="lede">Every capture, in order. Left, what I pointed at. Right, the same spot at 23:57.</p>
    </div>
<!-- timeline -->
<!-- /timeline -->
  </section>

  <section class="col" id="close-ups">
    <div class="sect-head"><h2>Six close-ups</h2></div>
<!-- closeups -->
<!-- /closeups -->
  </section>

  <section class="col" id="payload">
    <div class="sect-head">
      <h2>What the agent received</h2>
      <p class="lede">For the send button, Locant put this on the clipboard: the element, where it sits, the folder the app was built from, and my note. I didn't have to say which button I meant.</p>
    </div>
    <pre class="payload">PAYLOAD</pre>
  </section>

  <section class="col">
    <p class="method">This is one real working session, not a test. Times come from Locant's capture files and the git history. For measured results, <a href="https://github.com/Malik1942/locant/blob/main/docs/video/11-measurement-worktrees.md">read the report</a>.</p>
  </section>

  <section class="col end">
    <h2>Try Locant on your Mac.</h2>
    <a class="btn" href="https://github.com/Malik1942/locant/releases/latest/download/Locant.dmg">Download for Mac</a>
    <p class="fine"><span>Free</span><span>macOS 15 or later</span></p>
  </section>

  <footer class="col">
    <div class="row">
      <span class="ver"><a href="/">Locant</a></span>
      <nav class="links" aria-label="Footer">
        <a href="https://github.com/Malik1942/locant">GitHub</a>
        <a href="https://oryne.malikzhang.com">Oryne</a>
        <a href="https://www.malikzhang.com">Built by Malik</a>
      </nav>
    </div>
  </footer>
</main>
```
Then do what the comment in `<style>` says: copy those line ranges from `site/index.html` in place of the comment (verbatim, with the `--icon` change). Replace `PAYLOAD` with the payload Malik pasted at 23:38: run `cd ~/Desktop/oryne-story && python3 bin/chat_after.py 20261018-233759-v0xc 1 --full`, take the text between `<pasted_content …>` and `</pasted_content>`, HTML-escape it (`&`, `<`, `>`), keep it whole except the `### Sidecar` JSON block if one is there (replace that block with `…`), and paste it. Set the hero images' `height` to the real exported height (`python3 -c "from PIL import Image; print(Image.open('$HOME/Desktop/oryne-story/out/hero-before.webp').size)"`).

- [ ] **Step 3: Write the failing tests** — `W/tests/test_render_page.py`

```python
import os, sys, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "bin"))
import render_page as rp

ROW = {"n": 17, "pointed": "23:37", "note": "太亮 <b>&", "translation": "Too bright",
       "label": "the send button", "featured": True, "closeup": "send", "story": "It kept the glass.",
       "story_time": "23:39", "answers": [{"hash": "b15f960", "time": "23:39", "subject": "Send arrows stay glass"}]}
SIZES = {"before-17.webp": (720, 233), "now-17.webp": (720, 233), "after-17.webp": (720, 233)}


class Render(unittest.TestCase):
    def test_row_escapes_and_marks_chinese(self):
        h = rp.row_html(ROW, SIZES)
        self.assertIn('lang="zh-Hans"', h)
        self.assertIn("太亮 &lt;b&gt;&amp;", h)
        self.assertIn('<span class="en" lang="en">Too bright</span>', h)
        self.assertIn('src="/oryne/assets/before-17.webp" width="720" height="233"', h)
        self.assertIn("<time>23:37</time>", h)
        self.assertIn("<code>b15f960</code>", h)

    def test_closeup_shows_the_answer_pair(self):
        h = rp.closeup_html("send", [ROW], SIZES)
        self.assertIn('id="send"', h)
        self.assertIn("after-17.webp", h)
        self.assertIn("It kept the glass.", h)

    def test_fill_replaces_only_the_block(self):
        page = "a<!-- timeline -->old<!-- /timeline -->b"
        self.assertEqual(rp.fill(page, "timeline", "NEW"), "a<!-- timeline -->\nNEW\n<!-- /timeline -->b")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 4: Run them to see them fail**

Run: `cd ~/Desktop/oryne-story && python3 -m unittest tests/test_render_page.py`
Expected: `ModuleNotFoundError: No module named 'render_page'`

- [ ] **Step 5: Write `W/bin/render_page.py`**

```python
#!/usr/bin/env python3
"""Fill site/oryne/index.html's timeline and close-ups from facts.json. Usage: render_page.py <site/oryne/index.html>"""
import html, json, os, re, sys
from PIL import Image

W = os.path.expanduser("~/Desktop/oryne-story")
TITLES = {"titles": "Card titles, lighter", "more": "A transcript you can open", "light": "Light, then no light",
          "currents": "A quieter link", "settings": "Does the Library need settings?", "send": "The send button"}
ORDER = ["send", "light", "settings", "titles", "more", "currents"]
CJK = re.compile(r"[㐀-鿿]")
e = html.escape


def img(name, alt, sizes):
    w, h = sizes[name]
    return f'<img src="/oryne/assets/{name}" width="{w}" height="{h}" alt="{e(alt)}">'


def note_html(r):
    text = r["note"] or r.get("chat_note") or ""
    if not text:
        return '<p class="note muted">Pointed, no note.</p>'
    lang = ' lang="zh-Hans"' if CJK.search(text) else ""
    prefix = "" if r["note"] else f"No note; in the chat at {r['chat_note_time']}: "
    en = f'<span class="en" lang="en">{e(r["translation"])}</span>' if r.get("translation") else ""
    return f'<p class="note"{lang}>{e(prefix)}{e(text)}{en}</p>'


def answer_html(r):
    return "".join(f'<p class="answer">Answered at {a["time"]}: <code>{a["hash"]}</code> {e(a["subject"])}</p>'
                   for a in r["answers"])


def row_html(r, sizes):
    n = r["n"]
    return (f'<li id="t-{n}"><time>{r["pointed"]}</time><div>{note_html(r)}'
            f'<div class="pair"><figure>{img(f"before-{n}.webp", "Before: " + r["label"], sizes)}</figure>'
            f'<figure>{img(f"now-{n}.webp", "At 23:57: " + r["label"], sizes)}</figure></div>'
            f'{answer_html(r)}</div></li>')


def closeup_html(key, rows, sizes):
    first = rows[0]
    parts = [f'<article class="close-up" id="{key}"><h3>{e(TITLES[key])}</h3>']
    for r in rows:
        n, last = r["n"], r["answers"][-1]
        figs = [f'<figure>{img(f"before-{n}.webp", "Before: " + r["label"], sizes)}<figcaption>Pointed at {r["pointed"]}</figcaption></figure>']
        if len(r["answers"]) > 1:
            a0 = r["answers"][0]
            figs.append(f'<figure>{img(f"lit-{n}.webp", "First try: " + r["label"], sizes)}<figcaption>{a0["time"]}, <code>{a0["hash"]}</code></figcaption></figure>')
        figs.append(f'<figure>{img(f"after-{n}.webp", "After: " + r["label"], sizes)}<figcaption>{last["time"]}, <code>{last["hash"]}</code></figcaption></figure>')
        parts.append(note_html(r))
        parts.append(f'<div class="pair" style="--n: {len(figs)}">{"".join(figs)}</div>')
        if r.get("reply"):
            parts.append(f'<p class="note reply" lang="zh-Hans">{r["reply_time"]}, after the first try: {e(r["reply"])}'
                         f'<span class="en" lang="en">{e(r["reply_en"])}</span></p>')
        parts.append(answer_html(r))
    if first.get("story"):
        parts.append(f'<p class="story">{e(first["story"])}</p>')
    if first.get("voice_note"):
        parts.append(f'<p class="story">{e(first["voice_note"])}</p>')
    parts.append("</article>")
    return "".join(parts)


def fill(page, block, content):
    start, end = f"<!-- {block} -->", f"<!-- /{block} -->"
    a, b = page.index(start) + len(start), page.index(end)
    return page[:a] + "\n" + content + "\n" + page[b:]


def main():
    path = sys.argv[1]
    rows = json.load(open(os.path.join(W, "facts.json"), encoding="utf-8"))["rows"]
    out = os.path.join(W, "out")
    sizes = {f: Image.open(os.path.join(out, f)).size for f in os.listdir(out) if f.endswith(".webp")}
    page = open(path, encoding="utf-8").read()
    page = fill(page, "timeline", '<ol class="timeline">' + "".join(row_html(r, sizes) for r in rows) + "</ol>")
    groups = {k: [r for r in rows if r.get("closeup") == k] for k in ORDER}
    page = fill(page, "closeups", "".join(closeup_html(k, groups[k], sizes) for k in ORDER if groups[k]))
    open(path, "w", encoding="utf-8").write(page)
    print("filled", path)


if __name__ == "__main__":
    main()
```

- [ ] **Step 6: Run the tests, then fill the page**

Run: `cd ~/Desktop/oryne-story && python3 -m unittest tests/test_render_page.py && python3 bin/render_page.py /Users/malik/Documents/Locant/.claude/worktrees/locant-oryne-redesign-story-f88439/site/oryne/index.html`
Expected: `Ran 3 tests … OK` then `filled …/site/oryne/index.html`. Running it twice gives the same file (the blocks are replaced, not appended).

- [ ] **Step 7: Add the home page's link**

In `site/index.html`, directly after line 686 (`<p class="method">Tested on Claude Code, graded blind. <a href="…11-measurement-worktrees.md">Read the report</a>.</p>`), add:

```html
    <p class="method">See it on a real redesign: <a href="/oryne/">One night with Oryne</a>, capture by capture.</p>
```

- [ ] **Step 8: Commit locally (no push)**

```bash
cd /Users/malik/Documents/Locant/.claude/worktrees/locant-oryne-redesign-story-f88439
git add site/oryne site/index.html
git commit -m "site: the Oryne story page, one night of captures"
```

---

### Task 9: Check the page

**Files:**
- Create: `W/bin/check_page.py`, `W/bin/render.mjs`
- Modify: `site/oryne/index.html` only if a check fails

**Interfaces:**
- Consumes: the site folder, `facts.json`.

- [ ] **Step 1: Write `W/bin/check_page.py`**

```python
#!/usr/bin/env python3
"""Static checks on site/oryne/index.html. Usage: check_page.py <site folder>. Exit 1 on any problem."""
import json, os, re, sys
from html.parser import HTMLParser

SITE = sys.argv[1]
W = os.path.expanduser("~/Desktop/oryne-story")
page = open(os.path.join(SITE, "oryne", "index.html"), encoding="utf-8").read()
rows = json.load(open(os.path.join(W, "facts.json"), encoding="utf-8"))["rows"]


class Collect(HTMLParser):
    def __init__(self):
        super().__init__()
        self.imgs, self.links, self.text = [], [], []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "img":
            self.imgs.append(a)
        if tag == "a":
            self.links.append(a.get("href", ""))

    def handle_data(self, data):
        self.text.append(data)


c = Collect()
c.feed(page)
problems, seen = [], set()
for a in c.imgs:
    src = a.get("src", "")
    if not src.startswith("/"):
        problems.append(f"not root-absolute: {src}")
        continue
    f = os.path.join(SITE, src.lstrip("/"))
    if not os.path.exists(f):
        problems.append(f"missing: {src}")
        continue
    for k in ("alt", "width", "height"):
        if not a.get(k):
            problems.append(f"{src} has no {k}")
    if os.path.getsize(f) > 200_000:
        problems.append(f"{src} is {os.path.getsize(f)} bytes")
    seen.add(f)
total = sum(os.path.getsize(f) for f in seen)
if total > 5_000_000:
    problems.append(f"images total {total} bytes")
allowed = {"21:43", "23:57", "22:18", "23:46"}
for r in rows:
    allowed |= {r["pointed"], r["pasted"]} | {a["time"] for a in r["answers"]}
    allowed |= {r[k] for k in ("reply_time", "story_time", "chat_note_time") if r.get(k)}
for t in sorted(set(re.findall(r"\b([012]\d:[0-5]\d)\b", " ".join(c.text)))):
    if t not in allowed:
        problems.append(f"time {t} is not in facts.json")
for href in c.links:
    if href.startswith("/") and not href.startswith("/#"):
        target = os.path.join(SITE, href.lstrip("/"))
        if os.path.isdir(target):
            target = os.path.join(target, "index.html")
        if not os.path.exists(target):
            problems.append(f"broken link {href}")
for p in problems:
    print(p)
print(f"{len(c.imgs)} images, {total / 1e6:.2f} MB, {len(problems)} problems")
sys.exit(1 if problems else 0)
```

- [ ] **Step 2: Run it**

Run: `cd ~/Desktop/oryne-story && python3 bin/check_page.py /Users/malik/Documents/Locant/.claude/worktrees/locant-oryne-redesign-story-f88439/site`
Expected: `… images, … MB, 0 problems`. Fix the page for anything listed, rerun.

- [ ] **Step 3: Write `W/bin/render.mjs`**

```js
// Render a page in headless Chrome at 1280 and 375 px, light and dark; fail on horizontal scroll or a broken image.
// Usage: node render.mjs <url> <outdir>
import { spawn } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const [url, out] = process.argv.slice(2);
const chrome = spawn("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  ["--headless=new", "--remote-debugging-port=9333", "--no-first-run", "--hide-scrollbars",
   `--user-data-dir=${mkdtempSync(join(tmpdir(), "oryne-story-"))}`, "about:blank"], { stdio: "ignore" });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let wsUrl;
for (let i = 0; i < 50 && !wsUrl; i++) {
  try {
    const targets = await (await fetch("http://127.0.0.1:9333/json/list")).json();
    wsUrl = targets.find((t) => t.type === "page")?.webSocketDebuggerUrl;
  } catch {}
  if (!wsUrl) await sleep(200);
}
const ws = new WebSocket(wsUrl);
await new Promise((r) => (ws.onopen = r));
let next = 0;
const pending = new Map();
ws.onmessage = (e) => { const m = JSON.parse(e.data); if (pending.has(m.id)) { pending.get(m.id)(m.result); pending.delete(m.id); } };
const send = (method, params = {}) => new Promise((r) => { const id = ++next; pending.set(id, r); ws.send(JSON.stringify({ id, method, params })); });

let failed = false;
for (const [w, h] of [[1280, 900], [375, 812]]) {
  for (const scheme of ["light", "dark"]) {
    await send("Emulation.setDeviceMetricsOverride", { width: w, height: h, deviceScaleFactor: 2, mobile: w < 768 });
    await send("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: scheme }] });
    await send("Page.navigate", { url });
    await sleep(2000);
    const r = await send("Runtime.evaluate", { returnByValue: true, expression:
      "({sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth, height: document.documentElement.scrollHeight, broken: [...document.images].filter(i => !i.complete || !i.naturalWidth).map(i => i.getAttribute('src'))})" });
    const v = r.result.value;
    const ok = v.sw <= v.cw && v.broken.length === 0;
    failed ||= !ok;
    console.log(`${w} ${scheme}: width ${v.sw}/${v.cw}${v.broken.length ? ", broken " + v.broken.join(" ") : ""} ${ok ? "OK" : "FAIL"}`);
    const shot = await send("Page.captureScreenshot", { format: "png", captureBeyondViewport: true,
      clip: { x: 0, y: 0, width: w, height: v.height, scale: 1 } });
    writeFileSync(join(out, `page-${w}-${scheme}.png`), Buffer.from(shot.data, "base64"));
  }
}
ws.close();
chrome.kill();
process.exit(failed ? 1 : 0);
```

- [ ] **Step 4: Serve the site and render**

Start the server in the background (Bash `run_in_background: true`): `python3 -m http.server 8742 --directory /Users/malik/Documents/Locant/.claude/worktrees/locant-oryne-redesign-story-f88439/site`
Then run: `cd ~/Desktop/oryne-story && node bin/render.mjs http://localhost:8742/oryne/ render && node bin/render.mjs http://localhost:8742/ render-home 2>/dev/null; ls render`
(Create `render-home` first with `mkdir`; the second run only checks the home page still renders with its new line.)
Expected: four `OK` lines for the story page; `render/` holds `page-1280-light.png`, `page-1280-dark.png`, `page-375-light.png`, `page-375-dark.png`. View all four with the Read tool: one column, both phones side by side even at 375, every pair readable, dark mode with no light boxes. Fix and rerun until all four pass and look right.

- [ ] **Step 5: Commit fixes, if any (no push)**

```bash
cd /Users/malik/Documents/Locant/.claude/worktrees/locant-oryne-redesign-story-f88439
git add site/oryne
git commit -m "site: the Oryne story page passes its checks at 375 and 1280, light and dark"
```
(Skip if Steps 2–4 needed no change.)

---

### Task 10: CHECKPOINT: Malik reviews before anything is published

No push, no PR, no deploy in this task. Stop after Step 2 and wait for Malik's answer in chat.

- [ ] **Step 1: Send Malik the review set**

Send with SendUserFile: `~/Desktop/oryne-story/sheet.html` (every image, row by row) and `~/Desktop/oryne-story/render/page-1280-dark.png`, `page-375-light.png`. Give the local URL `http://localhost:8742/oryne/` (the server from Task 9 must still be running).

- [ ] **Step 2: Ask, in one message, for his answers on:**

1. Privacy: any image to drop or replace (his real thoughts are in the crops).
2. The six close-ups: keep, or swap one (alternates: row 10 Library lag, row 9 Tide position, row 6 Currents).
3. The hero screen (now `tide-top`).
4. The title ("One night with Oryne") and the draft copy.
5. The translations of rows 12–17.
6. The voice-note line in "A transcript you can open".
7. The home page line.

Then end the turn and wait. A correct page does not excuse skipping this.

---

### Task 11: Apply Malik's answers, publish, clean up

- [ ] **Step 1: Apply his answers**

Copy changes go into `site/oryne/index.html` (static parts) or `W/notes.json` (rows), then rerun `python3 bin/make_facts.py && python3 bin/render_page.py <page>`. A dropped image: remove the row's `<figure>` by setting `"hide_now": true` for that row in `notes.json` and adding `if r.get("hide_now")` handling in `row_html` (skip the `now` figure), with a test in `tests/test_render_page.py` first. A new hero screen: set `HERO_SCREEN` in `shotlist.py` and `crops.py`, take the shots (Task 5 Step 3 for `f271e77` and `d854071`), rerun `crops.py`, recopy `hero-*.webp`. Rerun Task 9 Steps 2 and 4.

- [ ] **Step 2: Commit (no push yet)**

```bash
cd /Users/malik/Documents/Locant/.claude/worktrees/locant-oryne-redesign-story-f88439
git add site/oryne site/index.html
git commit -m "site: the Oryne story page, Malik's review"
```

- [ ] **Step 3: Push and open the PR only after Malik says to**

```bash
git push -u origin am/locant-oryne-redesign-story-f88439
gh pr create --base main --title "site: One night with Oryne" --body "A story page at /oryne/: the Oct 18 tweak pass on Oryne, capture by capture. Spec: docs/superpowers/specs/2026-10-19-oryne-story-design.md. Plan: docs/superpowers/plans/2026-10-19-oryne-story.md. Images reviewed by Malik for privacy before this push."
```
Then check the Vercel preview: `/oryne/` loads, images load, `/` shows the new line. Malik merges.

- [ ] **Step 4: Clean up**

Run: `~/Desktop/oryne-story/bin/sim.sh delete` (deletes the story simulator and the data copy) and stop the local server. Keep `~/Desktop/oryne-story/` (its shots and builds feed the film later) unless Malik says otherwise.
