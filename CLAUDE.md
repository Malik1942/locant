# Locant

Native macOS menu bar tool: point at any UI element, hand a coding agent a grep-able reference.
Read `docs/PRD.md` for background only. The task you are working on is always the file I name in `specs/`. If the spec and the PRD disagree, the spec wins; say so and continue.

## How we work
- One task at a time, from one spec file. Do not start work that is not in the spec.
- Ask before adding a dependency, a permission, a target, or a file outside the layout in the spec.
- Small commits, one intent each, message in the form `area: what changed`. Never commit without a green build.
- When a spec slot overruns, cut polish from the next slot, not its core. Tell me when you do.
- Report in three lines: what you did, what you skipped, what you are unsure about. No summaries of the code.

## Code
- Swift 6, strict concurrency `complete`. `async/await` only; no completion handlers.
- Value types for data (`struct`, `Codable`). Classes only for objects that own system resources (windows, monitors, panels).
- One `@Observable` `AppState`. No other singletons.
- Errors are typed enums, never strings.
- Pure functions for anything transformable: AX attributes → `ResolvedElement`, `Capture` → Markdown. These get tests; UI does not in v0.1.
- No third-party packages. Foundation, AppKit, SwiftUI, ScreenCaptureKit, Vision, ApplicationServices, and AudioToolbox (the two interface sounds, specs/v0.8.1.md R60) only.
- Accessibility calls run on a background actor. The main actor touches AppKit only.
- Locant must never appear in its own captures. Every ScreenCaptureKit call goes through a filter that excludes our windows.
- Never overwrite the clipboard on a failed capture.
- No network calls except the release check (specs/v0.6.md R45). No telemetry. No analytics.

## Data contract
- `schema/capture.schema.json` is the only interface between the app and anything else. Field names are platform-neutral (`role`, `label`, `identifier`, `frame`, `path`), never `AX`-prefixed.
- Every capture writes a PNG and a JSON sidecar. The Markdown on the clipboard is derived from the JSON, never the other way around.
- The MCP server (`Locant --mcp`, specs/v0.7.1.md) reads the sidecars through the same `Capture` model and writes only `resolved`. It adds no second interface.

## Do not
- Do not create windows, dashboards, onboarding, or Settings unless the spec names them.
- Do not use private API (no `AXPTranslator`, no SPI). If public API cannot do it, stop and tell me.
- Do not reformat files you did not need to touch.
- Do not write the README until the spec's last slot.
