# Copyright and source notice

Copyright © 2026 Matthew McCarty.

Hours is free software licensed under the GNU General Public License, version 3
only. It comes with absolutely no warranty. You may redistribute and modify it
under the terms in `LICENSE`.

This repository is the corresponding source of the Hours app distributed on
the App Store. This revision is the source of Hours 1.2.0 (build 65), and the
databases under `HoursApp/Resources/SharedOffice` and
`HoursApp/Resources/Missal` are the ones that build contains. It also holds
the source of the Hours web app as it is released at
https://liturgia.horarum.com, in `web-app`. The web app sends the same chant
to the reader's browser: the corpus it fetches is exported from these
databases, and the GPL scores in it are those reproduced under `Content`.
The About section of the app and of the web app shows this license and links
to these notices.

## GPL chant transcriptions

The bundled databases contain 3,109 chant scores from three collections
published under `GPL-3.0-only`: 1,746 in the Roman 1960 database,
`HoursApp/Resources/SharedOffice/base-office.sqlite`, compiled on 2026-10-14,
and 1,363 in the Roman 1954 database,
`HoursApp/Resources/SharedOffice/roman-1954-office.sqlite`, compiled on
2026-10-25. The Missals and the Kyriale under `HoursApp/Resources/Missal`
contain none: their chant is from GregoBase, under CC0.

The editable GABC of every one of these scores, exactly as the app stores it,
is reproduced under `Content`, one file for each distinct transcription (2,567
files). The manifest alongside each export records, for every covered score,
its database and row, its own identifier, its source URL, the recorded
upstream checksum, the GABC checksum, any modification the app records, and
its file. `Content/README.md` describes the export and how the databases store
a score.

### Nocturnale Romanum

- Upstream repository:
  `https://github.com/Nocturnale-Romanum/nocturnale-romanum`
- Pinned upstream revision:
  `84ce1514306be54bf4e693c9e8aa3bfd5e5aa3f2`
- 3,074 scores, 1,730 in the Roman 1960 database and 1,344 in the Roman 1954
  database, reproduced in 2,547 files under `Content/Nocturnale-Romanum/gabc`

Hours has modified these transcriptions. None is distributed exactly as it is
published upstream.

In the Roman 1960 database:

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
- 5 hymns were added on 2026-10-14 from the pinned revision, their headers
  and markup changed as above. In 3 of them the breviary's words are set
  under the transcription's notes, one syllable to each group of notes.

In the Roman 1954 database, added between 2026-10-11 and 2026-10-15 from the
pinned revision, each with its header replaced by a `name:` line and the NABC
layer, the Euouae, and presentational markup removed:

- 540 antiphons. 114 of them are only the opening that is intoned before the
  psalm, as far as the words the breviary prints there. 41 are the same
  transcriptions as scores of the Roman 1960 database.
- 722 responsories of Matins, each sung over its respond, its verse and the
  repeat, and over the Gloria Patri where the breviary says it: 23 are
  without the Gloria Patri the piece sets, which is not said there. The
  Paschaltide Alleluia is omitted where the breviary's respond does not have
  it.
- 45 versicles, composed by setting the breviary's words to the Nocturnale's
  versicle tone, `ORW`. Chant Tools divided their syllables.
- 37 hymns. In 18 of them the breviary's words are set under the
  transcription's notes, one syllable to each group of notes. On 2026-10-25
  one of these, Deus tuorum militum as it is sung for St Stephen, was given
  one word as the breviary writes it.

### Vesperale Romanum

- Upstream repository:
  `https://github.com/MRoth1910/Vesperale-Romanum`
- Pinned upstream revision:
  `823532191af5591d02afdf47eefa04eaef54f98f`
- 33 scores, 16 in the Roman 1960 database and 17 in the Roman 1954
  database, reproduced in 18 files under `Content/Vesperale-Romanum/gabc`

Hours added these antiphons on 2026-10-01 (Roman 1960) and between 2026-10-11
and 2026-10-12 (Roman 1954), and has modified them. Each header is replaced by
a `name:` line; commented lines, the Euouae, and presentational markup are
removed; and the Paschaltide Alleluia is omitted where the Office does not
sing it. 2 of those in the Roman 1954 database are only the opening that is
intoned before the psalm.

### Antiphonale Romanum

- Upstream repository: `https://github.com/xmarteo/Antiphonale_Romanum`
- Pinned upstream revision: `988498498631e5463ea5ef638f23118bf23ebc54`
- 2 scores, in the Roman 1954 database, reproduced under
  `Content/Antiphonale-Romanum/gabc`

Hours added these antiphons between 2026-10-11 and 2026-10-12 and has modified
them. Each header is replaced by a `name:` line, and the Euouae and
presentational markup are removed.

### Packaging

Every score above was assigned an application identifier and a provenance
record, given a playback timeline derived from its notes, combined with other
office content, and packaged into SQLite.

## Source records

`Tools/ContentCompiler/sources.lock.json` pins the revision and license of
the third-party repositories read when the databases were assembled. The
Roman 1954 database also holds 7 antiphons from Lauds notated, under the
Unlicense, which carries no copyleft obligation.

The Roman 1960 database manifest names
`Tools/ContentCompiler/Fixtures/martyrology-exceptional-review.json` as the
source of its English review of the exceptional Martyrology entries. That file
is kept at the same path in this repository, which is the published
corresponding source for it.
