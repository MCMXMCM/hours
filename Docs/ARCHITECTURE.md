# Architecture

## Targets

- `Hours`: native SwiftUI office reader, Canvas score view, and cantor-guide audio.
- `HoursCore`: stable models, SQLite repository, GABC timelines, native engraving parser/layout, and signed pack installation/update.
- `HoursTests`: model/parser/repository/cryptographic tests.
- `HoursUITests`: compact-navigation and reader smoke test with screenshot attachment.
- `ContentCompiler`: Xcode aggregate target that runs the TypeScript validation suite.

## Normalized corpus and runtime flow

Schema 3 stores bilingual `text_resources`, complete GABC-plus-timeline scored
realizations, ordered `recipes`, and a compact date/hour `office_schedule`.
The app materializes one `OfficeDocument` lazily from those references. Text is
never syllabified or attached to notation at runtime; every scored realization
retains the exact lyric groups and event-to-syllable identity compiled with its
GABC. The same normalized text rows back the contentless FTS5 search index.
Latin FTS fields normalize accents, `æ`/`ae`, `œ`/`oe`, and `j`/`i`, while
English remains independently queryable. Chant incipits receive a high search
weight. Compact `text_scores` and `text_recipes` relations support lazy detail
loading and distinct scheduled-office usage counts without indexing the full
1.4-million-row ordered-section table in both reverse directions.

`LiturgicalOrdoProvider` separates schedule lookup from the repository. The
reviewed rolling 12-year schedule is authoritative in the installed app. It is
produced from the longer 1962–2100 parity schedule in one local pass through the
pinned 1960-rubrics rules engine, then stored as date/hour references to a finite
catalog of reusable recipes. Validation may iterate all 406,152 compact parity
rows, but it never fetches or snapshots 406,152 office pages. A calculated
provider is fail-closed: it cannot expose dates outside the reviewed window
until it matches every parity office and the focused calendar edge-case suite.

The app asks `ContentRepository` for the selected civil day and canonical hour, validates every available score against the native engraving parser, and renders ordinary office sections in a SwiftUI scroll view. `GregorianScoreView` draws immutable layout output with SwiftUI `Canvas`; transparent native controls provide a frame, accessibility element, and tap target for each neume.

The compiler-generated `ChantTimeline` remains the source of playback identity and timing. `GregorianScoreParser` maps raw GABC notes one-to-one onto those IDs while preserving clefs, named neume forms, note shapes, liquescence, accidentals, morae, episemata, divisions, and breaks in a separate engraving model. `GregorianEngravingLayoutEngine` composes form-specific glyphs, measures each notation/lyric unit around its vowel nucleus, then performs responsive line breaking, condensation, justification, staff placement, merged ledger lines, and custos in Swift.

`GregorianGlyphCatalog` is a checked-in native display list generated from the pinned bbloomf Exsurge fork. The generator parses the upstream SVG paths and converts arcs and shorthand curves to `move`, `line`, quadratic, and cubic commands. SwiftUI turns those commands directly into `Path` values. Production does not parse SVG, load a notation font, execute JavaScript, or host a web view.

Selecting a chant hands its `ChantScore` to `ChantPlaybackController`. The controller synthesizes an owned vowel-like guide tone through `AVAudioEngine`, advances the event timeline, and publishes the active ID directly to SwiftUI for highlighting and scrolling.

`Tools/ReferenceRenderer` contains the pinned original Exsurge build for development-only visual comparison. The production bundle contains only the generated native vector geometry permitted by Exsurge's MIT license; no WebKit, JavaScript, Exsurge runtime, or Exsurge glyph font is present.

The synthesizer is explicitly a pitch/phrasing guide, not an authoritative rhythmic performance. Microphone access, singing assessment, whole-office continuous playback, and speech recognition are outside this implementation.

## Offline and update behavior

The bundled SQLite corpus is always usable without a network. Correction packs are optional. Downloads never mutate the active database until signature, hash, schema, and app compatibility checks succeed. Atomic replacement in the same directory preserves the last-known-good corpus on verification, network, or staging failure.

The widget receives a small compiler-generated calendar index rather than
decoding office recipes. Search, bilingual text, notation, and all schedule
navigation remain available offline.
