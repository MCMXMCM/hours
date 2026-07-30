# Third-party material and acknowledgements

This file distinguishes material distributed with Hours from sources consulted
only during development. Acknowledging a reference does not mean its code,
assets, or text are incorporated into the app, and Hours does not bundle a
license solely because a project or edition was consulted.

## Material distributed with Hours

- **Divinum Officium** — MIT, pinned at
  `79a596eeb68268c35334f25122af7ffc376934d5`. Hours distributes calendar and
  office-text data from this source, including English translations. Its MIT
  grant is bundled at
  `HoursApp/Resources/Divinum-Officium-LICENSE.txt`.
- **Exsurge (bbloomf maintained fork)** — MIT, pinned at
  `0c39f61df0e7c843f467250976338cac62f94e62`. Hours distributes native Swift
  vector geometry converted from its canonical Gregorian SVG glyph outlines.
  The app does not include Exsurge JavaScript, a web view, or an Exsurge runtime
  font. The required MIT notice is bundled at
  `HoursApp/Resources/Exsurge-LICENSE.txt`.
- **EB Garamond** — SIL Open Font License 1.1. Hours distributes the variable
  font and its license under `HoursApp/Resources`.
- **Bureå Funeral Chapel Organ, Gedackt 8′ stop** — Creative Commons
  Attribution-ShareAlike 2.5. Hours distributes an SF2 adaptation of Lars
  Palo's chromatically sampled stereo pipe-organ stop. Its attribution,
  adaptation details, checksum, source, and license link are bundled at
  `HoursApp/Resources/ChurchOrgan-LICENSE.txt`.
- **Chant transcriptions** — Each score records its own collection, source URL,
  source identifier, license, and checksum. GregoBase transcriptions are CC0.
  The bundled development corpus contains 1,547 Nocturnale Romanum
  transcriptions under GPL-3.0-only. Their exact editable GABC, provenance
  manifest, modification notice, and license are included under
  `Content/Nocturnale-Romanum`, `NOTICE.md`, and `LICENSE`. The installed
  scored corpus is development-only and must not be submitted as a release
  corpus.

The Latin prayers in the development fixture are public-domain liturgical
text. Its editorial GABC exists only to exercise the implementation and is
labeled CC0.

## Development references and acknowledgements

The following helped validate, compare, or generate development artifacts.
Except where separately identified above as distributed material, they are not
runtime dependencies and their code or publications are not bundled in Hours:

- **Breviarium Gregorianum** — Used as an assembly/order concordance and chant
  source-index reference. Office texts and translations are attributed to their
  underlying Divinum Officium source; chant payloads retain their own source
  licenses.
- **Exsurge (original)** — MIT, pinned at
  `f828578b2fc4f501697414080d4241a322ae3cc0`. A copy is retained in
  `Tools/ReferenceRenderer` for offline visual regression, not in the
  production rendering path.
- **jgabc / Chant Tools** — Unlicense, pinned at
  `dff87490026adf21a97cac019a83b8611f0c2e71`. Used as a development generator
  and reference for reviewed psalmody, lesson, and chapter tones; its
  JavaScript is not distributed in the app.
- **Printed chant and office editions** — The 1960 *Liber antiphonarius*, the
  1961 *Liber Usualis*, historical Roman breviaries and martyrologies, and
  modern printed editions identified in `Docs/MISSING_OFFICE_SOURCES.md` are
  editorial comparison references. Hours does not copy content from a modern
  edition merely because it was used for comparison.
