# Locant: install an update from inside the app

**Status:** Spec written Nov 19, 2026, at Malik's request: he no longer wants to open the browser, download the dmg, and drag the new copy over the old one for every release. Decided the same day:
- Locant installs the update itself, with its own code. Sparkle was considered and turned down. It would be the first third-party dependency, it brings its own XPC services that `release.sh` would have to sign, and it needs an EdDSA key to guard and an appcast to host.
- The user installs with one click, from the existing update alert. Nothing downloads or installs on its own.

Numbered from R175 (`specs/frozen-screen.md` ends at R174).

**Scope of this spec:**
- the alert's new button and when it offers it;
- the download, the checks on what was downloaded, and the swap and relaunch;
- what happens when something fails;
- a Debug switch to test it end to end;
- the words that change elsewhere.

**Out of scope:**
- installing without a click;
- release notes in the alert;
- delta updates;
- installing where Locant cannot write without an administrator password (the browser download stays the answer there);
- a Locant installed by Homebrew updating Homebrew's record of the version (`auto_updates true` tells Homebrew to leave it alone, R184).

Read `CLAUDE.md`, `specs/v0.6.md` R45–R49 (the daily check and its alert), `Locant/Store/UpdateCheck.swift`, and in `Locant/App/AppState.swift` `checkForUpdates`, `offerUpdate`, and `inform`.

This spec overrides `specs/v0.6.md` R48 (the alert) and R49 (the privacy sentences). R45–R47 are unchanged: the check, its timing, its one request, and the Settings row stay as they are.

The first version with this code is the first one that can be installed this way. Every copy older than it, 1.3.1 included, still updates through the browser once.

## 1. Requirements

**R175. The alert.** The R48 alert, with the same rule that it never shows over the overlay. Title "Locant 1.4.0 is available".
- **Where Locant can update itself (R176):**
  - Text: "You have 1.3.1. Locant downloads the new version, checks that it is signed by the same developer, and reopens. Your permissions carry over."
  - Buttons: **Install and Relaunch** (the default, Return), **Later**, **Skip This Version**.
- **Where it cannot:**
  - Text: R48's text, then a second paragraph with the reason from R176.
  - Buttons: R48's **Download**, **Later**, **Skip This Version**, which behave as R48 says.

Later and Skip This Version behave as R48 says.

**R176. Where Locant can update itself.** Decided before the alert shows, from the running copy's bundle URL (`Bundle.main.bundleURL`). The decision is pure: `InstallPlace.check(bundlePath:volumeIsReadOnly:parentIsWritable:)` returns `.ok` or a reason, checked in this order. Each reason has its own sentence in the alert:
- **`.translocated`:** the path contains `/AppTranslocation/`.
  "Locant is running from a download or a disk image. Move it to Applications, open it from there, and it can update itself next time."
- **`.readOnlyVolume`:** the volume holding the bundle is read-only (`URLResourceValues.volumeIsReadOnly`).
  The same sentence as `.translocated`.
- **`.notWritable`:** the folder holding the bundle is not writable by the user (`FileManager.isWritableFile(atPath:)` on the parent).
  "Locant can't write to the folder it is in, <folder name>."

**R177. Download.** Clicking Install and Relaunch downloads the release asset named exactly `Locant-<version>.dmg`, the one the Homebrew cask uses (`scripts/publish.sh`).
- The asset is picked by a pure `GitHubRelease.installerAsset(version:)`. A release without one goes to R181 as "The release has no installer."
- The request is like R45's: an ephemeral session with no cookies and no cache, and `User-Agent: Locant/<version>`. Its timeout is 60 s without data. A download over 200 MB stops as a failure.
- The file goes to a new folder in `FileManager.default.temporaryDirectory` named `Locant-update-<UUID>`.
- While it downloads, a small panel shows "Downloading Locant 1.4.0…", a progress bar (determinate when the reply has a length), and **Cancel**.
  - Cancel stops the download and removes the folder. It shows nothing else, and the alert does not come back until the next daily check.
  - The panel stays up through R178 and R179, which take a few seconds, with its text changed to "Checking Locant 1.4.0…".
- While an install is under way (from the click until Locant quits or R181 shows), the daily check and Check Now offer nothing, so no second Install button appears that would do nothing.

**R178. Unpack.**
Every tool here runs with its standard input at `/dev/null`, so a dmg that asks a question fails instead of waiting forever.
1. Locant runs `/usr/bin/hdiutil attach -nobrowse -readonly -noautoopen -mountrandom <download folder> -plist <dmg>` and reads the mount point from the plist. No Finder window opens.
2. The dmg must hold `Locant.app` at its root, a folder and not a symbolic link, or R181: "The download doesn't hold Locant."
3. `/usr/bin/ditto` copies it into the folder that holds the running copy, as `.Locant-<version>.incoming.app`. A name that starts with a dot is hidden in Finder. The copy sits on the same volume as the running copy, so R180's swap is a rename.
4. `hdiutil detach -force` unmounts the dmg whatever happened before. The dmg is deleted.

**R179. Checks.** All of these must pass on the incoming copy, or R181 follows with "The download isn't signed by Locant's developer." (the first two) or "The download isn't the version that was offered." (the third):
- **Same signer, notarized.** The running copy's designated requirement comes from `SecCodeCopySelf` and `SecCodeCopyDesignatedRequirement`, wrapped in parentheses with ` and notarized` appended, `(<designated>) and notarized` (`SecRequirementCreateWithString`; the designated requirement holds an `or`). The incoming copy is checked against it with `SecStaticCodeCheckValidity` and the flags `kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode`.
  - For a release copy, the designated requirement names the Developer ID anchor, the team (MVAUZXPK9M), and the bundle identifier (`com.malikzhang.deixis`). macOS keys the Accessibility and Screen Recording permissions to the same requirement, so passing this check is what makes the permissions carry over.
- **Same identifier.** The incoming `Info.plist`'s `CFBundleIdentifier` equals the running one's.
- **The offered version.** The incoming `CFBundleShortVersionString` parses (`AppVersion`), equals the release's version, and is newer than the running version. This stops a downgrade and a mismatched asset.

The two plist comparisons are pure: `UpdateInstaller.checkBundle(incoming:running:offered:current:)`. The signature check is not.

Locant runs all three checks a second time right before R180 starts the script, after the wait for idle. The incoming copy sits in a folder the user can write to during that wait, so the copy that gets swapped in is the one checked last. A copy that fails then goes to R181 the same way.

**R180. Swap and relaunch.** When the checks pass, Locant waits until `phase == .idle`. An install never cuts a session short; a session started during R177–R179 finishes first. Then:
1. Locant runs R179's checks again, writes R181's pending file, and starts the script with `Process`: `/bin/sh -c <UpdateInstaller.script> sh <pid> <running path> <incoming path> <old version> <download folder> /usr/bin/open`.
   - The script text is a constant, `UpdateInstaller.script`, passed inline. No script file is written, so nothing can replace it between writing and running, and it never deletes its own file.
   - It takes everything as arguments, never interpolated into the text. The arguments after `-c <script>` come from one pure function, `UpdateInstaller.swapArguments(pid:running:incoming:oldVersion:work:opener:)`, which `startSwap` and the tests both use, so the order can't drift.
   - The last argument is the command that opens the result, so the tests can pass `/usr/bin/true`.
2. Locant quits (`NSApp.terminate`).
3. The script:
   1. Waits for the pid to exit, checking `kill -0` every 100 ms for up to 20 s. If the pid is still running at 20 s, it removes the incoming copy and the download folder and stops.
   2. If the incoming copy is missing, it goes to step 6.
   3. Renames the running copy to `.Locant-<old version>.outgoing.app` in the same folder, removing a leftover of that name first. If that fails, it removes the incoming copy and goes to step 6.
   4. Renames the incoming copy to the running copy's path. If that fails, it renames the outgoing copy back and removes the incoming copy.
   5. Moves the outgoing copy, if it is still there, to `~/.Trash/Locant <old version>.app`, adding ` <date and time>` to the name if one exists. This is best effort: if the move fails, the outgoing copy stays and R182 removes it.
   6. Runs `/usr/bin/open` on the running path, so whichever copy ended up there opens.
   7. Deletes the download folder.
- Every move on the way to the new copy is a rename inside the folder that holds Locant. A rename needs only write access to that folder (R176), never to the bundle itself, and it can't leave half a copy behind. Moving a folder to another parent needs write access to the folder itself, and across volumes it is a copy and a delete, so the move to the Trash comes after the new copy is in place.
- `Locant --mcp` processes that agents have running keep running from the old files until their agent restarts them. They are not waited for and not stopped.
- Files that URLSession downloads and that `hdiutil` and `ditto` copy carry no quarantine flag, so the new copy opens without the "downloaded from the internet" dialog. It is notarized either way.

**R181. Failure.** Any failure in R177–R179, and a `Process` that won't start in R180, shows:
- Title "Locant couldn't install 1.4.0".
- Text: the reason (the sentences above, "The download failed." for a network error or a non-2xx status, "There isn't enough space to unpack it." for `ENOSPC`, and "Something went wrong unpacking it." for anything else).
- Buttons: **Download in Browser** (opens the dmg as R48 did) and **Cancel**.

Before the alert, Locant removes the download folder and any incoming copy, and detaches a dmg it attached. The running copy is never touched before R180, so a failure leaves Locant as it was.

**A swap that didn't happen.** Once Locant has quit, it can't show an alert, and the script reopens the old copy without a word. So:
- Right before it starts the script, Locant writes `Locant-pending-update.json` in `FileManager.default.temporaryDirectory`, holding the offered version and the dmg's browser URL (the one R48's Download opens).
- At `AppState.start()`, Locant reads that file and deletes it. The decision is pure: `UpdateInstaller.pendingOutcome(pending:current:)`.
  - When the running version is the pending one or newer, the update went in, and nothing shows.
  - When the running version is older, the swap didn't happen: the script couldn't rename a copy, or Locant was still running at 20 s. Locant shows, once the session is idle:
    - Title "Locant couldn't install 1.4.0".
    - Text "Locant couldn't replace the copy in <folder name>, so you still have 1.3.1."
    - Buttons: **Download in Browser** (opens the URL from the file) and **Cancel**.
  - A file that doesn't decode is deleted and ignored.

**R182. Leftovers.** At `AppState.start()`, Locant removes:
- any `.Locant-*.incoming.app` and `.Locant-*.outgoing.app` in the folder that holds it;
- any `Locant-update-*` folder in the temporary directory, after `hdiutil detach -force` on any disk image still mounted inside it (`hdiutil info -plist`, mount points under that folder).

These are what a crash, a quit during unpacking, or a stopped script leaves behind. Each removal is best effort; one that fails is left for the next start.

**R183. A switch to test it.** In Debug builds only, the launch argument `-updateFeed <path>` makes the update check read a release JSON from that file instead of asking GitHub, with the same decoding (R45). Its asset URL may point at a server on this Mac (`http://127.0.0.1:<port>/…`), which R177 downloads like any other. Release builds compile none of it, except a build that sets the Swift flag `UPDATE_FEED_TEST` (`OTHER_SWIFT_FLAGS`), which is only for step 8 of the end-to-end run below and is never committed or shipped.

**R184. Words elsewhere.**
- **README Install:**
  "The one request Locant makes is a daily check for a newer release on GitHub. When you click Install and Relaunch, it downloads that release from GitHub. Turn the check off in Settings › General."
- **README Git facts:**
  "It never talks to the network except the release check and the update you install, and, for a local page's source lines, your own dev server…"
- **Site, "Nothing leaves your Mac":**
  "No telemetry, no accounts. The one request that leaves it is a daily check for a newer version, and you can turn it off. An update downloads only when you click Install."
- **CHANGELOG:**
  - The intro sentence becomes "Every release is a signed, notarized `Locant.dmg` on GitHub Releases. From 1.4.0 on, Locant installs it for you from the update alert; your permissions carry over."
  - An Unreleased section gains one bullet.
- **`docs/CLAUDE.md`:** the network line becomes "No network calls except the release check (specs/v0.6.md R45), the update the user clicks Install and Relaunch for (specs/in-app-update.md R177), and, for a local web page's source lines, that page's source maps from the dev server on this Mac (specs/web-source.md R152)."
- **Homebrew cask:** `packaging/homebrew/locant.rb` gains `auto_updates true`, so `brew upgrade` leaves a self-updated copy alone. The tap's copy follows at the next release (`scripts/cask.sh`).

## 2. Files

- **New:**
  - `Locant/Store/UpdateInstaller.swift`: `InstallPlace`, `checkBundle`, `script()`, the download, the unpack, the signature check, and the swap.
  - `Locant/App/UpdatePanel.swift`: the progress panel of R177 (a window, so a class of its own).
  - `LocantTests/UpdateInstallerTests.swift`.
- **Changed:**
  - `UpdateCheck.swift`: `installerAsset(version:)`, and R183's Debug feed.
  - `AppState.swift`: R175's alert; the panel, failure, and idle wait of R177–R181; R182 at start.
  - `README.md`, `site/index.html`, `CHANGELOG.md`, `docs/CLAUDE.md`, `packaging/homebrew/locant.rb` (R184).

## 3. Tests

**`UpdateInstallerTests`:**
- `InstallPlace.check`:
  - `/Applications/Locant.app` on a writable volume is `.ok`.
  - A path under `/private/var/folders/…/AppTranslocation/…` is `.translocated`.
  - A read-only volume is `.readOnlyVolume`.
  - A writable volume whose parent is not writable is `.notWritable`.
- `installerAsset(version: "1.4.0")`:
  - It picks `Locant-1.4.0.dmg` from a release that also has `Locant.dmg`.
  - It is nil when only `Locant.dmg` is there.
- `checkBundle`:
  - It passes the same identifier with the offered version, newer than the running one.
  - It fails a different identifier, a different version from the offered one, an equal version, and an older version.
- `script`, run as `/bin/sh -c` with `swapArguments` against folders in a temporary directory (a fake running copy, a fake incoming copy, and the pid of a `sleep 0.3`):
  - It names no path: everything comes in as arguments.
  - It waits for the pid, swaps the copies, and leaves the old copy in the Trash under the name it was given, with no `.outgoing.app` left.
  - With an incoming path that does not exist, it leaves the running copy in place.
  - When the incoming copy can't be renamed into place, the old copy is back at the running path.
  - When the Trash can't take the outgoing copy, the new copy is still in place and opened.
- `swapArguments` puts the values in the order the script reads them.
- `pendingOutcome`: an older running version is a failure with the pending version and URL; an equal or newer one is installed.
- `unpack` rejects a dmg whose `Locant.app` is a symbolic link.

The existing tests pass.

**End to end, on the Mac, publishing nothing:**
1. **The new copy:** set `MARKETING_VERSION` to 9.9.9 locally (not committed) and run `scripts/release.sh`. That gives a notarized `build/release/Locant-9.9.9.dmg`.
2. **The old copy:** at the branch's real version, build the Debug configuration with `release.sh`'s signing settings (the Developer ID identity, team, hardened runtime). Its designated requirement is then the release one. Put it in a writable test folder such as `~/Applications/LocantUpdateTest/`.
3. **A feed:** serve `build/release` on `http://127.0.0.1:8765` (`python3 -m http.server`), and write a release JSON with `tag_name` `v9.9.9` and an asset `Locant-9.9.9.dmg` at that address.
4. **Install:**
   - Open the old copy with `-updateFeed <json>`, choose Check Now, then Install and Relaunch.
   - The panel shows. Locant quits and reopens as 9.9.9 from the same path, and Settings shows Version 9.9.9.
   - The old copy is in the Trash as `Locant <version>.app`.
   - Point captures without asking for permission again.
5. **Failure:** in the JSON, point the asset at an unsigned or ad-hoc copy packed as a dmg.
   - The R181 alert shows "isn't signed by Locant's developer".
   - The running copy is untouched, and no `.incoming.app` is left.
6. **Translocated:** opened from the dmg itself (not copied out), the alert shows the R176 reason and Download.
7. **Failure after quitting:** make the test folder's old copy impossible to rename (for example `chmod a-w` on the test folder after the checks pass, by hand), install, and check that the old copy reopens and shows "Locant couldn't replace the copy in…". Restore the folder's mode.
8. **Notarized to notarized, through LaunchServices (the gate before release):** steps 1–4 test a Debug old copy started from a shell, which App Management likely doesn't protect. Build 9.9.8 and 9.9.9 both with `release.sh`'s settings plus `UPDATE_FEED_TEST`, notarized. Install 9.9.8 from its dmg into `/Applications`, open it once with `open` so Gatekeeper assesses it, then update to 9.9.9 through the feed. It reopens as 9.9.9 with its permissions. This Mac has Gatekeeper turned off, which may hide a failure, so a second Mac with it on is better.
9. **Cleanup:** remove the test folder, the test copies, and the 9.9.8 and 9.9.9 dmgs, and restore `MARKETING_VERSION`.
