# Locant sounds

`landed` plays when a capture reaches the clipboard, `missed` when nothing did (`specs/v0.8.1.md` R60).
Both are rendered by `render.swift`, never edited by hand; the shipped pair is in `Locant/Feedback/Sounds/`.
Each also fires a trackpad tap in the same turn, so a capture marks itself in both channels.

- Chosen Sep 21, 2026 by ear, in the eighth listening round: **Tock** — one warm note on D4 (294 Hz, the root
  of the Shortcuts completion sound), a harmonic series whose upper harmonics are gone at once, two voices a
  cent and a half apart, a small glide as the tine settles, almost dry, over in 300 ms at −23 dBFS. `missed` is
  the same note a fourth lower (A3), damped, 3 dB quieter.
- The rounds before it failed for reasons worth keeping: a two-note rising figure read as a Windows device
  connecting; struck bars at G5 and then G4 read as sharp, because a strike begins with a contact; bare tones
  read as thin; warm chords with a room read as a ceremony. The lesson that stuck is Apple's: a cue is sized by
  how often it fires, and a capture fires many times an hour, so the sound is short and quiet and the tap
  carries half of it.
- Levels and what sits above 4 kHz follow a measurement of 45 macOS interface sounds (Sep 20, 2026); the
  scripts and results of that study are not in the repo. Every parameter is in `sets` and the constants under
  it in `render.swift`. Run these from the repo root:

```bash
swiftc -O design/sound/render.swift -o design/sound/render
design/sound/render candidates /tmp/locant-sounds   # every set as WAV, to listen
design/sound/render ship tock                        # into Locant/Feedback/Sounds as CAF
```

Measured when shipped (the script's own report):

```
tock landed  300 ms   peak  -23.0 dBFS   rms  -37.2 dBFS   200 Hz–4 kHz  99.8 %   tail at fade  -46.7 dB
tock missed  260 ms   peak  -26.0 dBFS   rms  -40.7 dBFS   200 Hz–4 kHz  92.0 %   tail at fade  -52.9 dB
```
