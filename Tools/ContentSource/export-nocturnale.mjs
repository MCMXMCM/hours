#!/usr/bin/env node

import { createHash } from "node:crypto";
import {
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { inflateRawSync } from "node:zlib";

const repositoryRoot = resolve(
  dirname(new URL(import.meta.url).pathname),
  "../..",
);
const databasePath = join(
  repositoryRoot,
  "HoursApp/Resources/base-office.sqlite",
);
const exportRoot = join(
  repositoryRoot,
  "Content/Nocturnale-Romanum",
);
const gabcRoot = join(exportRoot, "gabc");

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function decodePayload(value) {
  let payload = Buffer.from(value);
  if (payload.subarray(0, 4).toString("ascii") === "NCP1") {
    const expectedLength = payload.readUInt32BE(4);
    payload = inflateRawSync(payload.subarray(8));
    if (payload.length !== expectedLength) {
      throw new Error(
        `Decoded ${payload.length} bytes; expected ${expectedLength}.`,
      );
    }
  }
  return JSON.parse(payload.toString("utf8"));
}

mkdirSync(gabcRoot, { recursive: true });

const database = new DatabaseSync(databasePath, { readOnly: true });
const rows = database.prepare(
  "SELECT id, payload FROM scores ORDER BY id",
).all();
const entries = [];

for (const row of rows) {
  const score = decodePayload(row.payload);
  const provenance = score.provenance ?? {};
  if (
    provenance.collection !== "Nocturnale Romanum"
    || provenance.license !== "GPL-3.0-only"
  ) {
    continue;
  }

  const gabc = score.gabc.endsWith("\n") ? score.gabc : `${score.gabc}\n`;
  const filename = `${row.id}.gabc`;
  writeFileSync(join(gabcRoot, filename), gabc, "utf8");
  entries.push({
    applicationScoreID: row.id,
    contentScoreID: score.id,
    file: `gabc/${filename}`,
    incipit: score.incipit,
    mode: score.mode,
    reviewStatus: score.reviewStatus,
    sourceBook: provenance.sourceBook,
    sourceURL: provenance.sourceURL,
    upstreamSnapshotSHA256: provenance.snapshot,
    gabcSHA256: sha256(gabc),
    license: provenance.license,
  });
}

if (entries.length !== 1547) {
  throw new Error(
    `Expected 1547 Nocturnale Romanum scores; found ${entries.length}.`,
  );
}

const manifest = {
  schemaVersion: 1,
  generatedAt: "2026-07-30T00:00:00Z",
  database: "HoursApp/Resources/base-office.sqlite",
  databaseSHA256: sha256(readFileSync(databasePath)),
  collection: "Nocturnale Romanum",
  license: "GPL-3.0-only",
  upstreamRepository:
    "https://github.com/Nocturnale-Romanum/nocturnale-romanum",
  upstreamRevision: "84ce1514306be54bf4e693c9e8aa3bfd5e5aa3f2",
  scoreCount: entries.length,
  entries,
};

writeFileSync(
  join(exportRoot, "manifest.json"),
  `${JSON.stringify(manifest, null, 2)}\n`,
  "utf8",
);

console.log(
  `Exported ${entries.length} GPL-covered scores to ${gabcRoot}`,
);
