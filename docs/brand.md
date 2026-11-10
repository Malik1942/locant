# Locant brand

**Status:** decisions as of Sep 13, 2026. Owner: Malik Zhang.

The rule inside the app is "Borrow, don't brand" (PRD 6.1): system accent, SF Pro, system materials, an SF Symbol in
the menu bar. Outside the app, three things carry the identity: the name and its story, the app icon, and the site.
Everything else stays borrowed on purpose.

## Name

Locant, a term from chemical nomenclature: in 2-methylbutane, the 2 is the locant, the number that says exactly
which position the methyl group is attached to. Without it the name describes a family of molecules; with it, one.
Pronounced LOH-kant, two syllables. Tagline, always with the comma and the period:

> Point, don't describe.

Say "Locant" as a proper noun, never "the Locant app". Say "capture" for the act, "payload" for what lands on the
clipboard, "the ball" for the floating disc, "the overlay" for the frozen frame. Never "screenshot tool".

## Icon

`Locant/AppIcon.icon`, an Icon Composer package the system renders on macOS 26; `AppIcon.appiconset` holds the PNG
fallback for macOS 15. Regeneration tools and the current renders live in `design/icon/`.

- Two elements: a clear glass disc, the ball made solid, and two selection corners with a 10 percent gap.
- Disc at 62 percent of the canvas, 18 percent opacity, glass layer, soft center glow at 10 percent.
- Brackets: white at 85 percent, stroke 1.6 percent of the canvas, round caps, arms 17 percent long.
- Background: the product blue as a gradient, lit from the top. Light `#2A96FF` to `#0060DF`; dark `#1F86F0` to
  `#0A4FBF`. The same blue the overlay draws around an element, so icon, overlay, and site share one color.
  Chosen Sep 13, 2026 over a neutral gradient: the neutral version disappears in a Dock, and blue is the one color
  the product already owns. The cost, accepted: the icon no longer changes between light and dark beyond the glass.
- Rejected on the way here: a heavier hand-painted glass, a dot under the lens, an element with its hover outline,
  brackets overlapping the disc, blue brackets on a neutral background (read as incoherent), a flat blue background
  (less depth than the gradient). Every added element read as noise. The icon stays two elements.
- Menu bar: `hand.point.up.left` as a template image, not derived from the icon. SF Symbols are licensed for
  interfaces, not icons or logos, so the icon is original artwork.

## Site

`site/index.html`, one page, static, no build step. Assets in `site/assets/`.

**Treatment.** A quiet Apple-style product page. The demo carries the argument; the page stays out of its way.
The one bold move is typographic: the page is set in the system face, the same one the overlay label uses, so on a
Mac the site and the app share a voice. No custom font is loaded.

**Color.** Light: ground `#F5F5F7`, surface `#FFFFFF`, ink `#1D1D1F`, secondary `#6E6E73`, hairline `#D2D2D7`.
Dark: ground `#000000`, surface `#1C1C1E`, ink `#F5F5F7`, secondary `#A1A1A6`, hairline `#3A3A3C`. Accent `#0A84FF`
appears where the product uses it: the highlight stroke in the illustration, the hero stage behind the drawn
window, the download button, and the icon's background.

**Type.** `-apple-system` stack, SF Mono via `ui-monospace` for the payload. Display weight 600 with `-0.022em`
tracking. Scale: 60 / 40 / 21 / 17 / 15 / 13. Body 17 px at 1.5 line height in a 760 px column.

**Layout.** Single column. A centered hero, then everything left-aligned. Sections are separated by space, not
cards; a card is used only where items repeat as a set (the four actions). Numbers appear only where the content is
a real sequence: the three steps and the five rungs of the fallback ladder.

**Illustrations.** The hero stage is drawn in CSS from the app's tokens (`dim`, `highlight.stroke`, `label.bg`) and
holds the slot for the demo video. Everything below it is a real capture: the overlay's four states over Calculator,
the ball's four states, and the Settings window. Captures are staged over Apple's Tahoe Day wallpaper so they read
as a Mac, not as one person's desktop.

**Honesty.** Known limitations and the agent status table stay on the page. Statuses say "untested" until someone
tests them.

## Assets

| Asset | Path | Notes |
|---|---|---|
| Icon, light and dark, 1024 and 512 | `design/icon/renders/` | rendered by `ictool` from the shipped package |
| Site icon copies | `site/assets/icon-light.png`, `icon-dark.png` | 512, the page picks one per theme; the README shows the light one |
| Favicons | `site/assets/favicon-32.png`, `favicon-64.png`, `apple-touch-icon.png` | same package, rendered at size |
| Share image | `site/assets/og.jpg` | 1200×630, the page's `og:image` |
| The film, recorded | `site/assets/hero.mp4`, `hero-mobile.mp4`, `hero-poster.jpg`; `hero.gif` (the older loop) for the README | real takes: Point on an iPhone app in the Simulator and on a website, the paste in Cursor, and each change the agent made; captions are dark cards with a blue LOCANT label |
| Try-it demo | `site/assets/desktop.jpg`, `scene-calculator.png`, `scene-iphone.jpg`, `scene-web.jpg` | the Tahoe Day wallpaper and three real windows; the overlay, label, note field, and ball are drawn over them in CSS from the app's tokens |
| Glyphs | `site/assets/glyph-{snap,text,color,cut}.png`, `ball-hand.png` | the ring's four symbols and the hand on the ball, used as masks and tinted on the page |
| Overlay frame | `site/assets/overlay-note.jpg` | real capture of the note field over Calculator on the Tahoe Day wallpaper, 3:2, 1260×840; the README's Use section |
| Settings screenshots | `site/assets/settings-light.png`, `settings-dark.png` | window capture with shadow, General tab, 1184×1154; the README shows the light one |
| Measured outcome | `site/assets/measured-outcome.png` | the chart of the Locant-against-screenshot runs; not shown anywhere since the launch rework of Oct 15, 2026 |

## Not yet decided

- Domain. The page is hosted as a static folder; GitHub Pages from `site/` or Vercel both work with no build.
- A dmg background image. The dmg currently opens with the app and an Applications alias on a plain window.
- Whether the overlay's element highlight becomes four corner brackets so product and icon share one symbol.
  Live with the icon for a week first.
