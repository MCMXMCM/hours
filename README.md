# Hours

Hours is a native iPhone and iPad app for praying the Roman Divine Office
under the 1960 rubrics.

The app presents all eight canonical hours in Latin with optional English,
native Gregorian notation, a cantor guide for learning chants, a liturgical
calendar, and Home Screen widgets.

## What is included

This repository contains:

- The SwiftUI app, shared core, and widget source
- Native Gregorian notation and chant-playback code
- Tests and content-validation tools
- The TypeScript content compiler
- The bundled 2026 development corpus
- Source and provenance for included third-party chant transcriptions

The Xcode project, targets, and Swift modules use the **Hours** name
throughout.

## Project status

The bundled corpus is a development corpus covering 2026. It is intended for
development and testing and is not yet the complete release corpus.

## Building

Requirements:

- Xcode 26.5 or later
- Swift 6.3 or later
- Node.js 24 or later
- Git LFS

```sh
git lfs pull
npm ci --prefix Tools/ContentCompiler
make build
```

To run the content and notation checks:

```sh
make compiler-test
make native-notation-validate
```

## License

Hours is released under the
[GNU General Public License version 3](LICENSE).

Third-party copyrights, licenses, and acknowledgements are listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
