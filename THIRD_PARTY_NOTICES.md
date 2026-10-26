# Third-party material and acknowledgements

This file distinguishes material distributed with Hours from sources consulted
only during development. Acknowledging a reference does not mean its code,
assets, or text are incorporated into the app, and Hours does not bundle a
license solely because a project or edition was consulted.

## Material distributed with Hours

- **Divinum Officium** — MIT, pinned at
  `79a596eeb68268c35334f25122af7ffc376934d5`. Hours distributes calendar,
  office-text and Missal data from this source, including English
  translations. The separate Roman 1954 source edition also incorporates its
  Latin-gabc transcriptions and generated psalmody. Original book and transcriber
  headers are retained in the GABC, with exact source hashes and transformation
  notices in each score.
  Its MIT
  grant is bundled at
  `HoursApp/Resources/Divinum-Officium-LICENSE.txt`.
- **Exsurge (bbloomf maintained fork)** — MIT, pinned at
  `0c39f61df0e7c843f467250976338cac62f94e62`. gabc-parser's native Swift
  vector geometry, which Hours distributes, is converted from its canonical
  Gregorian SVG glyph outlines.
  The app does not include Exsurge JavaScript, a web view, or an Exsurge runtime
  font. The required MIT notice is bundled at
  `HoursApp/Resources/Exsurge-LICENSE.txt`.
- **EB Garamond** — SIL Open Font License 1.1. Hours distributes the variable
  font and its license under `HoursApp/Resources`, and gabc-parser carries a
  copy of both.
- **gabc-parser** — MIT, version 0.8.0 (https://github.com/MCMXMCM/gabc-parser).
  Hours parses and engraves chant with its `GABCParser` and `GABCLayout`
  libraries, which hold the Exsurge-derived glyph geometry above, and on the
  web with its TypeScript package, which holds the same geometry.
- **FreePats Concert Harp** — Creative Commons CC0 1.0. Hours distributes the
  FreePats SF2 made from Versilian Community Sample Library stereo recordings.
  Its provenance, recording details, checksum, source, and public-domain
  dedication are bundled at
  `HoursApp/Resources/ConcertHarp-LICENSE.txt`.
- **Chant transcriptions** — Each score records its own collection, source URL,
  source identifier, license, and checksum. GregoBase transcriptions are CC0,
  and they are all the chant of the Missals and the Kyriale;
  scores generated with Chant Tools, and the Lauds notated transcriptions, are
  under the Unlicense; the Roman 1954 edition's own chant from Divinum Officium
  is under its MIT license. Under GPL-3.0-only, the Roman 1960 corpus contains
  1,730 Nocturnale Romanum and 16 Vesperale Romanum transcriptions, and the
  Roman 1954 corpus 1,344 Nocturnale Romanum, 17 Vesperale Romanum and 2
  Antiphonale Romanum transcriptions. Their exact editable GABC, provenance
  manifests, modification notices, and license are included under `Content`,
  `NOTICE.md`, and `LICENSE`.
- **The web app's packages** — React, React Router, Base UI, Floating UI,
  Workbox, Lucide, idb, gabc-parser and the others its build includes are under
  the MIT, ISC and Apache-2.0 licenses, and SQLite, compiled to WebAssembly,
  is in the public domain. `web-app/scripts/third-party-licenses.mjs` writes
  the notice of every package in the build to `web-app/public/licenses.txt`,
  which the app serves at `/licenses.txt`.

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
