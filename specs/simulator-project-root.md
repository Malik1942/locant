# Locant: the Project line names the build that is on screen

**Status:** Spec written Oct 19, 2026, after the Oryne redesign captures of Oct 18 (22:18–23:46) were found to name the wrong worktree: 9 of 18 Device Hub captures say `Project: …/worktrees/oryne-apple-watch-app-177fc5`, yet their images show the redesign (the serif "Drifted in" heading), which exists only in `oryne-product-opportunities-a913cb`. Since PR #48 the line under it says "The app on screen was built from this folder", so those payloads told the agent to change the wrong checkout. One agent passed it on: at 22:58 the session in the redesign worktree (94a84403) told Malik his screenshots came from the Watch worktree and that he should rebuild the other one, yet the Watch branch at those captures' `gitCommit` (b52098d) has none of the "Nearby" or "Tide" strings they show. Malik approved it the same day with option A (§3). Numbered from R105 (`specs/ball-findable.md` ends at R104).
**Scope of this spec:** how a simulator capture finds `source.projectRoot` (and so `source.gitCommit`).
**Out of scope:** Mac apps (`projectRoot(forBundleAt:)`, including Debug builds that run from `DerivedData.noindex`, where `derivedDataMarker` misses); the payload wording; the schema; which app the window shows (the highest pid on the device, as today); recording the commit the build was made from (`gitCommit` stays HEAD at capture time, v0.4 R33).

Read `CLAUDE.md`, `specs/v0.3.md` §2 (R17, rules 2 and 4), `specs/v0.4.md` R33, `Locant/Resolve/ModeInference.swift`, and `SimulatorApps` in `Locant/Capture/ContextCollector.swift`.

This spec overrides `specs/v0.3.md` R17 rule 2 on where a simulated app's `projectRoot` comes from.

## 0. Why it is wrong today

A simulated app runs from the device's container (`…/CoreSimulator/Devices/<UDID>/data/Containers/Bundle/Application/<UUID>/Oryne.app`), not from DerivedData, so rule 2 never applied as written. Since Sep 13 (6cb0aa0) `ModeEnvironment.projectRoot(ofSimulatedApp:derivedData:)` lists every `*-iphonesimulator` product in DerivedData with the simulated app's bundle id and takes the newest. The newest product is the last one built, not the one installed. With two sessions building two worktrees of the same app, whichever built last wins, whatever the simulator runs.

Reproduced on this Mac on Oct 19: the booted iPhone 17 Pro runs a build from `DerivedData.noindex/Oryne-phone-refocus` (WorkspacePath `oryne-product-opportunities-a913cb`); the newest product with `com.inspireocean.app` is `Oryne-watch-sdd` (Oct 19 03:56, WorkspacePath `oryne-apple-watch-app-177fc5`). Today's code names the Watch worktree.

## 1. Requirements

**R105. The running copy.** For a simulator capture, `SimulatorApps` already finds the simulated app's process (the highest pid on the device the window shows; on any device for Simulator.app) and reads its bundle id from the bundle path. It now keeps that bundle path too: the copy that is running, so the build on screen. It travels as `CaptureContext.simulatedBundlePath` and `ModeSignals.simulatedBundlePath`, never in the sidecar.

**R106. The build's own record.** The bundle's code binary is `<CFBundleExecutable>.debug.dylib` when the bundle has one, otherwise the executable. (Xcode's Debug builds put the code in that dylib and make the executable a stub. The stub is the same in every checkout: all seven Oryne products built on this Mac since Oct 17, from four different folders, carry LC_UUID `A229C089…`.) The linker writes a debug map into the binary's symbol table: one `N_OSO` entry per object file it linked, by absolute path, under `<build folder>/Build/Intermediates.noindex/`. Xcode's simulator builds keep it unless debug symbols are off or the build is stripped. The build folder is the one most of those entries name; entries elsewhere (the toolchain's own archives, for example) are skipped. `BuildProvenance` (new, pure) reads a thin or universal Mach-O with Foundation's `Data` only: no new framework, no `Process`, no `xcrun`. Any input it cannot read returns nil and never crashes.

**R107. Order.**
1. The running copy's debug map names a build folder whose `info.plist` has a `WorkspacePath` → `projectRoot` is that path's parent, as for products today.
2. Otherwise (no process found, no debug map, a build folder since deleted) → the DerivedData product search, **only when every product with that bundle id names the same project**. When they name different projects, there is no `projectRoot` and so no `gitCommit` and no Project line (option A, §3).

Mode and rule (`simulator`, `myApps`) are unchanged: only `projectRoot` changes.

**R108. `gitCommit`.** Unchanged: HEAD of `projectRoot` at capture time. With the right folder it is that folder's HEAD.

**Layout.** New `Locant/Resolve/BuildProvenance.swift`: `codeBinary(ofBundleAt:)` and `buildFolder(inMachO:)`. Changed: `ModeInference.swift` (`ModeEnvironment.simulatorProjectRoot` takes the bundle id and the running copy's path; `projectRoot(ofSimulatedApp:runningAt:derivedData:)`), `ContextCollector.swift` (`SimulatorApps.mostRecentlyLaunchedApp(onDevice:)` returns the id and the path; `simulatorInfo` and `collect` pass the path on), `Capture.swift` (`CaptureContext.simulatedBundlePath`), `ModeClassifier.swift`. New `LocantTests/BuildProvenanceTests.swift`. No schema change: `projectRoot` stays "never guessed", which R107 now honors.

## 2. Tests

Written first, and the R107 test is run red against today's code before the fix.

- `ModeInferenceTests`, **the regression:** a DerivedData with two products of `com.inspireocean.app`: `Oryne-redesign` (older, WorkspacePath `/Users/me/Code/oryne-redesign/Oryne.xcodeproj`) and `Oryne-watch` (newer, `/Users/me/Code/oryne-watch/…`). The running copy sits in a device container, with a stub executable that has no debug map and an `Oryne.debug.dylib` whose debug map names `Oryne-redesign`. Expected: `/Users/me/Code/oryne-redesign`. Today: `/Users/me/Code/oryne-watch`.
- `ModeInferenceTests`, fallback: the same products and a running copy without a debug map give nil. With only one product, or with both naming the same project, the answer is that project. With no running copy the same rules apply. The symlinked-DerivedData test still passes.
- `BuildProvenanceTests`: a synthetic thin arm64 Mach-O (header, `LC_SYMTAB`, `N_SO` and `N_OSO` stabs, string table) gives its build folder. The same slice inside a universal wrapper gives the same. A toolchain `.a(…o)` entry is skipped; with several folders, the one most entries name wins. No `LC_SYMTAB`, only non-stab symbols, truncated data, and random bytes each give nil. `codeBinary` picks `<exe>.debug.dylib` when present, otherwise the executable.
- `ContextCollectorTests`: the existing `simulatorInfo` tests, updated for the closure that returns the id and the path.
- The existing tests pass; `xcodebuild test` is green.
- By hand on this Mac, headless: the new code run on the booted iPhone 17 Pro's running copy gives `oryne-product-opportunities-a913cb`, while today's gives `oryne-apple-watch-app-177fc5`.

## 3. Decision (R107 step 2): A, approved Oct 19

When the running copy has no debug map and the products name different projects:

- **A (chosen): no Project line.** A wrong line is worse than none: since PR #48 it tells the agent to edit that folder. Without one, the agent works in its own checkout, which in parallel-worktree work is usually the one that built the app. It also matches the schema's "never guessed". In practice this branch is rare, because Xcode simulator builds carry a debug map.
- **B: newest product, as today.** Keeps the old behavior wherever the new signal is missing, and keeps the Oct 18 failure in that branch.

**Considered and not chosen.** Matching LC_UUIDs (or a content hash) of the running copy against each DerivedData product. The executable's UUID is the same in every build (the stub), so it would have to be the dylib's. And on Oct 19 none of the six Oryne installs on the booted simulators matched any current product: every product had been rebuilt after it was installed, without a reinstall. The debug map records the folder, not the bytes, so later rebuilds do not affect it. `simctl get_app_container` would give the installed copy, but it needs a subprocess, and the running process already gives the copy on screen.
