# Hours

Hours is a native iPhone and iPad app for praying the Roman Divine Office
under the 1960 rubrics.

The app presents all eight canonical hours in Latin with optional English,
native Gregorian notation, a cantor guide for learning chants, a liturgical
calendar, and Home Screen widgets. Settings also offers a Roman 1954 edition,
an offline Guide to Chant, and a rubrics reference.

Hours is available from the
[App Store](https://apps.apple.com/us/app/hours-roman-breviary/id6794589632);
product information is at [horarum.com](https://horarum.com/).

## What is included

This repository is the source of the app as it is distributed. This revision
corresponds to Hours 1.0.9 (build 49). It contains:

- The SwiftUI app, shared core, and widget source
- Native Gregorian notation and chant-playback code
- Tests and the native notation validator
- The bundled offline office databases, exactly as shipped
- Source and provenance for the included GPL chant transcriptions

The Xcode project, targets, and Swift modules use the **Hours** name
throughout.

The tooling that assembles the office databases from their sources is not
part of this repository. The databases are published in the form the app
ships, and [Content](Content/README.md) carries the editable GABC of every
GPL-covered chant they contain, with a description of how a score is stored.
The App Store icon artwork is likewise omitted, so a build from this
repository has no app icon.

## Project status

The bundled Roman 1960 corpus contains all eight canonical hours for every
civil date from 2025-01-01 through 2036-12-31. It is the reviewed rolling
release window for the 2026 release year.

The Roman 1954 corpus covers the same dates from the pinned Divinum Officium
`Divino Afflatu - 1954` source. It is a source edition: its offices keep the
imported order, and its independent liturgical and musical review is pending.

## Building

Requirements:

- Xcode 26.5 or later
- Swift 6.3 or later
- Git LFS
- Node.js 24 or later, only for the GPL source export

```sh
git lfs pull
make build
```

To engrave every bundled chant with the native validator, and to verify the
GPL source export against the databases:

```sh
make native-notation-validate
make check-gpl-source
```

## License

Hours is released under the
[GNU General Public License version 3](LICENSE).

Copyright and corresponding-source details are in [NOTICE.md](NOTICE.md).
Third-party copyrights, licenses, and acknowledgements are listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
