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

**R178. Unpack.**
1. Locant runs `/usr/bin/hdiutil attach -nobrowse -readonly -noautoopen -mountrandom <download folder> -plist <dmg>` and reads the mount point from the plist. No Finder window opens.
2. The dmg must hold `Locant.app` at its root, or R181: "The download doesn't hold Locant."
3. `/usr/bin/ditto` copies it into the folder that holds the running copy, as `.Locant-<version>.incoming.app`. A name that starts with a dot is hidden in Finder. The copy sits on the same volume as the running copy, so R180's swap is a rename.
4. `hdiutil detach -force` unmounts the dmg whatever happened before. The dmg is deleted.

**R179. Checks.** All of these must pass on the incoming copy, or R181 follows with "The download isn't signed by Locant's developer." (the first two) or "The download isn't the version that was offered." (the third):
- **Same signer, notarized.** The running copy's designated requirement comes from `SecCodeCopySelf` and `SecCodeCopyDesignatedRequirement`, with ` and notarized` appended (`SecRequirementCreateWithString`). The incoming copy is checked against it with `SecStaticCodeCheckValidity` and the flags `kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode`.
  - For a release copy, the designated requirement names the Developer ID anchor, the team (MVAUZXPK9M), and the bundle identifier (`com.malikzhang.deixis`). macOS keys the Accessibility and Screen Recording permissions to the same requirement, so passing this check is what makes the permissions carry over.
- **Same identifier.** The incoming `Info.plist`'s `CFBundleIdentifier` equals the running one's.
- **The offered version.** The incoming `CFBundleShortVersionString` parses (`AppVersion`), equals the release's version, and is newer than the running version. This stops a downgrade and a mismatched asset.

The two plist comparisons are pure: `UpdateInstaller.checkBundle(incoming:running:offered:)`. The signature check is not.

**R180. Swap and relaunch.** When the checks pass, Locant waits until `phase == .idle`. An install never cuts a session short; a session started during R177–R179 finishes first. Then:
1. Locant writes a shell script into the download folder and starts it with `Process` (`/bin/sh <script> <pid> <running path> <incoming path> <old version>`). The script text is generated by a pure `UpdateInstaller.script()` and takes everything as arguments, never interpolated into the text.
2. Locant quits (`NSApp.terminate`).
3. The script:
   1. Waits for the pid to exit, checking `kill -0` every 100 ms for up to 20 s. If the pid is still running at 20 s, it removes the incoming copy and stops.
   2. Moves the running copy to `~/.Trash/Locant <old version>.app`, adding ` <date and time>` to the name if one exists.
   3. Renames the incoming copy to the running copy's path. If that fails, it moves the old copy back.
   4. Runs `/usr/bin/open` on the path, so whichever copy ended up there opens.
   5. Deletes the download folder, its own folder included.
- `Locant --mcp` processes that agents have running keep running from the old files until their agent restarts them. They are not waited for and not stopped.
- Files that URLSession downloads and that `hdiutil` and `ditto` copy carry no quarantine flag, so the new copy opens without the "downloaded from the internet" dialog. It is notarized either way.

**R181. Failure.** Any failure in R177–R179, and a `Process` that won't start in R180, shows:
- Title "Locant couldn't install 1.4.0".
- Text: the reason (the sentences above, "The download failed." for a network error or a non-2xx status, "There isn't enough space to unpack it." for `ENOSPC`, and "Something went wrong unpacking it." for anything else).
- Buttons: **Download in Browser** (opens the dmg as R48 did) and **Cancel**.

Before the alert, Locant removes the download folder and any incoming copy, and detaches a dmg it attached. The running copy is never touched before R180, so a failure leaves Locant as it was.

**R182. Leftovers.** At `AppState.start()`, Locant removes:
- any `.Locant-*.incoming.app` in the folder that holds it;
- any `Locant-update-*` folder in the temporary directory.

These are what a crash or a stopped script leaves behind.

**R183. A switch to test it.** In Debug builds only, the launch argument `-updateFeed <path>` makes the update check read a release JSON from that file instead of asking GitHub, with the same decoding (R45). Its asset URL may be a `file://` URL, which R177 downloads like any other. Release builds compile none of it.

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
- **Homebrew cask:** `packaging/homebrew/locant.rb` gains `auto_updates true`, so `brew upgrade` leaves a self-updated copy alone. The tap's copy follows at the next release (`scripts/cask.sh`).

## 2. Files

- **New:**
  - `Locant/Store/UpdateInstaller.swift`: `InstallPlace`, `checkBundle`, `script()`, the download, the unpack, the signature check, and the swap.
  - `LocantTests/UpdateInstallerTests.swift`.
- **Changed:**
  - `UpdateCheck.swift`: `installerAsset(version:)`, and R183's Debug feed.
  - `AppState.swift`: R175's alert; the panel, failure, and idle wait of R177–R181; R182 at start.
  - `README.md`, `site/index.html`, `CHANGELOG.md`, `packaging/homebrew/locant.rb` (R184).

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
- `script()`:
  - It has no argument values in its text.
  - Run with `/bin/sh` against folders in a temporary directory (a fake running copy, a fake incoming copy, and the pid of a `sleep 0.3`), it swaps them and leaves the old copy under the trash name it was given.
  - Run with an incoming path that does not exist, it leaves the running copy in place.

The existing tests pass.

**End to end, on the Mac, publishing nothing:**
1. **The new copy:** set `MARKETING_VERSION` to 9.9.9 locally (not committed) and run `scripts/release.sh`. That gives a notarized `build/release/Locant-9.9.9.dmg`.
2. **The old copy:** at the branch's real version, build the Debug configuration with `release.sh`'s signing settings (the Developer ID identity, team, hardened runtime). Its designated requirement is then the release one. Put it in a writable test folder such as `~/Applications/LocantUpdateTest/`.
3. **A feed:** write a release JSON with `tag_name` `v9.9.9` and an asset `Locant-9.9.9.dmg` whose URL is the `file://` path of step 1.
4. **Install:**
   - Open the old copy with `-updateFeed <json>`, choose Check Now, then Install and Relaunch.
   - The panel shows. Locant quits and reopens as 9.9.9 from the same path, and Settings shows Version 9.9.9.
   - The old copy is in the Trash as `Locant <version>.app`.
   - Point captures without asking for permission again.
5. **Failure:** in the JSON, point the asset at an unsigned or ad-hoc copy packed as a dmg.
   - The R181 alert shows "isn't signed by Locant's developer".
   - The running copy is untouched, and no `.incoming.app` is left.
6. **Translocated:** opened from the dmg itself (not copied out), the alert shows the R176 reason and Download.
7. **Cleanup:** remove the test folder and the 9.9.9 dmg, and restore `MARKETING_VERSION`.
