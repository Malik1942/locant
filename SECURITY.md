# Security

## What Locant touches

- **Accessibility.** Reads the element under your cursor and listens for its hotkeys through one event tap. A matched chord is swallowed; every other key passes through untouched, and nothing is logged.
- **Screen Recording.** Captures the pixels of the element or region you chose, through ScreenCaptureKit, with Locant's own windows excluded.
- **Recapture when your app changes** (Settings › Captures, on by default). For a day after a Point capture in an app you build, each time that app comes forward Locant looks for the element again over Accessibility, captures its region of the screen, and when the pixels differ writes an after-image beside the capture with the git facts. Only your own apps (fix mode); other apps are never watched.
- **A local web page you point at** (off until you allow a browser in Settings › Captures › Web pages). For a Point capture of a page served from this Mac (`localhost`, `127.0.0.1`, `*.local`) in Chrome, Edge, Brave, or Dia, Locant sends that browser one Apple Event that runs a script in the page. The script reads what React's development build keeps about the element (component names, a short preview of its props, the stacks where its JSX ran) and returns; it fetches nothing and changes nothing but one script element it adds and removes in the same step, which the browser needs to let a script see the page's own objects. Locant then reads the page's source maps from the same dev server. A page from anywhere else is never asked, and macOS's Automation prompt for a browser appears only when you press Allow in Settings, never during a capture.
- **The clipboard.** Written only after a capture succeeds, with one item carrying the PNG and the Markdown. A failed capture never touches it. With **Paste into agent** on (off by default), Locant also brings forward the agent app you used last and posts ⌘V into it; it never presses Return.
- **Paste completion** (on by default; `defaults write com.malikzhang.deixis completesPaste -bool NO` turns it off). While the clipboard still holds the newest capture, your own plain ⌘V in Cursor, Codex, or Grok Bot makes Locant read that app's front window over Accessibility to find the message box, and add the image after the text your key pasted. The key is never held, replaced, or posted again, and nothing is read in any other app.
- **Files.** `~/Pictures/Locant` (or the folder you chose) for captures and their JSON sidecars; its settings under `com.malikzhang.deixis`. With Connect in Settings › Agents, one `locant` server entry in `~/.claude.json`, `~/.cursor/mcp.json`, or `~/.codex/config.toml`; Disconnect removes it.
- **git.** Before & After reads `git` facts about your repository through `/usr/bin/git`, read-only. Locant never commits, never installs hooks, never writes to a repository.

## What it never does

- No network beyond your own Mac, except one daily request to `api.github.com` for the newest release, carrying the version number in the User-Agent and nothing else. Settings › General turns it off. The only other requests are to a dev server on this Mac, for the source maps of a local page you pointed at.
- No telemetry, analytics, accounts, or crash reporting.
- No private API.

The MCP server (`Locant --mcp`) reads the sidecars in the capture folder and writes only a `resolved` flag. It listens on stdio for the agent that started it and opens no port.

## Reporting

Please report a vulnerability privately through GitHub's **Security › Report a vulnerability** on this repository rather than in a public issue. You will get a reply within a week. Anything that lets a page, an app, or an MCP client read more than the capture you pointed at, write outside the capture folder and the three agent configurations, or reach the network counts.
