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
