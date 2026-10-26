# Hours

Hours is a native iPhone and iPad app for praying the Roman Divine Office
under the 1960 rubrics.

The app presents all eight canonical hours in Latin with optional English,
native Gregorian notation, a cantor guide for learning chants, a liturgical
calendar, the Mass of each day, and Home Screen widgets. Settings also offers
a Roman 1954 edition, an offline Guide to Chant, and a rubrics reference.

Hours is available from the
[App Store](https://apps.apple.com/us/app/hours-roman-breviary/id6794589632);
product information is at [horarum.com](https://horarum.com/).

## What is included

This repository is the source of the app as it is distributed. This revision
corresponds to Hours 1.2.0 (build 65). It contains:

- The SwiftUI app, shared core, and widget source
- Gregorian notation and chant-playback code
- The bundled offline office databases and Missals, exactly as shipped
- Source and provenance for the included GPL chant transcriptions
- The web app served at [liturgia.horarum.com](https://liturgia.horarum.com),
  in `web-app`, with the modules it builds in from beside it

The Xcode project, targets, and Swift modules use the **Hours** name
throughout.

Chant is parsed and engraved by
[gabc-parser](https://github.com/MCMXMCM/gabc-parser), under the MIT license:
Xcode fetches its Swift package at the revision pinned in
`Hours.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`,
and the web app installs its TypeScript package at the release tag pinned in
`web-app/package.json`.

The tooling that assembles the office databases and Missals from their
sources is not part of this repository, nor are the tests and development
tools. The databases are published in the form the app ships, and
[Content](Content/README.md) carries the editable GABC of every GPL-covered
chant they contain, with a description of how a score is stored.
The App Store icon artwork is likewise omitted, so a build from this
repository has no app icon.

## Project status

The bundled Roman 1960 corpus contains all eight canonical hours for every
civil date from 2025-01-01 through 2284-12-31. It is perennial: under fixed
rubrics a civil year's Office follows from the date of Easter and the length
of the year, so the database stores one civil year of each such year type (59
years) and reads any other year from the stored year of its type. The years
2025–2036 are the window that has been reviewed.

The Roman 1954 corpus covers the same dates in the same way, from the pinned
Divinum Officium `Divino Afflatu - 1954` source, with chant from the printed
books where that source has none. It is a source edition: its offices keep
the imported order, and its independent liturgical and musical review is
pending.

The Missals of the two editions, under `HoursApp/Resources/Missal`, give the
Mass of every day of the same years, from Divinum Officium's Missal, with the
chant of the Graduale Romanum and the settings of the Kyriale from GregoBase.
Their independent liturgical and musical review is pending.

## Building

Requirements:

- Xcode 27.1 or later
- Swift 6.4 or later
- Git LFS
- Node.js 24 or later, only for the GPL source export and the web app

```sh
git lfs pull
make build
```

The first build fetches the gabc-parser package from GitHub.

To verify the GPL source export against the databases:

```sh
make check-gpl-source
```

The web app is built with Node.js 24 or later, on macOS:

```sh
cd web-app
npm ci
npm run build
```

It reads the Office and the Mass from a corpus exported from the office
databases and Missals by tooling that is not part of this repository;
`web-app/README.md` says more.

## License

Hours is released under the
[GNU General Public License version 3](LICENSE).

Copyright and corresponding-source details are in [NOTICE.md](NOTICE.md).
Third-party copyrights, licenses, and acknowledgements are listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
