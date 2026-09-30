# Security

## What Locant touches

- **Accessibility.** Reads the element under your cursor and listens for its hotkeys through one event tap. A matched chord is swallowed; every other key passes through untouched, and nothing is logged.
- **Screen Recording.** Captures the pixels of the element or region you chose, through ScreenCaptureKit, with Locant's own windows excluded.
- **The clipboard.** Written only after a capture succeeds, with one item carrying the PNG and the Markdown. A failed capture never touches it. With **Paste into agent** on (off by default), Locant also brings forward the agent app you used last and posts ⌘V into it; it never presses Return.
- **Files.** `~/Pictures/Locant` (or the folder you chose) for captures and their JSON sidecars; its settings under `com.malikzhang.deixis`. With Connect in Settings › Agents, one `locant` server entry in `~/.claude.json`, `~/.cursor/mcp.json`, or `~/.codex/config.toml`; Disconnect removes it.
- **git.** Before & After reads `git` facts about your repository through `/usr/bin/git`, read-only. Locant never commits, never installs hooks, never writes to a repository.

## What it never does

- No network, except one daily request to `api.github.com` for the newest release, carrying the version number in the User-Agent and nothing else. Settings › General turns it off.
- No telemetry, analytics, accounts, or crash reporting.
- No private API.

The MCP server (`Locant --mcp`) reads the sidecars in the capture folder and writes only a `resolved` flag. It listens on stdio for the agent that started it and opens no port.

## Reporting

Please report a vulnerability privately through GitHub's **Security › Report a vulnerability** on this repository rather than in a public issue. You will get a reply within a week. Anything that lets a page, an app, or an MCP client read more than the capture you pointed at, write outside the capture folder and the three agent configurations, or reach the network counts.
