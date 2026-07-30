# Architecture

## Targets

- `Hours`: native SwiftUI office reader, Canvas score view, and cantor-guide audio.
- `HoursCore`: stable models, SQLite repository, GABC timelines, native engraving parser/layout, and signed pack installation/update.
- `HoursTests`: model/parser/repository/cryptographic tests.
- `HoursUITests`: compact-navigation and reader smoke test with screenshot attachment.
- `ContentCompiler`: Xcode aggregate target that runs the TypeScript validation suite.

## Runtime flow

The app asks `ContentRepository` for the selected civil day and canonical hour, validates every available score against the native engraving parser, and renders ordinary office sections in a SwiftUI scroll view. `GregorianScoreView` draws immutable layout output with SwiftUI `Canvas`; transparent native controls provide a frame, accessibility element, and tap target for each neume.

The compiler-generated `ChantTimeline` remains the source of playback identity and timing. `GregorianScoreParser` maps raw GABC notes one-to-one onto those IDs while preserving clefs, named neume forms, note shapes, liquescence, accidentals, morae, episemata, divisions, and breaks in a separate engraving model. `GregorianEngravingLayoutEngine` composes form-specific glyphs, measures each notation/lyric unit around its vowel nucleus, then performs responsive line breaking, condensation, justification, staff placement, merged ledger lines, and custos in Swift.

`GregorianGlyphCatalog` is a checked-in native display list generated from the pinned bbloomf Exsurge fork. The generator parses the upstream SVG paths and converts arcs and shorthand curves to `move`, `line`, quadratic, and cubic commands. SwiftUI turns those commands directly into `Path` values. Production does not parse SVG, load a notation font, execute JavaScript, or host a web view.

Selecting a chant hands its `ChantScore` to `ChantPlaybackController`. The controller synthesizes an owned vowel-like guide tone through `AVAudioEngine`, advances the event timeline, and publishes the active ID directly to SwiftUI for highlighting and scrolling.

`Tools/ReferenceRenderer` contains the pinned original Exsurge build for development-only visual comparison. The production bundle contains only the generated native vector geometry permitted by Exsurge's MIT license; no WebKit, JavaScript, Exsurge runtime, or Exsurge glyph font is present.

The synthesizer is explicitly a pitch/phrasing guide, not an authoritative rhythmic performance. Microphone access, singing assessment, whole-office continuous playback, and speech recognition are outside this implementation.

## Offline and update behavior

The bundled SQLite corpus is always usable without a network. Correction packs are optional. Downloads never mutate the active database until signature, hash, schema, and app compatibility checks succeed. Atomic replacement in the same directory preserves the last-known-good corpus on verification, network, or staging failure.
