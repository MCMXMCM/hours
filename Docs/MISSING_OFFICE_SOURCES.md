# Sources and promotion record for the 2026 source-gap offices

This note records the source research and compiler promotion for the twelve
documents that the upstream Breviarium Gregorianum capture could not produce.
It is not permission to copy a modern edition into a shipping corpus. Payload
distribution rights must still be reviewed.

## Scope and conclusion

The twelve documents are:

- Lauds and Vespers from Monday through Friday within the Easter Octave,
  2026-04-06 through 2026-04-10 (ten documents).
- Prime on 2026-02-22, whose Martyrology reading announces 2026-02-23.
- Prime on 2026-12-24, whose Martyrology reading announces Christmas Day.

The compiler now promotes all twelve as complete Latin documents. The ten
Easter offices include the reviewed chant payloads and formulaic canticle tones.
The two Prime documents include the complete Latin office and Martyrology but
intentionally omit English and Martyrology notation. A rights-cleared English
translation is deferred. The exceptional Christmas proclamation GABC also
remains deferred until it can be checked against a physical or licensed scan of
the applicable Martyrology.

## Source hierarchy

Use the sources for distinct, non-overlapping purposes:

1. **Rubrics:** the 1960 `Codex Rubricarum` and `Variationes in Martyrologio
   Romano`, promulgated in *Acta Apostolicae Sedis* 52 (1960), pp. 593-733:
   <https://www.vatican.va/archive/aas/documents/AAS-52-1960-ocr.pdf>.
2. **Easter Latin office text:** a 1961 `Breviarium Romanum`, checked against
   the pinned Divinum Officium `Tempora/Pasc0-0` through `Pasc0-5` files at
   revision `79a596eeb68268c35334f25122af7ffc376934d5`.
3. **Easter chant:** the 1960 Solesmes *Liber antiphonarius*, pp. 443-452.
   GregoBase's page-by-page index and source images are at
   <https://gregobase.selapa.net/source.php?id=48>.
4. **Secondary Easter chant check:** the 1961 Solesmes *Liber Usualis*,
   principally pp. 782-803:
   <https://gregobase.selapa.net/source.php?id=3>.
5. **Martyrology Latin:** *Martyrologium Romanum*, fourth edition after the
   typical edition, Vatican Polyglot Press, 1956, 542 pages, amended by the
   official 1960 `Variationes`. Bibliographic records:
   <https://books.google.com/books/about/Martyrologium_romanum.html?id=Nu0YAgAACAAJ>
   and
   <https://search.worldcat.org/title/Martyrologium-Romanum/oclc/83468870>.
6. **Martyrology English comparison:** *The Roman Martyrology*, edited by
   J. B. O'Connell, Newman Press, 1962. It expressly translates the fourth
   post-typical 1956 edition and includes eulogies approved through 1961:
   <https://books.google.com/books/about/The_Roman_Martyrology.html?id=ZLAvAQAAIAAJ>.
   Treat this as development-only until rights are resolved.
7. **Ordered presentation oracle:** pinned Breviarium Gregorianum snapshots.
   The live reference is <https://breviariumgregorianum.com/index.php>.
8. **Independent validator:** pinned Divinum Officium Latin and English data
   and generator code. It is valuable as a cross-check, but the English
   Martyrology files contain material defects described below.

For a physical bilingual Easter comparison, the most relevant edition is
*The Hours of the Divine Office in English and Latin*, Liturgical Press,
1963, volume 2 (Passion Sunday to August). Its bibliographic record is
<https://search.worldcat.org/pt/title/1260108>. The current Baronius 1961
Roman Breviary is based on that edition:
<https://www.baronius.com/roman-breviary.html>. These are comparison sources,
not automatically licensed payload sources.

## Easter Octave: shared structure

The weekday offices inherit the special Easter Sunday scaffold. The official
rubrics require the Easter-Octave form: Sunday psalms, omitted hymns and
chapters, and `Hæc dies` in the place prescribed by the proper. The daily
collect and Gospel-canticle antiphons change.

### Lauds

Materialize the document in the same occurrence order as the reviewed Easter
Sunday Lauds sidecar, substituting the daily Benedictus antiphon and collect:

1. opening (the Easter Sunday Vigil-only introductory rubrics are omitted);
2. the five shared antiphon/psalm occurrences:
   - `Angelus autem Dómini` — Psalm 92;
   - `Et ecce terræmótus` — Psalm 99;
   - `Erat autem aspéctus` — Psalm 62;
   - `Præ timóre autem eius` — `Benedicite`;
   - `Respóndens autem Angelus` — Psalms 148-150;
3. `Hæc dies`;
4. the daily Benedictus antiphon and Benedictus;
5. the daily collect and the reviewed Easter conclusion, including the
   double Alleluia where prescribed.

### Vespers

Materialize the document in the same occurrence order as the reviewed Easter
Sunday Vespers sidecar, substituting the daily Magnificat antiphon and collect:

1. opening;
2. the same five shared antiphons with Psalms 109, 110, 111, 112, and 113;
3. `Hæc dies`;
4. the daily Magnificat antiphon and Magnificat;
5. the daily collect and the reviewed Easter conclusion, including the
   double Alleluia where prescribed.

This reuse belongs in compiler components only. Each compiled date/hour must
still contain one complete, flattened, ordered document and its own visible
content digest. The app must not reconstruct the office.

## Easter Octave: daily propers

| Date | Day | Collect incipit | Benedictus antiphon | GABC | Mode / source | Magnificat antiphon | GABC | Mode / source |
| --- | --- | --- | --- | ---: | --- | --- | ---: | --- |
| 2026-04-06 | Monday | `Deus, qui solemnitáte pascháli` | `Jesus junxit se` | 11971 | 8; LA 1960 p. 448 | `Qui sunt hi sermónes` | 2314 | 8; LA p. 448, LU p. 788 |
| 2026-04-07 | Tuesday | `Deus, qui Ecclésiam tuam novo semper fœtu` | `Stetit Jesus in médio` | 12689 | 8; LA p. 449 | `Vidéte manus meas` | 2148 | 8; LA p. 449, LU p. 792 |
| 2026-04-08 | Wednesday | `Deus, qui nos resurrectiónis Domínicæ` | `Míttite in déxteram` | 12153 | 7; LA p. 450 | `Dixit Jesus discípulis suis` | 2023 | 8; LA p. 450, LU p. 795 |
| 2026-04-09 | Thursday | `Deus, qui diversitátem géntium` | `María stabat` | 11828 | 7; LA p. 450 | `Tulérunt Dóminum meum` | 2150 | 7; LA p. 451, LU p. 800 |
| 2026-04-10 | Friday | `Omnípotens sempitérne Deus, qui paschále sacraméntum` | `Undecim discípuli` | 12261 | 7; LA p. 451 | `Data est mihi` | 2917 | 8; LA p. 452, LU p. 803 |

The full Latin collects and antiphon texts are in the pinned files:

```text
web/www/horas/Latin/Tempora/Pasc0-1.txt
web/www/horas/Latin/Tempora/Pasc0-2.txt
web/www/horas/Latin/Tempora/Pasc0-3.txt
web/www/horas/Latin/Tempora/Pasc0-4.txt
web/www/horas/Latin/Tempora/Pasc0-5.txt
```

The parallel English validator files use the same paths below
`web/www/horas/English`. Before promotion, compare their translations
block-for-block with the selected bilingual printed edition and the pinned
Breviarium Gregorianum presentation snapshot.

## Easter Octave: shared GABC

| Chant | GregoBase ID | Mode | Printed source |
| --- | ---: | ---: | --- |
| `Angelus autem Dómini` | 1952 | 8 | LU 1961 p. 782; LA 1960 p. 443 |
| `Et ecce terræmótus` | 2038 | 7 | LU p. 782; LA pp. 443-444 |
| `Erat autem aspéctus` | 2344 | 8 | LU p. 782; LA p. 444 |
| `Præ timóre autem eius` | 2959 | 7 | LU p. 782; LA p. 444 |
| `Respóndens autem Angelus` | 2171 | 8 | LU p. 783; LA p. 444 |
| `Hæc dies` | 2230 | 2 | LU p. 783; LA p. 445 |
| `Benedicamus Domino, alleluia, alleluia` | 15864 | common tone | LA p. 445 |

Each GABC contains the psalm-tone ending needed by the pinned jgabc generator.
For this fixed 2026 promotion, the compiler reuses byte-identical generated
Benedictus and Magnificat templates from explicitly pinned, successfully
captured 2026 offices for the same canticle and termination. The shared psalm
tones come from the reviewed Easter Sunday sidecar. The compiled date/hour
documents remain fully flattened; the app performs no reconstruction.

The current GregoBase CSV fetched during this research had SHA-256
`cdb47eb71ee69bf13ca5830f0d7387130a023a5bb8b48f8c9b75356375b53bc0`.
That does **not** match the checksum currently pinned in `sources.lock.json`.
Do not silently use the live export. Snapshot the reviewed GABC files by ID and
checksum, or deliberately update the lock after reviewing the export change.

## Prime and the Martyrology

Prime announces the following civil day's Martyrology. Therefore:

| Office date | Announced date | Required opening |
| --- | --- | --- |
| 2026-02-22 | 2026-02-23 | `Séptimo Kaléndas Mártii Luna sexta Anno Dómini 2026` |
| 2026-12-24 | 2026-12-25 | `Octavo Kalendas Ianuarii Luna sexta décima Anno Dómini 2026` |

The date heading and lunar age are generated fields, not part of the static day
file. The pinned Divinum Officium snapshot materializes them after advancing to
the next civil date with its Gregorian ecclesiastical-lunar table algorithm.
The 2026 promotion requires the two exact headings above and compiles them into
the flattened document. Before generating a corpus for another year, port that
algorithm into the compiler with independent table fixtures. Never calculate it
in the app.

### February 23

Use the 1956 Latin day text with the 1960 official variation. Variation 20
explicitly deletes the first eulogy, `Vigilia sancti Matthiae Apostoli`.
The correct remaining order begins:

1. St. Peter Damian;
2. St. Polycarp of Smyrna and the twelve companions;
3. blessed Sirenus;
4. the seventy-two martyrs at Sirmium;
5. St. Martha of Astorga;
6. St. Lazarus at Constantinople;
7. St. Felix of Brescia;
8. the priest St. Polycarp at Rome;
9. St. Florentius at Seville;
10. St. Romana at Todi;
11. St. Milburga in England;
12. the common `Et álibi...` conclusion and response.

Pinned Latin validator:

```text
web/www/horas/Latin/Martyrologium1960/02-23.txt
```

### Christmas Day

Use the complete Christmas proclamation, preserving its standalone rubrics and
tone changes, followed by the day's eulogies in this order:

1. the chronological Christmas proclamation;
2. the rubric to raise the voice and kneel;
3. `Natívitas Dómini nostri Iesu Christi secúndum carnem` in the Passion tone;
4. the rubric to return to the usual lesson tone and stand;
5. St. Anastasia;
6. St. Peter Nolasco;
7. St. Eugenia;
8. the martyrs at Nicomedia;
9. the common `Et álibi...` conclusion and response.

Pinned Latin validator:

```text
web/www/horas/Latin/Martyrologium1960/12-25.txt
```

### Defects in the legacy English validator

Do not promote either pinned English Martyrology file as authoritative:

- `English/Martyrologium/02-23.txt` retains the Vigil of St. Matthias that the
  official 1960 variation deletes.
- The same file omits the complete St. Polycarp of Smyrna eulogy.
- `English/Martyrologium/12-25.txt` moves St. Peter Nolasco after the Nicomedia
  martyrs instead of pairing it with the second Latin eulogy.
- It also says that St. Peter Nolasco's feast is on the last day of January.
  The 1960 calendar and amended text say January 28 (`quinto Kaléndas
  Februárii`).

O'Connell's 1962 English edition contains the complete February 23 eulogies
without the suppressed vigil and keeps the Christmas eulogies in the Latin
order. It is the better English comparison source, but its copyright and
distribution status must be resolved before its wording is shipped.

### Martyrology notation

The normal daily eulogies do not have unique proper melodies. They are read in
the usual lesson tone; formulaic notation, if displayed, should be generated
from a reviewed Martyrology/lesson-tone definition. Existing normal Prime
sidecars correctly contain prose blocks without a GABC score, so leaving the
ordinary February reading unscored is consistent with the current product.

Christmas is exceptional. The book itself prescribes three audible states:

1. the proclamation in its special elevated tone;
2. `Natívitas Dómini nostri Iesu Christi secúndum carnem` in the Passion tone;
3. the remaining eulogies in the ordinary lesson tone.

GregoBase ID 18242,
<https://gregobase.selapa.net/chant.php?id=18242>, is an exact-text GABC
candidate titled `Proclamatio Nativitas DNIC (Martyrologium Romanum 1962)`.
It includes the traditional 5199 chronology and the special `Natívitas`
cadence. The record has no printed-book provenance, however. It must be
compared note-for-note with the applicable Martyrology before promotion.

Do not use GregoBase ID 18869: it is explicitly the Dominican tone with the
2004 Martyrology text. Do not use ID 9494 for this corpus either: it contains
the modern `Innumeris transactis sæculis` chronology, not the required 1956
text.

## Implemented integrity gates

For each of the twelve replacement documents, the compiler now:

1. validates the pinned Divinum Officium source snapshot before assembly;
2. checks the required proper incipits for every Easter antiphon and collect;
3. checks the exact order of the material February and Christmas Martyrology
   passages and rejects the suppressed Vigil of St. Matthias;
4. reads each selected GABC from a checked-in, source-ID-named payload, records
   its checksum and printed provenance, and notation-validates it at compile
   time;
5. materializes one complete flattened document and computes its canonical
   visible-content digest;
6. includes the twelve documents in the authoritative coverage count.

The remaining release work is a primary-source/distribution review, a
rights-cleared English translation if desired, and a note-for-note review of
the exceptional Christmas proclamation tone. Ordinary Martyrology prose may
remain unscored, consistently with other Prime documents.
