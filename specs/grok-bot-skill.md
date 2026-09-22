# Grok Bot: a Locant skill any bot can pick up (no app change)

**Status:** designed Sep 22, 2026 with Malik; not built. Nothing under `Locant/` changes: Malik's rule
for this work is that Locant is not modified to suit Grok Bot. Branch `am/locant-grok-bot-integration-ecdc4f`,
PR #42 (open, not merged). Requirements continue from R63.

## 1. What Grok Bot does with a capture today

Tested Sep 22, 2026 with Grok Bot 0.57.1 (`com.anysphere.sand`) and Locant 0.8.1, in a new test bot, with
Calculator captures only.

| Route | Result | Why |
|---|---|---|
| Paste (⌘V) | The image only; the Markdown, note, identifier, and path are dropped | The composer's paste handler attaches every clipboard item of kind "file" and returns; text is inserted only when there is no file |
| MCP | Fails: `failed_to_load: spawn /Applications/Locant.app/Contents/MacOS/Locant ENOENT` | Stdio connectors start on the bot's own cloud computer; HTTP connectors are called from the backend. Neither reaches the Mac |
| Ask the bot to read the capture on the Mac | Works: `button` · `Eight`, Calculator, the note, Locant's image path, and the image | Bots run commands and read files on the user's computer through Grok Bot's local exec daemon |

The last route is a Grok Bot permission, "run commands on your local computer": `always`, `ask`, or
`never`, and a team admin can cap it. A bot doesn't know Locant exists, and a paste carries only the
image, so a one-time step per user can't be avoided without changing Locant. This spec makes that step
one sentence, or one install.

## 2. Layout additions

```
.cursor-plugin/marketplace.json            the repository is a plugin marketplace with one plugin, locant
plugins/locant/.cursor-plugin/plugin.json  the plugin manifest
plugins/locant/skills/locant/SKILL.md      the skill (R64), the only component
plugins/locant/README.md                   what it does, setup, requirements, privacy
plugins/locant/assets/logo.png             site/assets/icon-dark.png, 512 × 512
specs/grok-bot-skill.md                    this file
```

## 3. Requirements

**R64 The skill.** `plugins/locant/skills/locant/SKILL.md`, frontmatter `name: locant` (it must match
the folder) and a `description` that names when to use it: the user refers to something they pointed at
with Locant ("what I just pointed at", "this button", "fix this"), mentions Locant or a capture, or
pastes a small crop of an app's interface and refers to it. The body tells the bot:

1. If a Locant MCP tool such as `latest_capture` is available, call it and go to step 3. So in Claude
   Code, Cursor, or Codex, where Settings › Agents connects the server, the skill changes nothing.
2. Otherwise run this on the user's Mac, the local computer, never the bot's own computer: Locant and
   its captures exist only on the Mac.

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

   It starts Locant's own MCP server once (R53), calls `latest_capture` (R54), and prints the result's
   text: the payload the clipboard carries, image path first, then `### Sidecar` and the JSON with the
   capture's `id`. The server reads the folder chosen in Settings › Captures, so the skill never names
   a folder. `plutil` ships with macOS; nothing is installed. The skill says to keep the pipe as
   written: passing the response through `echo` breaks it, because zsh's `echo` turns the `\n` escapes
   in the JSON into newlines (verified in zsh and `/bin/sh`, Sep 22).
3. Open the PNG at the `Image:` path on the Mac, to see the element.
4. Say in one line which capture it is (the element and the time), then do what the note asks. Grep for
   the identifier in the user's code on the Mac. Never ask which element: the capture says.
5. When the change is done, run the command again with
   `{"name":"resolve_capture","arguments":{"id":"<id from the sidecar>"}}` in place of the second
   request. Locant then keeps the capture past the retention period.
6. Read only the latest capture. `list_captures` (with `limit`) and `get_capture` only when the user asks
   for an earlier one. Never browse the capture folder.

When something fails, the bot says so in one sentence and doesn't guess:
- "Locant is not in …": Locant isn't installed there; give https://locant.malikzhang.com, or ask where it is.
- "No captures in …": the user points first, with ⌃⌃ or the ball.
- The command is refused (`never`, or a team cap): the user allows "run commands on your local
  computer" in Grok Bot; until then a paste carries only the image.
- The Mac can't be reached: Grok Bot must be open on the Mac.

Locant 0.7.1 or later is required (`--mcp`); older copies start the app instead of the server. The
update check has offered 0.7.1 or later to every install since Sep 15, so the skill doesn't check the
version.

**R65 The plugin.** `plugins/locant/.cursor-plugin/plugin.json`: `name` `locant`, `description`,
`version` `1.0.0`, `author` `{ "name": "Malik Zhang" }`, `homepage` https://locant.malikzhang.com,
`repository` https://github.com/Malik1942/locant, `license` `MIT`, `keywords`
`["macos", "accessibility", "screenshot", "ui", "grok-bot"]`, `logo` `assets/logo.png`.
Skills are found in `skills/`; the manifest doesn't list them. No MCP server: in Grok Bot a plugin's
server would start on the bot's computer and fail as in §1. `.cursor-plugin/marketplace.json` at the
repository root: `name` `locant`, `owner` `{ "name": "Malik Zhang" }`, and one plugin, `locant`, with
`source` `plugins/locant`. Every path is relative. `plugins/locant/README.md` covers what it does, both
setups (R66), the requirements (Locant 0.7.1 or later; Grok Bot allowed to run commands on the Mac), and
privacy: only the latest capture is read, and its text and image go to the bot's model, as they would
on paste.

**R66 Setup.** Two ways, both in the README and on the site (R67):
- Per bot, today: tell the bot "Save the skill at
  https://raw.githubusercontent.com/Malik1942/locant/main/plugins/locant/skills/locant/SKILL.md as a
  private skill named locant, word for word."
- Every bot at once: install the Locant plugin. From the Marketplace once it is listed; or by the
  repository URL where Grok Bot or Cursor accepts one (Cursor: Customize › From GitHub Repository, or
  `agent plugin marketplace add https://github.com/Malik1942/locant`).

Malik submits the plugin at cursor.com/marketplace/publish after the merge (and may list it on
cursor.directory); Claude drafts the text and does not submit. Cursor reviews every listing and every
update by hand and currently works with a small group of partners, so the per-bot sentence stays the
path that works on day one.

**R67 Sentences.**
- Site, `#agents` lede: "so any agent takes it on paste" becomes "so most agents take it on paste".
- Site, the rows after Codex CLI:
  - **Grok Bot** · "Reads the capture on your Mac with the Locant skill; a paste carries only the
    image" · Verified (the date of the §4 test 3 run). "Locant skill" links to
    https://github.com/Malik1942/locant#in-grok-bot.
  - **Antigravity** · "Takes the paste and opens the image at the path" · Verified Sep 18, 2026. From
    Antigravity's own log of Sep 18, 20:28 PDT: the payload arrived whole, the first step opened the
    PNG at the `Image:` path, and the search went straight to `oceanCurrent` without asking. The run
    was stopped before an answer, and Antigravity has no Locant MCP entry.
  - **Gemini CLI** · "Paste, or the snippet from Settings › Agents" · Untested (not installed on this Mac).
- README, Works where you paste: the same "most agents" change; a Grok Bot 0.57.1 row (Over MCP: "Fails:
  stdio connectors start on the bot's own cloud computer (`spawn … ENOENT`); the Locant skill reads the
  capture on the Mac instead"; On paste: "The image only; the Markdown is dropped"); Gemini CLI and
  Antigravity split, with Antigravity 2.15.0 "Not connected" over MCP and "Markdown text; opened the PNG
  at the `Image:` path and searched the identifier" on paste, Sep 18, 2026.
- README, Or let the agent fetch it: a new "### In Grok Bot" at its end: why MCP can't work there (one
  sentence), the two setups (R66), then "point, and say 'fix what I just pointed at'; the first time,
  Grok Bot asks to run commands on your Mac".

## 4. Verification

1. Static: both manifests parse and carry the fields above; the skill's `name` matches its folder; the
   R64 command, pasted into a plain shell, prints the payload; `resolve_capture` works on a scratch copy
   passed with `--folder`, never on Malik's captures.
2. One sentence: the Tester bot saves the skill from the branch's raw URL, and it shows under Private
   skills. (This changes Malik's Grok Bot account: ask first.)
3. End to end, the test that dates the Grok Bot chip: a neutral capture is the newest (made while Malik
   is away, with Paste into your agent switched off around it, or by Malik). In a new conversation, the
   only message is "what did I just point at?". It passes when the bot uses the skill without being told,
   and states the element with role and identifier, the app, the note, and Locant's image path, and
   describes the image, without asking which element. The test capture then goes to the Trash.
4. The plugin loads: `agent plugin marketplace add` with the pushed branch in the Cursor CLI lists the
   skill; the repository URL is tried in Grok Bot's Marketplace search (installing changes the account:
   ask first). Either result is recorded in the PR; the README claims only what worked.
5. The site at desktop and phone widths: the rows read in order and nothing scrolls sideways.

## 5. Out of scope

Any change to the app: a text-only copy, a different paste order, an HTTP transport for the MCP server,
adding `com.anysphere.sand` to Paste into your agent. Submitting to the Marketplace (Malik). Testing
Gemini CLI. A full re-run in Antigravity (possible later with a neutral capture).
