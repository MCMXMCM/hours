# Third-party material and acknowledgements

This file distinguishes material distributed with Hours from sources consulted
only during development. Acknowledging a reference does not mean its code,
assets, or text are incorporated into the app, and Hours does not bundle a
license solely because a project or edition was consulted.

## Material distributed with Hours

- **Divinum Officium** — MIT, pinned at
  `79a596eeb68268c35334f25122af7ffc376934d5`. Hours distributes calendar and
  office-text data from this source, including English translations. The
  separate Roman 1954 source edition also incorporates its
  Latin-gabc transcriptions and generated psalmody. Original book and transcriber
  headers are retained in the GABC, with exact source hashes and transformation
  notices in each score.
  Its MIT
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
- **FreePats Concert Harp** — Creative Commons CC0 1.0. Hours distributes the
  FreePats SF2 made from Versilian Community Sample Library stereo recordings.
  Its provenance, recording details, checksum, source, and public-domain
  dedication are bundled at
  `HoursApp/Resources/ConcertHarp-LICENSE.txt`.
- **Chant transcriptions** — Each score records its own collection, source URL,
  source identifier, license, and checksum. GregoBase transcriptions are CC0,
  and scores generated with Chant Tools are under the Unlicense. The Roman 1960
  corpus contains 1,725 Nocturnale Romanum and 16 Vesperale Romanum
  transcriptions under GPL-3.0-only. Their exact editable GABC, provenance
  manifests, modification notices, and license are included under `Content`,
  `NOTICE.md`, and `LICENSE`.

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
  `f828578b2fc4f501697414080d4241a322ae3cc0`. Used for offline visual
  regression during development, not in the production rendering path; it is
  not part of this repository.
- **jgabc / Chant Tools** — Unlicense, pinned at
  `dff87490026adf21a97cac019a83b8611f0c2e71`. Used as a development generator
  and reference for reviewed psalmody, lesson, and chapter tones; its
  JavaScript is not distributed in the app.
- **Printed chant and office editions** — The 1960 *Liber antiphonarius*, the
  1961 *Liber Usualis*, historical Roman breviaries and martyrologies, and
  modern printed editions identified in `Docs/MISSING_OFFICE_SOURCES.md` are
  editorial comparison references. Hours does not copy content from a modern
  edition merely because it was used for comparison.
