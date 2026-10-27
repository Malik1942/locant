# Locant: a Mac app built in DerivedData gets its Project line however it was launched

**Status:** Spec written Oct 22, 2026, to check a gap left out of `specs/simulator-project-root.md` (PR #66): Mac Debug apps that run from `DerivedData.noindex`. On this Mac `~/Library/Developer/Xcode/DerivedData` is a symlink to `DerivedData.noindex`. Measured the same day with a throwaway Mac app built by `xcodebuild` into the default DerivedData. The build system writes the symlink's own path (`…/Xcode/DerivedData/<Project-hash>/Build/Products/Debug/<App>.app`, the same in Locant's own Debug products' debug maps), and what `NSRunningApplication.bundleURL` reports depends on how the app was launched:

| Launch | `bundleURL` | Today's result |
|---|---|---|
| Xcode Run, debugger on (the default scheme) | `…/Xcode/DerivedData/…` | fix, builtHere, the project folder |
| A direct exec of the executable | `…/Xcode/DerivedData/…` | fix, builtHere, the project folder |
| Xcode Run, debugger off | `…/Xcode/DerivedData.noindex/…` | reference, no Project line |
| `open` (Finder, the Dock, Spotlight, an agent's `open`), even of the symlink's path | `…/Xcode/DerivedData.noindex/…` | reference, no Project line |

The last two go through LaunchServices, which reports the resolved path. That path misses `derivedDataMarker`, and no folder above it holds a project, so the real `ModeInference.infer` returns reference with no `projectRoot`. An app signed with the user's Apple Development team gets fix through `signedByUser`, still with no Project line. The same happens to every build made with `-derivedDataPath` outside the project, which is how agent sessions on this Mac build (`DerivedData.noindex/Oryne-phone-refocus`, a scratchpad folder): those folders also have an `info.plist` with `WorkspacePath` (checked for four of them). Numbered from R116 (`specs/capture-recovery.md` holds R109–R115).
**Scope of this spec:** how `ModeInference.projectRoot(forBundleAt:environment:)` finds the build folder of a Mac app.
**Out of scope:** simulator captures (`specs/simulator-project-root.md`, R105–R108); a Debug app copied out of its build folder (only its debug map would still know the folder: `BuildProvenance` from PR #66 could do it later); two checkouts building into one shared `-derivedDataPath` while an older build still runs (the folder names the last build); the payload wording; the schema.

Read `CLAUDE.md`, `specs/v0.3.md` §4 (R17, rule 4), and `Locant/Resolve/ModeInference.swift`.

This spec extends `specs/v0.3.md` R17 rule 4: "under DerivedData" also means a path that resolves into it, or any Xcode build folder.

## 1. Requirements

**R116. The build folder.** A bundle's build folder is, in order:
1. the folder right after `/Library/Developer/Xcode/DerivedData/` in its path, as today;
2. otherwise, the folder before the last `/Build/Products/` in its path. Xcode puts every product there, inside the default DerivedData, its symlink's target (`DerivedData.noindex`), or any `-derivedDataPath`.

When that folder's `info.plist` has a `WorkspacePath`, `projectRoot` is that path's parent, as today. Nothing is read from the binary and nothing new is read from disk: the same `derivedDataWorkspacePath` lookup, on the folder the path names.

**R117. No `WorkspacePath`, still the walk.** When the build folder has no readable `WorkspacePath`, the ancestor walk runs as for any other bundle (today a DerivedData path stops there with no root). A `-derivedDataPath` inside the project then finds the project; one outside finds nothing, so no Project line, as today.

Mode and rules are unchanged: a root found this way gives `builtHere` (or rides with `myApps`) as today.

**R118. Words elsewhere.** CHANGELOG gains one bullet under Unreleased (PR #66 adds that section too; whichever merges second keeps both bullets).

## 2. Files

- Changed: `Locant/Resolve/ModeInference.swift` (`projectRoot(forBundleAt:environment:)`), `LocantTests/ModeInferenceTests.swift`, `CHANGELOG.md`.

## 3. Tests

- `ModeInferenceTests`:
  - A bundle in `…/Library/Developer/Xcode/DerivedData.noindex/Locant-abc123/Build/Products/Debug/Locant.app` whose folder's `WorkspacePath` is `/Users/me/Code/Locant/Locant.xcodeproj` → fix, `builtHere`, `/Users/me/Code/Locant`. Fails today.
  - The same for a `-derivedDataPath` build in `/private/tmp/scratch/dd/Build/Products/Debug/Locant.app` → `/Users/me/Code/Locant`. Fails today.
  - A `-derivedDataPath` inside the project, `/Users/me/Code/Tool/build/dd/Build/Products/Debug/Tool.app`, with no `WorkspacePath` and `Tool.xcodeproj` in `/Users/me/Code/Tool` → `/Users/me/Code/Tool` (R117).
  - The existing DerivedData test keeps passing, including its case without a `WorkspacePath` (reference).
- The existing tests pass.
- On this Mac: build a throwaway Mac app into the default DerivedData, launch it with `open`, and pass its `NSRunningApplication.bundleURL` to `ModeInference.infer` with the live environment → fix, `builtHere`, the app's project folder. Then delete the build.
