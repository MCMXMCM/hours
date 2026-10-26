# Hours web app

This is the source of the Hours web app as it is released at
https://liturgia.horarum.com: a client-side React and TypeScript
progressive web app, built with Vite, that gives readers without an iPhone
or iPad the same Office and Mass as the native app. Its chant is engraved by
[gabc-parser](https://github.com/MCMXMCM/gabc-parser).

## Building

The build needs Node.js 24 or later, on macOS, whose Swift renders the
harp's notes:

```sh
npm ci
npm run build
```

Its first step, `npm run prepare:assets`, gathers the fonts, the harp, the
guides and the third-party notices into `public/`. The public site's artwork
(the hour wheel's tapestry and pointer, and the icons) is not part of this
repository, and the build goes without it.

## The corpus

The app reads the Office and the Mass from a corpus exported from the office
databases under `HoursApp/Resources/SharedOffice` and the Missals under
`HoursApp/Resources/Missal`, by tooling that is not part of this repository.
`Tools/ContentCompiler/Sources/webCorpusFormat.ts` documents its form. The
editable source of the GPL chant it carries is under `Content`.

## License

The web app is part of Hours and is released under the same license; see
`LICENSE`, `NOTICE.md` and `THIRD_PARTY_NOTICES.md` at the root of this
repository. Its About section shows the license and links to these notices,
and `scripts/third-party-licenses.mjs` writes the notice of every package in
the build to `public/licenses.txt`.
