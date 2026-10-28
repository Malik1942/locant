# Locant: a drawn frame reads only the window it was drawn on

**Status:** Spec written Oct 28, 2026, after Malik drew a frame over a page in Dia (`Personal: Oryne | Malik…`, full screen on the built-in display). The frame came back with dashed marks over empty parts of the page, and its target element was `heading "[2027] Associate Product Designer, Early Career"`, a Roblox careers page that was nowhere on screen. Measured the same day: that page was a second Dia window, minimized (`AXMinimized` 1), which still reports the frame it had on screen (75, 6, 1456×780). R12's walk starts at the application and goes into every window it lists, so the minimized window's heading and links fell inside the frame. Numbered from R136 (PR #75 holds R124–R135).
**Scope of this spec:** which of an app's windows R12's walk goes into, for a drawn frame and for iterations (R52).
**Out of scope:** the hover's hit test (R3), which asks the app at a point and already drops an answer that does not show there.

This spec makes `specs/v0.2.md` R12's "walk the tree of the app under the drag start (window hit-test as in R3)" hold for apps with more than one window.

## 1. Requirements

**R136. The windows a frame reads.** The walk goes into none of the app's minimized windows. Of the rest, it goes only into the window the frame was drawn on: the one the hit test at the drag start answered from, or else the window list's topmost normal window there, matched to an accessibility window by its frame (within 2 pt, as `Geometry.answerIsVisible` matches). When no window matches (the drag started on the desktop, the Dock, or a frame that reads a few points off), it goes into every window that is not minimized, as before. The app's other children (its menu bar, the Finder desktop) are walked as before. Iterations (R52) pass no window and so skip only minimized ones. The choice is pure: `Geometry.regionWindows(_:owner:)`.

## 2. Files

- Changed: `Geometry.swift` (`AppWindow`, `regionWindows`), `AccessibilityReader.swift` (the walk takes the window's bounds and filters the application's children), `AppState.swift` (the drawn frame passes the window it was drawn on).

## 3. Tests

- `GeometryTests`: the window drawn on, never a minimized one; with no owner, every window that shows; the app's window behind the one drawn on stays out; an owner that is none of them gives every window that shows; a window whose frame cannot be read stands.
- The existing tests pass.
- In the app: Dia full screen with a second Dia window minimized. Draw a frame over the page: the dashed marks sit on the page's own headings and links, and the capture's target element is one of them, not an element of the minimized window.
