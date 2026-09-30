# Contributing

Locant is one person's tool, built one spec at a time. Contributions are welcome where they fit that.

## The fastest way to help

Run it on a Mac that is not the author's and say what happened. The [tester form](https://github.com/Malik1942/locant/issues/new?template=tester.yml) takes two minutes; [`docs/rc-checklist.md`](docs/rc-checklist.md) lists what to try. A Mac on macOS 15, an Intel Mac, a non-English system, or a second display is worth more than any patch right now.

## Issues

- **Something broke**: use the bug form. Paste the block from Settings › General › Copy Diagnostics; it answers version, macOS, chip, displays, and permissions at once. Say which app you pointed at and what Locant gave you.
- **An app it reads badly**: the app form. The payload, with anything private removed, is the most useful thing you can attach.
- **An idea**: open a plain issue. Read [`docs/PRD.md`](docs/PRD.md) §4 first; the non-goals are firm (no cloud, no annotation editor, no window-level capture, no autonomous agent).

## Build

Xcode 26 on macOS 15 or later. No third-party packages, and none will be added.

```bash
git clone https://github.com/Malik1942/locant.git
cd locant
xcodebuild -project Locant.xcodeproj -scheme Locant -destination 'platform=macOS' test CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual
```

That line is what CI runs. Ad hoc signing changes on every build, so macOS asks for Accessibility and Screen Recording again after each rebuild; any real identity, including the free Apple Development one, avoids that (set your team in Signing & Capabilities).

## Pull requests

- A PR follows a spec in [`specs/`](specs/) or fixes a filed bug. For anything larger than a bug fix, open an issue first; the answer may be a spec, and the spec is where the design is argued.
- Read [`docs/CLAUDE.md`](docs/CLAUDE.md): it is the house style, for people as much as for agents. Swift 6 strict concurrency, value types for data, typed errors, pure functions for anything transformable, and those get tests.
- Small commits, one intent each, message in the form `area: what changed`. Green build before every commit.
- Do not reformat files you did not need to touch. Do not touch the README unless the change is user-facing.
- The JSON sidecar and [`schema/capture.schema.json`](schema/capture.schema.json) are the only contract with the outside. A schema change is a spec, not a PR.

## Releases

Releases are built on the author's Mac by `scripts/release.sh` (Developer ID, hardened runtime, notarized, stapled) and published by `scripts/publish.sh`. CI never signs or publishes.
