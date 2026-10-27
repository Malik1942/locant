# Locant: hover in Device Hub's phone reads less

**Status:** Spec written Oct 27, 2026, after the 1.1.0 release (`specs/capture-shapes.md` R133–R135, PR #75). Hover over Xcode 27 Device Hub's simulated screen is slow: one `AccessibilityReader.snapshot(at:candidates:fallbackPID:)` there cost p50 ~64 ms on the 1.0.1 reader and ~80–100 ms on 1.1.0, p95 ~210 ms, max ~550 ms, while the Mac sidebar of the same process costs 2 ms and a Chromium window 1.2 ms. Measured the same day with a read-only probe that calls the reader at every point of a grid over the phone (Oryne's Tide screen, Device Hub window 12,54 783×940, the screen 347.9,137.5 359.7×780.9), counting and timing every accessibility call:

| Call (Device Hub's phone) | Cost each |
|---|---|
| The hit test, `AXUIElementCopyElementAtPosition` on the app | 45–67 ms |
| `AXIdentifier` | 1.1–2.5 ms |
| `AXChildren` of the screen group (19 children) | 9.5 ms |
| The children count, `AXUIElementGetAttributeValueCount` | 2.2 ms |
| `AXDescription`, `AXSubrole`, `AXFrame` | 0.2–0.9 ms |
| `AXRole`, `AXTitle`, `AXParent` | 0.1 ms |
| Six attributes of one element in one `AXUIElementCopyMultipleAttributeValues` | 0.5–0.7 ms, against 2.5–3.4 ms read one by one, with identical values (40 elements, 0 differences) |

A hit test on the window or the screen group instead of the app answers nothing, so the hit test stays as it is and sets the floor. Everything after it is attribute reads, about 106 calls per point, and those are what this spec cuts. Numbered from R136 (`specs/capture-shapes.md` ends at R135).

**Scope of this spec:** how `AccessibilityReader` reads attributes and children during hover and drawn frames.
**Out of scope:** what the reader finds (every snapshot is the same as before on a screen that does not change); the hit test; the ladder, shapes, and text lines; the payload; the schema. Three other ideas were measured on the same grid and left out, since each would make what hover shows older than it is today for little:
- **Longer cache lifetimes.** With R136–R137 in, a 2 s `neighborTTL` instead of 400 ms saves 6 ms at p50 and 16 ms at p95, for labels and frames five times staler. Lifetimes stay as they are (400 ms, the real screen 5 s).
- **Keeping an element's attributes between hovers on it.** The hit's own read is one batched call (about 1.5 ms) and, for a leaf, its count; kept, a value or label that changes would stay old until the cache ran out.
- **The second snapshot after `overlay` or `smallerSibling`.** It runs at 7% of points and reads another element, the one that answers; its ancestors already come from the cache.

Read `CLAUDE.md`, `specs/capture-shapes.md` R128 and R133, and `Locant/Resolve/AccessibilityReader.swift`.

## 1. Requirements

**R136. One read per element.** The attributes of an element (`lightAttributes`, `attributes`, and the DOM id and class list of a web node) come from one `AXUIElementCopyMultipleAttributeValues` call, not one call each. An attribute the element does not have comes back as an error value and reads as missing, exactly as a failed single read does. When the call itself fails, the attributes are read one by one, as before. The children count stays its own call. The hit's window and frame, read to decide whether the answer shows at the point (R3), come from one call too.

**R137. Nothing read twice in one lookup.**
- The hit element's full attributes, read to decide whether it is a container (`refine`), are the ones its snapshot uses when refining keeps it (`read`), not read again.
- A container hit whose children the neighbor cache had to read afresh uses those children for the walk in `refine`, instead of reading them a second time. When the cache answered, the live children are still read and compared with it, as before.
- A container hit's children count is the number of those live children, not a call of its own (on the screen group it costs as much as reading them). Only a hit that is not a container asks for its count.

**R138. Unchanged.** The hit test; which elements are read; `neighborTTL` (400 ms) and every other lifetime and key; R133's searches and their limits; the attributes read (the same names, the same values). On a screen that does not change, every snapshot, and so every ladder, is the one 1.1.0 builds. Outside Device Hub the same reads are batched the same way and answer the same.

**R139. Words elsewhere.** CHANGELOG gains an Unreleased section with one bullet: hover over the iPhone screen in Device Hub follows the pointer faster.

## 2. Files

- Changed: `Locant/Resolve/AccessibilityReader.swift` (R136, R137), `CHANGELOG.md` (R139).
- No test file changes: unit tests have no accessibility tree, and the reader's reads are not reachable from them.

## 3. Tests

- The existing tests pass.
- The live probe is the check, read-only and with no input sent (the Mac is in use). A grid of 12 pt over Device Hub's phone, walked row by row in alternating directions with the app's 33 ms pause between lookups, once with the 1.1.0 reader and once with this one, back to back, twice in alternating order:
  - every grid point gives the same snapshot (encoded, element, ancestors, children, siblings) and the same ⌥ ladder, with and without shapes from one screenshot of the window;
  - the table of p50, p95, and max per lookup, and calls per point, before and after.
- The same comparison on the Device Hub sidebar and on a Chromium window (Claude), where the batched read must answer the same as the single reads.
