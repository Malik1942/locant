# A Locant skill any Grok Bot can pick up (specs/grok-bot-skill.md R64–R67) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Any Grok Bot user with Locant can, after one sentence or one install, say "what did I just point at?" and get the element, identifier, app, note, and image, read from their Mac, with no change to the Locant app.

**Architecture:** One skill (`plugins/locant/skills/locant/SKILL.md`) tells the bot to run Locant's own MCP server once on the user's Mac (`Locant --mcp`, `latest_capture`, text pulled out with `plutil`), open the PNG, act, and resolve. The repository becomes a Cursor-format plugin marketplace (`.cursor-plugin/marketplace.json` → `plugins/locant`) so the same skill installs for every bot; the per-bot path is one sentence pointing at the raw `SKILL.md`. `scripts/check-skill.sh` runs the skill's command, verbatim, against a throwaway capture folder. The site and README say what was verified.

**Tech Stack:** Markdown (SKILL.md), JSON manifests (Cursor plugin format), zsh and POSIX sh, `plutil` (ships with macOS), the installed Locant 0.8.1 at `/Applications/Locant.app`, Grok Bot 0.57.1 driven through the computer-use `app_*` tools, the Cursor CLI `agent` in `~/.local/bin`.

## Global Constraints

- Nothing under `Locant/` or `LocantTests/` changes (Malik: Locant is not modified to suit Grok Bot). No Xcode build is needed; the build of main stays as it is.
- Worktree `/Users/malik/Documents/Locant/.claude/worktrees/locant-grok-bot-integration-ecdc4f`, branch `am/locant-grok-bot-integration-ecdc4f`, PR https://github.com/Malik1942/locant/pull/42. Never merge; never enable auto-merge.
- Skill `name: locant`, and it must match its folder `plugins/locant/skills/locant/`. The plugin carries no MCP server and no `mcp.json` (R65). Every manifest path is relative, with no `..`.
- Locant 0.7.1 or later is required (`--mcp`). The skill does not check the version.
- `docs/CLAUDE.md`: commits `area: what changed`, one intent each, no attribution lines. "Do not write the README until the spec's last slot": the top-level `README.md` changes only in Task 4.
- Malik's captures never go to Grok and `resolve_capture` never runs on them: tests use a throwaway folder (`--folder`) or a neutral Calculator capture that goes to the Trash afterwards.
- Changes to Malik's Grok Bot account (saving a private skill, installing a plugin) and taking the Mac for synthetic input need his yes first (Task 3 step 1).
- Copy, verbatim from the spec (R66/R67):
  - Setup sentence: `Save the skill at https://raw.githubusercontent.com/Malik1942/locant/main/plugins/locant/skills/locant/SKILL.md as a private skill named locant, word for word.`
  - Site lede: "so any agent takes it on paste" → "so most agents take it on paste".
  - Site rows after Codex CLI: **Grok Bot** · "Reads the capture on your Mac with the Locant skill; a paste carries only the image" · Verified (Task 3's pass date), "Locant skill" linking to https://github.com/Malik1942/locant#in-grok-bot; **Antigravity** · "Takes the paste and opens the image at the path" · Verified Sep 18, 2026; **Gemini CLI** · "Paste, or the snippet from Settings › Agents" · Untested.
- Malik submits to the Marketplace; nobody else does. Task 4 drafts the text as a PR comment.

---

### Task 1: The skill and its checker (R64)

**Files:**
- Create: `scripts/check-skill.sh`
- Create: `plugins/locant/skills/locant/SKILL.md`

**Interfaces:**
- Produces: `scripts/check-skill.sh` (run from anywhere; exits 0 and prints `OK …` lines, or prints `FAIL: …` to stderr and exits 1). Task 2 appends manifest checks to it. The skill's `sh` block and its `resolve_capture` line, which the script extracts by pattern: the first ` ```sh ` fence, and the first line containing `"resolve_capture"`.

- [ ] **Step 1: Write the checker**

Create `scripts/check-skill.sh` and make it executable (`chmod +x scripts/check-skill.sh`):

```zsh
#!/bin/zsh
# specs/grok-bot-skill.md §4 test 1: checks the Locant skill (R64) and plugin (R65). The skill's own
# command runs against a throwaway capture folder, never ~/Pictures/Locant. Needs Locant 0.7.1 or later.
set -euo pipefail
cd "${0:A:h}/.."
fail() { print -u2 "FAIL: $*"; exit 1 }

plugin=plugins/locant
skill=$plugin/skills/locant/SKILL.md

# R64: the frontmatter names the skill after its folder and says when to use it.
[[ -f $skill ]] || fail "$skill is missing"
[[ $(sed -n 1p $skill) == --- ]] || fail "SKILL.md must open with --- frontmatter"
name=$(awk 'NR > 1 && /^---$/ { exit } NR > 1 && sub(/^name: /, "") { print }' $skill)
[[ $name == locant ]] || fail "SKILL.md name is '$name'; it must be locant, its folder's name"
awk 'NR > 1 && /^---$/ { exit } /^description: ./ { found = 1 } END { exit !found }' $skill \
  || fail "SKILL.md has no description"

# R64: the skill's command, exactly as written, against a folder holding one capture.
command=$(awk '/^ *```sh$/ { inside = 1; next } inside && /^ *```$/ { exit } inside' $skill)
[[ -n $command ]] || fail "SKILL.md has no sh block"
folder=$(mktemp -d)
trap 'rm -rf $folder' EXIT
id=20260922-120000-test
png=$folder/locant-calculator-$id.png
cp site/assets/icon-dark.png $png
cat > $folder/locant-calculator-$id.json <<EOF
{
  "createdAt" : "2026-09-22T12:00:00-07:00",
  "element" : {
    "frame" : { "h" : 48, "w" : 48, "x" : 1154, "y" : 516 },
    "identifier" : "Eight",
    "identifierSource" : "declared",
    "label" : "8",
    "path" : [
      { "identifier" : null, "role" : "application" },
      { "identifier" : "main", "role" : "window" },
      { "identifier" : "CalculatorKeypadView", "role" : "group" },
      { "identifier" : "Eight", "role" : "button" }
    ],
    "rawRole" : "AXButton",
    "role" : "button",
    "value" : null
  },
  "id" : "$id",
  "image" : {
    "crop" : { "h" : 128, "w" : 128, "x" : 1114, "y" : 476 },
    "heightPt" : 128,
    "path" : "$png",
    "scale" : 2,
    "widthPt" : 128
  },
  "iterations" : [],
  "mode" : "reference",
  "note" : "make this key bigger",
  "ocr" : null,
  "resolved" : false,
  "schemaVersion" : 1,
  "source" : {
    "app" : { "bundleId" : "com.apple.calculator", "name" : "Calculator" },
    "simulator" : null,
    "url" : null,
    "window" : { "title" : "Calculator" }
  }
}
EOF
run() { print -r -- "$1" | sed "s|--mcp|--mcp --folder $folder|" | /bin/sh }
out=$(run $command) || fail "the command failed: ${out[1,300]}"
[[ $out == "## Locant capture"* ]] || fail "the command printed: ${out[1,300]}"
[[ $out == *"Image: $png"* ]] || fail "no image path in the payload"
[[ $out == *'button "8" · id=Eight'* ]] || fail "no element in the payload"
[[ $out == *"make this key bigger"* ]] || fail "no note in the payload"
[[ $out == *"\"id\" : \"$id\""* ]] || fail "no id in the sidecar block"
print "OK  the command prints the latest capture"

# R64 step 5: the skill's resolve request, in place of the command's second request.
latest='{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"latest_capture","arguments":{}}}'
[[ $command == *"$latest"* ]] || fail "the command's second request is not latest_capture as the spec writes it"
resolve=$(grep -m 1 '"resolve_capture"' $skill | sed -e 's/^ *//' -e "s/<id>/$id/")
[[ $resolve == '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"resolve_capture"'* ]] \
  || fail "SKILL.md has no resolve_capture request"
out=$(run ${command/"$latest"/$resolve}) || fail "the resolve command failed: ${out[1,300]}"
[[ $out == "Resolved $id. Locant keeps it." ]] || fail "resolve printed: ${out[1,300]}"
[[ $(plutil -extract resolved raw -o - $folder/locant-calculator-$id.json) == true ]] \
  || fail "the sidecar is not resolved"
print "OK  the resolve request marks it resolved"
```

- [ ] **Step 2: Run it and watch it fail**

Run: `/Users/malik/Documents/Locant/.claude/worktrees/locant-grok-bot-integration-ecdc4f/scripts/check-skill.sh`
Expected: `FAIL: plugins/locant/skills/locant/SKILL.md is missing`, exit 1.

- [ ] **Step 3: Write the skill**

Create `plugins/locant/skills/locant/SKILL.md`, exactly:

````markdown
---
name: locant
description: Read what the user just pointed at with Locant, a macOS app that captures one on-screen element with its role, accessibility identifier, app, a cropped PNG, and the user's note. Use when the user refers to something they pointed at ("what I just pointed at", "this button", "fix this"), mentions Locant or a capture, or pastes a small crop of an app's interface and refers to it.
---

# Locant

Locant runs on the user's Mac. When the user points at an element and presses Return, Locant saves a
capture there: a cropped PNG and a JSON sidecar with the element's role, accessibility identifier,
frame, and ancestry, the app, and the user's note. The note says what to change; the identifier is
what to search the code for.

## Get the capture

1. If you have a Locant MCP tool such as `latest_capture`, call it and go to step 3.
2. Otherwise run this on the user's Mac, the local computer. Never run it on your own computer: Locant
   and its captures exist only on the Mac. Run it exactly as written; passing its output through `echo`
   breaks the JSON.

   ```sh
   L=/Applications/Locant.app/Contents/MacOS/Locant
   [ -x "$L" ] || L="$HOME/Applications/Locant.app/Contents/MacOS/Locant"
   if [ -x "$L" ]; then
     printf '%s\n' \
       '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"locant-skill","version":"1"}}}' \
       '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"latest_capture","arguments":{}}}' \
       | "$L" --mcp | tail -n 1 | plutil -extract result.content.0.text raw -o - -
   else
     echo "Locant is not in /Applications or ~/Applications."
   fi
   ```

   It prints the capture: the image path first, then the app, the note, the target element
   (role · identifier) and its path, then `### Sidecar` with the JSON, which holds the capture's `id`.
3. Open the PNG at the `Image:` path on the user's Mac to see the element.

## Act on it

4. Say in one line which capture you are using: the element and when it was captured. Then do what the
   note asks. To find the code, search the user's project on the Mac for the identifier. Don't ask which
   element they mean; the capture says.
5. When the change is done, mark the capture resolved: run the same command with this as the second
   request, using the `id` from the sidecar:

   ```
   {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"resolve_capture","arguments":{"id":"<id>"}}}
   ```

   Locant then keeps the capture past its retention period.
6. Read only the latest capture. Only when the user asks about an earlier one, call `list_captures`
   (with `"limit"`) or `get_capture` (with `"id"`) the same way. Never browse the capture folder.

## When something fails

Say what happened in one sentence; don't guess.

- "Locant is not in /Applications or ~/Applications.": Locant isn't installed there. Point the user to
  https://locant.malikzhang.com, or ask where it is.
- "No captures in …": the user hasn't pointed at anything yet. They press ⌃⌃ or click Locant's ball,
  click an element, type a note, and press Return.
- The command is refused: the user allows you to run commands on their local computer (in Grok Bot,
  "run commands on your local computer"). Until then a pasted capture brings only the image.
- The Mac can't be reached: the app you run in (Grok Bot) has to be open on the user's Mac.
````

- [ ] **Step 4: Run the checker and watch it pass**

Run: `/Users/malik/Documents/Locant/.claude/worktrees/locant-grok-bot-integration-ecdc4f/scripts/check-skill.sh`
Expected, exit 0:
```
OK  the command prints the latest capture
OK  the resolve request marks it resolved
```
If the first check fails with "no element in the payload", print `$out` from a scratch copy of the script and compare the element line with `MarkdownBuilder`'s format (`button "8" · id=Eight`); fix the fixture, not the skill.

- [ ] **Step 5: Run the command once more by hand, as a bot would**

Paste the `sh` block into `/bin/sh` (it reads Malik's latest capture; print only the first line):
`sed -n '/^ *```sh$/,/^ *```$/p' plugins/locant/skills/locant/SKILL.md | sed '1d;$d' | /bin/sh | head -1`
Expected: `## Locant capture (reference)` or `## Locant capture (fix)`.

- [ ] **Step 6: Commit**

```bash
git -C /Users/malik/Documents/Locant/.claude/worktrees/locant-grok-bot-integration-ecdc4f add scripts/check-skill.sh plugins/locant/skills/locant/SKILL.md
git -C /Users/malik/Documents/Locant/.claude/worktrees/locant-grok-bot-integration-ecdc4f commit -m "plugins: the Locant skill reads the latest capture on the Mac, and scripts/check-skill.sh runs it"
```

### Task 2: The plugin and the marketplace (R65)

**Files:**
- Modify: `scripts/check-skill.sh` (append the R65 block at the end)
- Create: `plugins/locant/.cursor-plugin/plugin.json`
- Create: `.cursor-plugin/marketplace.json`
- Create: `plugins/locant/README.md`
- Create: `plugins/locant/assets/logo.png` (a copy of `site/assets/icon-dark.png`)

**Interfaces:**
- Consumes: `scripts/check-skill.sh` and `plugins/locant/skills/locant/SKILL.md` from Task 1.
- Produces: the pushed branch as a Cursor plugin marketplace named `locant` with one plugin `locant` at `plugins/locant`; `plugins/locant/README.md`, whose "Every bot" line Task 4 may rewrite; the Cursor CLI result, recorded for the PR body.

- [ ] **Step 1: Append the manifest checks**

Append to `scripts/check-skill.sh`:

```zsh

# R65: the plugin and the marketplace that lists it.
manifest=$plugin/.cursor-plugin/plugin.json
market=.cursor-plugin/marketplace.json
field() { plutil -extract "$2" raw -o - "$1" 2>/dev/null || true }
for file in $manifest $market; do
  [[ -f $file ]] || fail "$file is missing"
  [[ -n $(field $file name) ]] || fail "$file does not parse, or has no name"
  grep -q '\.\./' $file && fail "$file has a path with .."
  grep -q '"/' $file && fail "$file has an absolute path"
done
[[ $(field $manifest name) == locant ]] || fail "plugin.json name must be locant"
[[ -n $(field $manifest description) ]] || fail "plugin.json has no description"
[[ $(field $manifest license) == MIT ]] || fail "plugin.json license must be MIT"
[[ $(field $manifest logo) == assets/logo.png && -f $plugin/assets/logo.png ]] \
  || fail "plugin.json logo must be assets/logo.png, and the file must exist"
[[ -z $(field $manifest mcpServers) && ! -e $plugin/mcp.json ]] || fail "the plugin must not carry an MCP server (R65)"
[[ $(field $market name) == locant ]] || fail "marketplace.json name must be locant"
[[ $(field $market owner.name) == "Malik Zhang" ]] || fail "marketplace.json owner.name must be Malik Zhang"
[[ $(field $market plugins.0.name) == locant && $(field $market plugins.0.source) == plugins/locant ]] \
  || fail "marketplace.json must list locant with source plugins/locant"
[[ -f $plugin/README.md ]] || fail "$plugin/README.md is missing"
print "OK  the plugin and marketplace manifests"
```

- [ ] **Step 2: Run it and watch it fail**

Run: `scripts/check-skill.sh` (from the worktree root)
Expected: the two `OK` lines from Task 1, then `FAIL: plugins/locant/.cursor-plugin/plugin.json is missing`, exit 1.

- [ ] **Step 3: Write the manifests, the README, and the logo**

`plugins/locant/.cursor-plugin/plugin.json`:
```json
{
  "name": "locant",
  "description": "Lets the agent read what you just pointed at with Locant on your Mac: the element, its accessibility identifier, the app, your note, and the cropped image. For agents that can run commands on your Mac but can't reach Locant's MCP server, such as Grok Bot.",
  "version": "1.0.0",
  "author": { "name": "Malik Zhang" },
  "homepage": "https://locant.malikzhang.com",
  "repository": "https://github.com/Malik1942/locant",
  "license": "MIT",
  "keywords": ["macos", "accessibility", "screenshot", "ui", "grok-bot"],
  "logo": "assets/logo.png"
}
```

`.cursor-plugin/marketplace.json`:
```json
{
  "name": "locant",
  "owner": { "name": "Malik Zhang" },
  "plugins": [
    {
      "name": "locant",
      "source": "plugins/locant",
      "description": "Read what you just pointed at with Locant on your Mac."
    }
  ]
}
```

`plugins/locant/assets/logo.png`: `mkdir -p plugins/locant/assets && cp site/assets/icon-dark.png plugins/locant/assets/logo.png`

`plugins/locant/README.md`:
```markdown
# Locant skill

[Locant](https://locant.malikzhang.com) is a macOS app: point at one element on screen, type a note,
and your coding agent gets the element (its role, accessibility identifier, the app, where it sits in
the tree, a cropped PNG, and your note) instead of a screenshot.

Claude Code, Cursor, and Codex fetch captures over Locant's MCP server (Settings › Agents). Grok Bot
can't: it starts MCP servers on the bot's own cloud computer, where Locant isn't, and a pasted capture
reaches it as the image alone. It can run commands on your Mac, though, and this skill uses that: it
starts Locant's MCP server once on your Mac, reads the latest capture, and opens its image.

## Set it up

- One bot: tell it "Save the skill at
  https://raw.githubusercontent.com/Malik1942/locant/main/plugins/locant/skills/locant/SKILL.md as a
  private skill named locant, word for word."
- Every bot: install the Locant plugin from the Marketplace once it is listed. In Cursor, add it now
  from Customize › From GitHub Repository with https://github.com/Malik1942/locant.

Then point at something with Locant (⌃⌃ or the ball, click, type a note, Return) and tell the bot "fix
what I just pointed at". The first time, Grok Bot asks whether it may run commands on your computer.

## Requirements

- Locant 0.7.1 or later, in /Applications or ~/Applications.
- The agent may run commands on your Mac. In Grok Bot that is "run commands on your local computer";
  a team admin can turn it off.
- Grok Bot open on the Mac, so the bot can reach it.

## What it reads

Only the latest capture, unless you ask about an earlier one. The capture's text and image go to the
bot's model, as they would if you pasted them. When the change is done the bot marks the capture
resolved, and Locant keeps it past its retention period.

## License

MIT, like Locant.
```

- [ ] **Step 4: Run the checker and watch it pass**

Run: `scripts/check-skill.sh`
Expected, exit 0:
```
OK  the command prints the latest capture
OK  the resolve request marks it resolved
OK  the plugin and marketplace manifests
```

- [ ] **Step 5: Commit and push**

```bash
cd /Users/malik/Documents/Locant/.claude/worktrees/locant-grok-bot-integration-ecdc4f
git add scripts/check-skill.sh plugins/locant .cursor-plugin
git commit -m "plugins: the locant plugin, and the repository lists it as a marketplace"
git push
```

- [ ] **Step 6: Load it in the Cursor CLI (spec §4 test 4), then undo**

```bash
agent plugin --help
agent plugin marketplace add https://github.com/Malik1942/locant.git --git-ref am/locant-grok-bot-integration-ecdc4f
agent plugin marketplace list --format json
```
Expected: the list names a marketplace `locant`. If `agent plugin --help` shows an install and a list subcommand, install `locant` from that marketplace and confirm the list shows the plugin with its one skill `locant`; then uninstall it. Finally `agent plugin marketplace remove locant` and confirm `agent plugin marketplace list` no longer shows it. Record the outcome in one sentence (for example "Cursor CLI 2026.09: the marketplace added from the branch, and `locant` installed with one skill") for the PR body. If a subcommand is missing, record exactly what the CLI said; don't claim more.

### Task 3: Grok Bot runs (spec §4 tests 2, 3, and 4's Grok half)

No repository changes. The results feed Task 4: the pass date, and whether a repository URL installs a plugin in Grok Bot.

**Interfaces:**
- Consumes: the pushed branch; the raw URL `https://raw.githubusercontent.com/Malik1942/locant/am/locant-grok-bot-integration-ecdc4f/plugins/locant/skills/locant/SKILL.md`.
- Produces: `passDate` (like `Sep 22, 2026`) if test 3 passes; `urlInstall` = `works` or `not supported`; screenshots in the session scratchpad `S=/private/tmp/claude-501/-Users-malik-Documents-Locant/112458ab-a8f4-4abe-ae99-84a200af20b8/scratchpad`, sent to Malik.

- [ ] **Step 1: Ask Malik, once, before touching his account or the Mac**

Ask with AskUserQuestion: (a) may the Tester bot save the skill as a private skill; (b) may Grok Bot's Marketplace try to install the plugin from the branch URL (uninstalled afterwards unless he keeps it); (c) who makes the neutral capture: Claude while he is away (the Mac for about 30 s), or Malik. Do only what he approves.

- [ ] **Step 2: One sentence (test 2)**

With the computer-use `app_*` tools on `com.anysphere.sand` (find the window with `app_list_windows`): open the Tester bot, `app_click` its "Prompt" text area, `app_type` with `overwrite_existing: true`:
`Save the skill at https://raw.githubusercontent.com/Malik1942/locant/am/locant-grok-bot-integration-ecdc4f/plugins/locant/skills/locant/SKILL.md as a private skill named locant, word for word.`
then `app_click` "Send message". Wait until the window stops changing: poll `screencapture -x -o -l <window id> $S/_poll.png` every 3 s and compare `md5 -q`, stopping after 5 unchanged polls or 100 s. Pass: Marketplace › Your plugins shows `locant` under Private skills for the Tester bot, and opening it shows a body that starts with `# Locant`. Save the screenshot as `$S/grok-skill-saved.png`.

- [ ] **Step 3: The neutral capture**

If Malik makes it: ask him to point at Calculator's "8" with the note "make this key bigger" and press Return (with Paste into your agent on, Locant pastes it into his last agent app; he can delete it there). If Claude makes it, only when `$S/ev idle` reports 40 s or more:

```zsh
S=/private/tmp/claude-501/-Users-malik-Documents-Locant/112458ab-a8f4-4abe-ae99-84a200af20b8/scratchpad
$S/clip save $S/clipboard-backup-2
osascript -e 'tell application id "com.malikzhang.deixis" to quit'
for i in {1..30}; do pgrep -f "MacOS/Locant$" >/dev/null || break; sleep 0.5; done
defaults write com.malikzhang.deixis pastesIntoAgent -bool false
open -a /Applications/Locant.app; sleep 3
open -a Calculator; sleep 1.5
centre=$(osascript <<'EOF'
tell application "System Events" to tell process "Calculator"
  repeat with e in (entire contents of window 1)
    try
      if value of attribute "AXIdentifier" of e is "Eight" then
        set p to position of e
        set s to size of e
        return (((item 1 of p) + (item 1 of s) div 2) as string) & " " & (((item 2 of p) + (item 2 of s) div 2) as string)
      end if
    end try
  end repeat
end tell
EOF
)
print $centre
$S/capture.sh ${=centre} "make this key bigger" e2e
```
`print $centre` shows the key's centre in screen points (for example `1178 540`). Expected from `capture.sh`: `new capture: /Users/malik/Pictures/Locant/locant-calculator-….json`. Then switch the option back and restore the clipboard:
```zsh
osascript -e 'tell application id "com.malikzhang.deixis" to quit'
for i in {1..30}; do pgrep -f "MacOS/Locant$" >/dev/null || break; sleep 0.5; done
defaults write com.malikzhang.deixis pastesIntoAgent -bool true
open -a /Applications/Locant.app
$S/clip restore $S/clipboard-backup-2
```
Either way, name the capture and confirm it is the newest by running the skill's command and printing only the element line:
```zsh
e2e=$(ls -t ~/Pictures/Locant/locant-calculator-*.json | head -1); e2e=${e2e%.json}; print $e2e
sed -n '/^ *```sh$/,/^ *```$/p' plugins/locant/skills/locant/SKILL.md | sed '1d;$d' | /bin/sh | grep -m 1 'id=Eight'
```
The second command must print `button "8" · id=Eight`; if it prints nothing, the newest capture is not the neutral one: stop and ask Malik.

- [ ] **Step 4: End to end (test 3, which dates the chip)**

Start a new conversation with the Tester bot: "New chat", type `Tester` in "Search or create Bots", press Return. If Grok Bot reopens the old thread instead, continue there and say so in the results. Send only: `what did I just point at?` Wait as in step 2. Pass, all of: the bot ran something on Malik's computer without being told how; its answer names `button` and `Eight`, Calculator, the note "make this key bigger", and the path `/Users/malik/Pictures/Locant/locant-calculator-….png`, and describes the image (the 8 key); it did not ask which element. Save `$S/grok-e2e.png` and send it to Malik. On a pass, record `passDate=$(date '+%b %-d, %Y')`. On a fail, record what the bot did and stop before Task 4; tell Malik.

- [ ] **Step 5: Resolve**

Send: `Done, mark it resolved.` Pass: `plutil -extract resolved raw -o - $e2e.json` prints `true`.

- [ ] **Step 6: Install by URL (test 4's Grok half, only if approved)**

Marketplace → the "Search plugins and Bots" field → type `https://github.com/Malik1942/locant/tree/am/locant-grok-bot-integration-ecdc4f` → Return → screenshot `$S/grok-url-install.png`. If a Locant result with Install appears: install it, confirm Your plugins lists `locant` with one skill, then Uninstall (unless Malik keeps it); `urlInstall=works`. Otherwise `urlInstall=not supported`.

- [ ] **Step 7: Clean up**

Move the e2e capture to the Trash with Finder, never `rm`:
`for ext in json png; do osascript -e "tell application \"Finder\" to delete (POSIX file \"$e2e.$ext\" as alias)"; done`
Confirm `ls -t ~/Pictures/Locant/locant-*.json | head -1` is not the e2e capture, `defaults read com.malikzhang.deixis pastesIntoAgent` prints `1`, and call `app_release`.

### Task 4: Sentences on the site and in the README; the PR (R66, R67, spec §4 test 5)

Run only after Task 3 step 4 passed.

**Files:**
- Modify: `site/index.html` (the `#agents` lede, line 663; the Grok Bot and Gemini CLI rows, lines 669–670)
- Modify: `README.md` (line 193; the table, lines 196–201; a new "### In Grok Bot" after line 127)
- Modify: `plugins/locant/README.md` (the "Every bot" line, only if `urlInstall=works`)

**Interfaces:**
- Consumes: `passDate` and `urlInstall` from Task 3; the Cursor CLI sentence from Task 2 step 6.

- [ ] **Step 1: The site**

In `site/index.html`, replace `The payload is plain Markdown, so any agent takes it on paste.` with `The payload is plain Markdown, so most agents take it on paste.` Replace the two lines

```html
      <div class="agent"><b>Grok Bot</b><span>A paste carries only the image; ask it to read the capture on your Mac</span><span class="chip">Verified Sep 22, 2026</span></div>
      <div class="agent"><b>Gemini CLI, Antigravity</b><span>Paste, or the snippet from Settings › Agents</span><span class="chip dash">Untested</span></div>
```
with (the Grok Bot chip carries `passDate`; Sep 22, 2026 if Task 3 passed today)
```html
      <div class="agent"><b>Grok Bot</b><span>Reads the capture on your Mac with the <a href="https://github.com/Malik1942/locant#in-grok-bot">Locant skill</a>; a paste carries only the image</span><span class="chip">Verified Sep 22, 2026</span></div>
      <div class="agent"><b>Antigravity</b><span>Takes the paste and opens the image at the path</span><span class="chip">Verified Sep 18, 2026</span></div>
      <div class="agent"><b>Gemini CLI</b><span>Paste, or the snippet from Settings › Agents</span><span class="chip dash">Untested</span></div>
```

- [ ] **Step 2: Look at it (test 5)**

Open `file:///Users/malik/Documents/Locant/.claude/worktrees/locant-grok-bot-integration-ecdc4f/site/index.html#agents` in the browser pane. At 1280 × 800 and at the mobile preset, scroll `#agents` into view and check with JavaScript that the rows read Claude Code, Cursor, Codex CLI, Grok Bot, Antigravity, Gemini CLI, that the Grok Bot link's `href` is `https://github.com/Malik1942/locant#in-grok-bot`, and that `document.documentElement.scrollWidth === window.innerWidth`. Screenshot both; the link must be legible against the muted row text. Reset the viewport to desktop.

- [ ] **Step 3: Commit the site**

```bash
git add site/index.html
git commit -m "site: most agents take a paste; Grok Bot reads the capture with the Locant skill; Antigravity and Gemini CLI get their own rows"
```

- [ ] **Step 4: The README (the spec's last slot)**

Line 193: `so any agent takes it on paste` → `so most agents take it on paste`.

Replace the table row `| Gemini CLI / Antigravity | The snippet from Settings › Agents; untested | Markdown text; untested | |` with (the Grok Bot date is `passDate`):
```markdown
| Grok Bot 0.57.1 | Fails: stdio connectors start on the bot's own cloud computer (`spawn … ENOENT`); the [Locant skill](#in-grok-bot) reads the capture on the Mac instead | The image only; the Markdown is dropped | Sep 22, 2026 |
| Antigravity 2.15.0 | Not connected | Markdown text; opened the PNG at the `Image:` path and searched the identifier | Sep 18, 2026 |
| Gemini CLI | The snippet from Settings › Agents; untested | Markdown text; untested | |
```

After line 127 (`The server reads the folder chosen in Settings › Captures; `--folder <path>` names another.`), insert:
```markdown

### In Grok Bot

Grok Bot starts MCP servers on the bot's own cloud computer, where Locant isn't, and a pasted capture
reaches it as the image alone. It can run commands on your Mac, though, and the Locant skill in
[`plugins/locant`](plugins/locant) uses that: it starts `Locant --mcp` once on your Mac, reads the latest
capture, and opens its image. Set it up once:

- One bot: tell it "Save the skill at
  https://raw.githubusercontent.com/Malik1942/locant/main/plugins/locant/skills/locant/SKILL.md as a
  private skill named locant, word for word."
- Every bot: install the Locant plugin from Grok Bot's Marketplace once it is listed. In Cursor, add it
  now from Customize › From GitHub Repository with https://github.com/Malik1942/locant.

Then point, and say "fix what I just pointed at". The first time, Grok Bot asks to run commands on your
Mac.
```
If `urlInstall=works`, the "Every bot" bullet instead reads `- Every bot: paste https://github.com/Malik1942/locant into Grok Bot's Marketplace search and install Locant.`, and the same change goes into `plugins/locant/README.md`'s "Every bot" bullet.

- [ ] **Step 5: Check and commit the README**

Run: `grep -n "most agents take it on paste\|### In Grok Bot\|| Grok Bot 0.57.1\|| Antigravity 2.15.0\|| Gemini CLI |" README.md` → five lines. Run `scripts/check-skill.sh` → three `OK` lines.
```bash
git add README.md plugins/locant/README.md
git commit -m "readme: In Grok Bot, and the agent table's Grok Bot, Antigravity, and Gemini CLI rows"
```

- [ ] **Step 6: Push and update the PR**

`git push`, then `gh pr edit 42 --repo Malik1942/locant --title "Grok Bot: the Locant skill, and the agents table"` and `--body-file` a body with: what the PR adds (the skill and plugin in `plugins/locant`, the marketplace manifest, `scripts/check-skill.sh`, the spec and this plan, the site and README sentences); what each test found (Task 2 step 6's sentence, Task 3 steps 2, 4, 5, 6 in one line each, with `passDate`); what stays with Malik (merging; the Marketplace submission; deleting the Tester bot). Then post the submission draft with `gh pr comment 42 --repo Malik1942/locant --body-file`:

```markdown
Draft for cursor.com/marketplace/publish (Malik submits after the merge):

- Repository: https://github.com/Malik1942/locant (marketplace manifest at `.cursor-plugin/marketplace.json`, plugin at `plugins/locant`)
- Name: locant
- Description: Lets the agent read what you just pointed at with Locant on your Mac: the element, its accessibility identifier, the app, your note, and the cropped image. For agents that can run commands on your Mac but can't reach Locant's MCP server, such as Grok Bot.
- For reviewers: one skill, no MCP server, no binaries. The skill runs the user's own Locant app (`/Applications/Locant.app/Contents/MacOS/Locant --mcp`, MIT, notarized) once on the user's Mac to read the latest capture, and `plutil` to print it. It reads only the latest capture unless the user asks for an earlier one. Tested on Sep 22, 2026 in Grok Bot 0.57.1 with Locant 0.8.1.
```
Read the CI state with `mcp__ccd_pr__get_status` (not `gh pr checks`), and report the PR link, what passed, and the two things left to Malik.
