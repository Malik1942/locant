# MCP discovery: when to call, and the Registry

Nov 25 2026. Agents pick tools from their names, descriptions and the server's instructions, nothing else.
Clients that defer tools (Claude Code's tool search) load a server's tools only when the instructions or a
search over names, descriptions and parameter names says to, and descriptions written as "call this when"
are picked more often than ones that say what a tool is. People still find servers themselves, mostly through
the official MCP Registry and the directories and client galleries that copy it.

**R185 When to call.** `MCPServer.instructions` and every tool description lead with when to call, in the
user's words. The instructions say what Locant is in one paragraph, then: call `latest_capture` first when the
user refers to something on screen the agent cannot see ("this", "that button", "here", "what I just pointed
at", "the one I selected", in any language), asks to change, fix, restyle, move or explain part of an app's or a
web page's interface without a screenshot, file or line, or mentions Locant or a capture; do it before asking for
a screenshot or a description; check the Captured time; then the Image path, the "In source:" line (else the
identifier, DOM id or classes, or label text), the Project line, `resolve_capture` when done, and
`list_captures`/`get_capture` only for earlier captures. Each tool description starts "Call this "; the
`latest_capture` one names the screen, a screenshot, the UI and the note, so a search for any of them finds it.
Tool names, schemas, results and annotations are unchanged (R54, R55).

**R186 The Registry.** Locant is listed in the official MCP Registry as `io.github.Malik1942/locant`, from
`packaging/mcp/server.json`. The Registry lists packages, not apps, and an `mcpb` package must be a release
asset on GitHub whose URL contains "mcp". So each release may carry `locant-mcp.mcpb`, built by
`scripts/mcpb.sh`: a manifest (`compatibility.platforms` darwin) and `server/locant-mcp`, a launcher that
execs `Locant --mcp` from `$LOCANT_APP`, `/Applications` or `~/Applications`, and otherwise says on stderr
where to get Locant and exits 1. The script stamps the project version, the release URL and the bundle's
sha256 into `server.json`; the zip is built with fixed dates, so the same files give the same sha256.
Publishing is by hand, after the release: `gh release upload`, `mcp-publisher login github`, `mcp-publisher
publish` from `packaging/mcp`.
