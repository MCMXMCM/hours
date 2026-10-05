# Copyright and source notice

Copyright © 2026 Matthew McCarty.

Hours is free software licensed under the GNU General Public License, version 3
only. It comes with absolutely no warranty. You may redistribute and modify it
under the terms in `LICENSE`.

This repository is the corresponding source of the Hours app distributed on
the App Store. This revision is the source of Hours 1.0.9 (build 49), and the
databases under `HoursApp/Resources/SharedOffice` are the ones that build
contains.

## GPL chant transcriptions

The bundled Roman 1960 database,
`HoursApp/Resources/SharedOffice/base-office.sqlite`, compiled on 2026-10-04,
contains 1,741 chant scores from two collections published under
`GPL-3.0-only`. The bundled Roman 1954 database contains none.

The editable GABC of every one of these scores, exactly as the app stores it,
is reproduced under `Content`. The manifest alongside each export records the
application score ID, source URL, recorded upstream checksum, GABC checksum,
and filename for every covered score. `Content/README.md` describes the export
and how the databases store a score.

### Nocturnale Romanum

- Upstream repository:
  `https://github.com/Nocturnale-Romanum/nocturnale-romanum`
- Pinned upstream revision:
  `84ce1514306be54bf4e693c9e8aa3bfd5e5aa3f2`
- 1,725 scores, reproduced under `Content/Nocturnale-Romanum/gabc`

Hours has modified these transcriptions. None is distributed exactly as it is
published upstream.

- 1,547 scores were packaged on 2026-07-24 through the Breviarium Gregorianum
  source concordance. As distributed they differ from the upstream files: each
  header is replaced by a `name:` line; the adiastematic (NABC) neume layer,
  the Euouae, and presentational markup are absent; and many are one
  separately sung part of a longer upstream score.
- 143 scores were added between 2026-09-30 and 2026-10-01 from the pinned
  revision. Each header is replaced by a `name:` line, and the NABC layer, the
  Euouae, and presentational markup are removed. The Paschaltide Alleluia is
  omitted where the Office does not sing it, and the editorial directions and
  tone-fitting signs of the Ordinary formulas are removed.
- 35 scores were composed on the same dates by setting other words to two
  formulas of the Nocturnale: its versicle tone, `ORW` (32 scores), and its
  absolution tone, `ORA` (3 scores). Chant Tools divided their syllables.

### Vesperale Romanum

- Upstream repository:
  `https://github.com/MRoth1910/Vesperale-Romanum`
- Pinned upstream revision:
  `823532191af5591d02afdf47eefa04eaef54f98f`
- 16 scores, reproduced under `Content/Vesperale-Romanum/gabc`

Hours added these antiphons on 2026-10-01 and has modified them. Each header
is replaced by a `name:` line; commented lines, the Euouae, and presentational
markup are removed; and the Paschaltide Alleluia is omitted where the Office
does not sing it.

### Packaging

Every score above was assigned an application identifier and a provenance
record, given a playback timeline derived from its notes, combined with other
office content, and packaged into SQLite.

## Source records

`Tools/ContentCompiler/sources.lock.json` pins the revision and license of
the third-party repositories read when the databases were assembled. Among
them are the Antiphonale Romanum (`GPL-3.0-only`) and Lauds notated
(Unlicense), which were searched for antiphons; no score from either is in the
bundled databases.

The Roman 1960 database manifest names
`Tools/ContentCompiler/Fixtures/martyrology-exceptional-review.json` as the
source of its English review of the exceptional Martyrology entries. That file
is kept at the same path in this repository, which is the published
corresponding source for it.
