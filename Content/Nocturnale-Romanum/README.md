# Nocturnale Romanum corresponding source

This directory contains the preferred editable form of every Nocturnale
Romanum chant transcription stored in
`HoursApp/Resources/base-office.sqlite`.

The `gabc` directory contains one exact UTF-8 GABC file per deduplicated
application score. `manifest.json` maps those files back to the application
score IDs and records their source URLs and SHA-256 checksums.

Regenerate and verify the export with:

```sh
make export-gpl-source
```

The source is licensed under `GPL-3.0-only`. See the repository `LICENSE` and
`NOTICE.md`.
