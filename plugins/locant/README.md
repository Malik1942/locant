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
