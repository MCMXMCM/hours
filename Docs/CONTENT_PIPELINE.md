# Content pipeline and release gate

## 1. Pin sources and calculate the ordo

Source revisions live in `Tools/ContentCompiler/sources.lock.json`. The complete
1962–2100 date/hour schedule is calculated directly by the pinned local Divinum
Officium 1960-rubrics engine. The compiler invokes its whole-year calendar
entry point once per year with:

- `version=Rubrics 1960 - 1960`
- the Gregorian computus and the engine's temporal, sanctoral, occurrence,
  concurrence, vigil, octave, transfer, and commemoration rules
- every civil year from 1962 through 2100

This produces 50,769 resolved days and 406,152 compact date/hour parity
references without making a network request or rendering one page per office.
The App Store bundle packages only the declared rolling 12-year reviewed window
(2025–2036 for release year 2026). The long schedule remains a local
validation fixture. Both point at normalized recipes and never duplicate prayers
or scores. Focused representative office snapshots remain useful as review
fixtures, but full-range page capture is not a build or release requirement.

Gregobase's CC0 CSV index is checksum-pinned, and matched GABC downloads must be
snapshotted by ID. Matins candidates also come from the pinned GPL-3.0-only
Nocturnale Romanum repository. GPL material is permitted in this open-source
project; those files remain provenance-distinct and retain their notices,
modification records, revision, checksum, and corresponding-source location.

## 2. Normalize reusable office resources

Representative `import-snapshots` fixtures parse the generator’s paired
Latin/English XHTML cells, preserve upstream section IDs and checksums, and
emit independent validation candidates. They review resource and recipe
classes, not every date that reuses them. The TypeScript schema is kept
field-for-field aligned
with the Swift `Codable` models; unknown enum values are compilation errors.
The semantic normalization/review stage converts approved candidates into:

- `LiturgicalDay` records the observance, rank, color, season, commemorations, and evening context.
- `OfficeDocument` contains ordered semantic sections for one of the eight
  canonical hours plus that hour's observance title, rank, color (when
  authoritative), commemorations, and Vespers context.
- Every record retains `sourceVersion`.

“Pray this evening” is resolved during compilation, not guessed at runtime. A
date’s Vespers document must say whether it is First Vespers, Second Vespers,
or ordinary Vespers and identify the associated observance. The compiler first
honors an explicit source label, including a source's identification of
Vespers as belonging to the preceding office in a concurrence. Otherwise, a
change from the daytime observance identifies First Vespers; an observance
that demonstrably began with First Vespers receives Second Vespers on its own
day; all remaining offices are classified as ordinary Vespers. The resolved
context is also copied to Compline so every evening-facing surface uses the
same liturgical identity.

## 3. Resolve chant

`chantResolver.ts` matches normalized full Latin first, then exact incipit plus office part. Mode and preferred source order disambiguate exact matches. The preferred tradition is a reviewed 1961 Solesmes/Liber Usualis source.

Breviarium Gregorianum scored-office pages are a development coverage oracle:
they expose the selected Gregobase IDs, Nocturnale codes, and generated
psalmody for all eight hours. More importantly, the page DOM records the
liturgical occurrence order of headings, prayers, translations, chants, and
repeated antiphons. Breviarium Gregorianum identifies Divinum Officium as the
source of its office texts and translations, so those payloads retain the
pinned Divinum Officium MIT provenance and notice. The checksummed pages remain
an assembly concordance while chant payloads retain their distinct primary
source licenses.

### One ordered intermediate representation

New concordance snapshots contain an `.ordered.json` sidecar in addition to the
raw HTML and score-only sidecar. `orderedReference.ts` parses the HTML with a
standards-compliant parser and emits one ordered `OfficeSection` array. It pairs
Latin and English by structural adjacency and anchors a score at its visible
container, not at the later script that renders it. Repeated uses of the same
antiphon remain separate section occurrences while sharing the deduplicated
`ChantScore.id`.

This ordered sidecar replaces the Divinum-text-plus-flat-score fuzzy merge.
Score-only snapshots are rejected by the compiler. The app's compatibility
builder exists only to display the already-bundled legacy development database;
the compiler never emits new documents that require it. Unknown visible
elements, unpaired translations, unconsumed score anchors, and remote frames
are hard errors.

For every authoritative date/hour, the compiler hashes the exact ordered
visible projection: section role, heading, Latin, English, rubric, and each
chant occurrence's GABC/review status. The reference golden must agree exactly.
Hours recomputes that digest after joining deduplicated scores to a document
and fails the whole read if it differs; partial offices are never displayed.
The manifest records `authoritativeOfficeCount` separately from nominal index
coverage so a development pack with quarantined gaps cannot appear complete.

There is no HTML rendering in the app. The corpus compiler is a Node build tool;
it serializes ordered native data to SQLite. The shipping app remains SwiftUI
and uses the native GABC renderer. When a reference page identifies a generated
lesson or chapter tone with a frame URL, the compiler reads only its explicit
Latin input and runs the checksum-pinned local jgabc generator. It never stores
or presents the frame.

The build sources have distinct, non-overlapping jobs:

- Breviarium Gregorianum snapshots provide the development assembly/order
  concordance and occurrence-level source links.
- Divinum Officium provides the calendar/ordo authority and an independent
  text/translation validator; it is not merged into ordered pages at runtime.
- Gregobase and Nocturnale Romanum provide primary chant payloads and
  provenance for promotion out of the development concordance.
- jgabc/Chant Tools generates formulaic psalmody, lessons, and chapters
  deterministically at build time.
- Exsurge is a development engraving comparison only, not a content source or
  app runtime.
- Neumz is unnecessary unless a future native NABC feature is deliberately
  added.

For a focused development audit, `snapshot-scored-reference` captures a
resumable, checksum-pinned concordance for the requested representative dates.
`compile-scored-snapshots` requires the ordered sidecars. It uses their
hour-specific metadata for display while comparing the title and rank against
Divinum Officium as an independent calendar check:

```sh
node Tools/ContentCompiler/Sources/cli.ts snapshot-scored-reference \
  --chant-tools-root ../jgabc \
  --output Tools/ContentCompiler/Snapshots/2026-scored-reference \
  --from 2026-01-01 --to 2026-12-31

node Tools/ContentCompiler/Sources/cli.ts compile-scored-snapshots \
  --input Tools/ContentCompiler/Snapshots/2026 \
  --scored-input Tools/ContentCompiler/Snapshots/2026-scored-reference \
  --output Tools/ContentCompiler/Output/2026-scored-reference.sqlite \
  --allow-incomplete

node Tools/ContentCompiler/Sources/cli.ts audit-observances \
  --input Tools/ContentCompiler/Snapshots/2026-scored-reference \
  --expectations Tools/ContentCompiler/Fixtures/2026-high-risk-observances.json \
  --divinum-input Tools/ContentCompiler/Snapshots/2026
```

Each captured page has separate checksummed ordered and score payloads. This includes the
lesson and chapter tones that Breviarium Gregorianum creates at runtime in
embedded Chant Tools frames; the snapshot command verifies the adjacent jgabc
checkout against `sources.lock.json` before generating them. A dynamic tone
without that pinned generator is a hard error rather than a silently missing
score.

The bundled 2026 development corpus predates the ordered sidecars. Its known
Compline blessing and chapter frames were previously enriched from the pinned
jgabc revision. This command is retained for reproducing that legacy artifact,
not as a stage in the authoritative ordered pipeline.

```sh
node Tools/ContentCompiler/Sources/cli.ts enrich-known-readings \
  --input HoursApp/Resources/base-office.sqlite \
  --output HoursApp/Resources/base-office.sqlite \
  --chant-tools-root ../jgabc
```

HTTP failures and valid pages containing zero scores remain explicit upstream
coverage gaps. A gap stays metadata-only unless it has an explicit,
checksum-pinned curated promotion. The 2026 compiler has twelve such
promotions: Easter Monday-Friday Lauds and Vespers, plus the February 22 and
December 24 Prime documents containing the following day's Martyrology. The
checked-in high-risk expectations pin Holy Week, Easter, Pentecost, First Vespers,
fixed/movable collisions, commemorations, year boundaries, and every known
2026 upstream source gap. The Easter Octave gaps additionally pin the complete
visible Divinum Officium document digest and the proper daily
Benedictus/Magnificat antiphon and collect incipits from `Tempora/Pasc0-1`
through `Pasc0-5`.
The two Prime gaps likewise pin the complete document digest and generated
Martyrology calendar/opening text. The promotion layer then applies explicit
ordered scaffolds, source-ID GABC payloads, required incipits, and Martyrology
order/omission assertions. It does not run a fuzzy merge or reconstruct content
in the app.
The primary-source and GABC promotion map for all twelve source gaps is
recorded in `Docs/MISSING_OFFICE_SOURCES.md`, including the known defects in
the legacy English Martyrology validator.
The audit loaders checksum and parse only the date/hour records named by the
expectations, keeping this focused gate fast without weakening full-pack
compilation.

This development output cannot overwrite the app bundle without the explicit
reference-bundle flag. GPL content is not a blocker; every promoted payload
must retain its pinned primary-source provenance and corresponding-source data.

No fuzzy result is accepted automatically. A curated override maps a stable section ID to one known candidate. Multiple equally preferred results produce `ambiguous`; absent results produce `missing`. Both fail release compilation.

Formulaic psalmody and recitation tones are generated only from reviewed tone definitions. jgabc is pinned as a public-domain reference implementation; generated output still receives a stable timeline and provenance.

## 4. Parse and render

All GABC is parsed into stable phrase, syllable, note, and clef events before
SQLite compilation. Timeline rows use compact storage keys in SQLite while the
public TypeScript and Swift models remain descriptive and aligned. The native
parser maps engraving notes one-to-one onto those IDs, which drive native tap
targets, accessibility, highlighting, and correct Cantor Guide pitch across
mid-score clef changes. Flat C-clefs such as `cb4` are clef events, not notes,
and the native renderer engraves their B-flat signature. Likewise, GABC
accidental declarations such as `ix` are standalone signs positioned at pitch
`i`, not sung notes. Their state applies to matching pitches until the next
divider (other than a virgula), while the native score preserves the sign as an
independent engraving element.

`NotationValidator` must accept the complete compiled pack before publication; unsupported syntax and timeline drift are hard failures. It engraves every score at 320, 390, and 768 points and rejects lost event identity, missing generated paths, non-finite geometry, or overlapping neume targets. Representative complex chants are shared between compiler and Swift tests and should also be snapshot-tested at iPhone/iPad widths, light/dark appearance, and accessibility sizes. Exsurge under `Tools/ReferenceRenderer` supplies development reference output only. Visual review must include clef changes, accidentals, named composite neumes, quilismas, liquescents, morae, episemata, divisions, ledger lines, custos, vowel-centered lyrics, justification, and line wrapping.

The native glyph catalog is reproducible from the pinned maintained Exsurge checkout:

```sh
make generate-glyphs EXSURGE_GLYPHS=/path/to/exsurge/src/Exsurge.Glyphs.js
```

The generated source records the upstream revision and must be regenerated and visually reviewed whenever that pin changes.

## 5. Coverage and human review

Release compilation requires every date and all eight hours in the declared
previous-year-through-next-10-years window, 100% Latin text coverage, 100% scored/formulaic
resource coverage, and zero ambiguity. Separately, native-provider activation
requires exact agreement with all 406,152 references in the 1962–2100 parity
fixture. The compiler validates the finite recipe/score catalog once, then
verifies every schedule reference and calendar invariant locally. Calendar
goldens must include:

- First Vespers and feast precedence
- commemorations and Saturday Office of Our Lady
- leap years and year boundaries
- Septuagesima, Holy Week, Easter, and Pentecost
- fixed/movable collisions

Generated observances, ranks, psalms, antiphons, commemorations, and collects
must be compared with the pinned local engine and a focused set of
human-reviewed printed-ordo fixtures. No release test performs one network
request per scheduled office. A full liturgical-season review is required
before TestFlight promotion.

## 6. Performance budgets

Before the corpus expands beyond 2026, the checked-in budgets are:

- Normalized one-year SQLite pack: at most 64 MiB.
- Reviewed rolling 12-year App Store pack: at most 128 MiB.
- Non-shipping complete 1962–2100 parity pack: at most 256 MiB.
- Cold repository open: at most 750 ms.
- One office read/decode: at most 250 ms.
- Resident memory during representative content access: at most 350 MiB,
  tracked with `XCTMemoryMetric`.

The time budgets are intentionally tested independently of SwiftUI rendering.
Notation is parsed and validated at build/install time; the app reuses bounded
parsed-score and layout caches instead of validating an entire office on every
open. SQLite day, document, and score JSON payloads use the versioned `NCP1`
envelope with a decoded-length field and raw DEFLATE payload. Both compiler and
Swift decoders verify that length; legacy uncompressed JSON remains readable.
The deterministic `recompile` command migrates an existing development pack to
the current timeline and storage contract without changing visible content.

## 7. Sign and publish

The signing private key must remain outside this repository and CI artifacts. The manifest signature covers:

`schemaVersion|corpusVersion|minimumAppVersion|packSHA256`

The app embeds only the public key. It verifies the manifest, pack hash, schema,
and minimum app version, then validates the staged SQLite schema, integrity,
foreign keys, manifest, rubrics, coverage, representative documents, and all
notation before replacing the installed corpus atomically.
