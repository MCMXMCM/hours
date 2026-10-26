# GPL chant source

This directory contains the preferred editable form of every chant
transcription under `GPL-3.0-only` that is stored in the bundled office
databases:

- `Nocturnale-Romanum` holds the scores from the Nocturnale Romanum project.
- `Vesperale-Romanum` holds the scores from the Vesperale Romanum project.
- `Antiphonale-Romanum` holds the scores from the Antiphonale Romanum
  transcriptions of xmarteo.

Each `gabc` directory contains one exact UTF-8 GABC file for each distinct
transcription, named by the SHA-256 checksum of its text; a transcription that
several scores sing, in one edition or in both, is written once.
`manifest.json` lists every score that sings one: its database, its row in
that database's `scores` table, its own identifier, its file, its source URL,
its recorded upstream checksum and any modification the app records. It also
records the pinned upstream revision and the checksums of the databases from
which the export was read.

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

Each row of an edition's `scores` table carries an `id` and a `payload`. A
payload is JSON, stored as the four bytes `NCP1`, a big-endian 32-bit length,
and the raw DEFLATE stream. The JSON holds the score's own `id`, its `gabc`,
its `provenance` (collection, source, and license), and a playback `timeline`
derived from the notes. Where a value is repeated, `{"$r": n}` names row `n`
of the catalog's `resources` table, `{"$join": [...]}` joins such fragments
into one string, and `{"$timeline": [...]}` restores a shared timeline's
identifiers for one score.

`Tools/ContentSource/export-gpl-source.mjs` reads this format, and
`HoursCore/ContentPayloadCodec.swift` and `HoursCore/SharedContentDatabase.swift`
are the app's own readers.

The Missals of the two editions and the Kyriale, under
`HoursApp/Resources/Missal`, store each score's payload whole, without the
catalog. None of their scores is under a copyleft license, and the export
stops if one is.

The source is licensed under `GPL-3.0-only`. See the repository `LICENSE` and
`NOTICE.md`.
