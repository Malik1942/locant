# Locant sounds

`landed` plays when a capture reaches the clipboard, `missed` when nothing did (`specs/v0.8.1.md` R60).
Both are rendered by `render.swift`, never edited by hand; the shipped pair is in `Locant/Feedback/Sounds/`.
Each also fires a trackpad tap in the same turn, so a capture marks itself in both channels.

- Chosen Sep 20, 2026 by ear, in the fourth listening round: **Room** — a tuned marimba bar with a little
  air under it. The rounds before it failed for reasons worth keeping: a two-note rising figure read as a
  Windows device connecting, and a dry wooden strike at G5 read as sharp and cheap.
- The figure: one strike at G4 (392 Hz), the pitch macOS tunes its own screenshot sound to; `missed` is the
  same bar struck a fifth lower (C4) and damped, so it stops sooner as well as sounding lower.
- The numbers come from measuring 45 macOS interface sounds (Sep 20, 2026): confirmations run 420 to 755 ms,
  stand about 64 dB below peak when their fade begins, peak between −15.4 and −7.4 dBFS, and hold essentially
  nothing above 4 kHz. Every parameter is in `sets` and the constants under it in `render.swift`. Run these
  from the repo root:

```bash
swiftc -O design/sound/render.swift -o design/sound/render
design/sound/render candidates /tmp/locant-sounds   # every set as WAV, to listen
design/sound/render ship room                       # into Locant/Feedback/Sounds as CAF
```

Measured when shipped (the script's own report):

```
room landed  700 ms   peak  -15.0 dBFS   rms  -32.3 dBFS   200 Hz–4 kHz  99.9 %   tail at fade  -75.8 dB
room missed  500 ms   peak  -18.0 dBFS   rms  -35.9 dBFS   200 Hz–4 kHz  98.8 %   tail at fade  -74.7 dB
```
