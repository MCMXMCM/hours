# GPL chant source

This directory contains the preferred editable form of every chant
transcription under `GPL-3.0-only` that is stored in the bundled office
databases:

- `Nocturnale-Romanum` holds the scores from the Nocturnale Romanum project.
- `Vesperale-Romanum` holds the scores from the Vesperale Romanum project.

Each `gabc` directory contains one exact UTF-8 GABC file per application
score, named by the score's stable identifier. `manifest.json` maps those
files back to the application score IDs and records their source URLs and
SHA-256 checksums, together with the checksums of the databases from which
they were read.

Regenerate the export, or verify the committed one against the databases, with:

```sh
make export-gpl-source
make check-gpl-source
```

Both require Node.js 24 or later and the Git LFS databases.

## How the databases store a score

The app bundles three SQLite files under `HoursApp/Resources/SharedOffice`:
the Roman 1960 and Roman 1954 editions, and `office-resources.sqlite`, a
catalog of the strings and timelines the two editions share.

Each row of an edition's `scores` table carries a `stable_key` and a
`payload`. A payload is JSON, stored as the four bytes `NCP1`, a big-endian
32-bit length, and the raw DEFLATE stream. The JSON holds the score's `gabc`,
its `provenance` (collection, source, and license), and a playback `timeline`
derived from the notes. Where a value is repeated, `{"$r": n}` names row `n`
of the catalog's `resources` table, `{"$join": [...]}` joins such fragments
into one string, and `{"$timeline": [...]}` restores a shared timeline's
identifiers for one score.

`Tools/ContentSource/export-gpl-source.mjs` reads this format, and
`HoursCore/ContentPayloadCodec.swift` and `HoursCore/SharedContentDatabase.swift`
are the app's own readers.

The source is licensed under `GPL-3.0-only`. See the repository `LICENSE` and
`NOTICE.md`.
