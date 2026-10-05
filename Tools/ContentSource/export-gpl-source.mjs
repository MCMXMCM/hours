#!/usr/bin/env node

// Writes the editable GABC of every copyleft chant score in the bundled
// office databases to Content/, with a provenance manifest per collection.
// Pass --check to compare the committed export with the databases instead.

import { createHash } from "node:crypto";
import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { fileURLToPath } from "node:url";
import { inflateRawSync } from "node:zlib";

const repositoryRoot = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "../..",
);
const resources = "HoursApp/Resources/SharedOffice";
const catalogPath = `${resources}/office-resources.sqlite`;
const editionPaths = [
  `${resources}/base-office.sqlite`,
  `${resources}/roman-1954-office.sqlite`,
];

// Every collection whose scores carry a copyleft license. A score under a
// license that is neither listed here nor known to be permissive stops the
// export, so new material cannot ship without its source.
const collections = {
  "Nocturnale Romanum": {
    directory: "Content/Nocturnale-Romanum",
    license: "GPL-3.0-only",
    upstreamRepository:
      "https://github.com/Nocturnale-Romanum/nocturnale-romanum",
    upstreamRevision: "84ce1514306be54bf4e693c9e8aa3bfd5e5aa3f2",
  },
  "Vesperale Romanum": {
    directory: "Content/Vesperale-Romanum",
    license: "GPL-3.0-only",
    upstreamRepository: "https://github.com/MRoth1910/Vesperale-Romanum",
    upstreamRevision: "823532191af5591d02afdf47eefa04eaef54f98f",
  },
};
const permissiveLicenses = new Set(["CC0-1.0", "MIT", "Unlicense"]);

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

// Payloads are JSON, stored as "NCP1", a big-endian length, and raw DEFLATE.
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

const catalog = new DatabaseSync(join(repositoryRoot, catalogPath), {
  readOnly: true,
});
const catalogIdentity = catalog
  .prepare("SELECT value FROM meta WHERE key = 'identity'")
  .get()?.value;
const catalogLookup = catalog.prepare(
  "SELECT payload FROM resources WHERE id = ?",
);

// The bundled editions keep repeated strings in the shared catalog:
// {"$r": id} names a catalog value and {"$join": [...]} joins fragments.
function expand(value) {
  if (Array.isArray(value)) {
    return value.map(expand);
  }
  if (value === null || typeof value !== "object") {
    return value;
  }
  if ("$r" in value) {
    const row = catalogLookup.get(value.$r);
    if (!row) {
      throw new Error(`Missing shared resource ${value.$r}.`);
    }
    return decodePayload(row.payload);
  }
  if ("$join" in value) {
    return value.$join.map(expand).join("");
  }
  return Object.fromEntries(
    Object.entries(value).map(([key, child]) => [key, expand(child)]),
  );
}

function decodeScore(payload) {
  // The timeline is derived from the GABC and is not needed here.
  const { timeline: _timeline, ...score } = decodePayload(payload);
  return expand(score);
}

const exported = new Map(
  Object.keys(collections).map((name) => [
    name,
    { databases: [], entries: [], files: new Map() },
  ]),
);

for (const editionPath of editionPaths) {
  const database = new DatabaseSync(join(repositoryRoot, editionPath), {
    readOnly: true,
  });
  const meta = (key) =>
    database.prepare("SELECT value FROM meta WHERE key = ?").get(key)?.value;
  const manifest = JSON.parse(meta("manifest"));
  if (manifest.schemaVersion === 4 && meta("shared_catalog") !== catalogIdentity) {
    throw new Error(`${editionPath} belongs to another shared catalog.`);
  }

  const used = new Set();
  const rows = database
    .prepare("SELECT stable_key, payload FROM scores ORDER BY stable_key")
    .all();
  for (const row of rows) {
    const score = decodeScore(row.payload);
    const provenance = score.provenance ?? {};
    if (permissiveLicenses.has(provenance.license)) {
      continue;
    }
    const collection = collections[provenance.collection];
    if (!collection || collection.license !== provenance.license) {
      throw new Error(
        `Score ${row.stable_key} in ${editionPath} is under `
          + `"${provenance.license}" from "${provenance.collection}", `
          + "which this export does not yet cover.",
      );
    }

    const gabc = score.gabc.endsWith("\n") ? score.gabc : `${score.gabc}\n`;
    const file = `gabc/${row.stable_key}.gabc`;
    const target = exported.get(provenance.collection);
    if (target.files.has(file)) {
      throw new Error(`Two scores share the identifier ${row.stable_key}.`);
    }
    target.files.set(file, gabc);
    target.entries.push({
      applicationScoreID: row.stable_key,
      contentScoreID: score.id,
      database: editionPath,
      file,
      incipit: score.incipit,
      mode: score.mode,
      reviewStatus: score.reviewStatus,
      sourceBook: provenance.sourceBook,
      sourceURL: provenance.sourceURL,
      upstreamSnapshotSHA256: provenance.snapshot,
      gabcSHA256: sha256(gabc),
      license: provenance.license,
      ...(provenance.modifications
        ? { modifications: provenance.modifications }
        : {}),
    });
    used.add(provenance.collection);
  }

  for (const name of used) {
    exported.get(name).databases.push({
      path: editionPath,
      sha256: sha256(readFileSync(join(repositoryRoot, editionPath))),
      corpusVersion: manifest.corpusVersion,
      createdAt: manifest.createdAt,
      rubrics: manifest.rubrics,
    });
  }
}

const check = process.argv.includes("--check");
const problems = [];

for (const [name, collection] of Object.entries(collections)) {
  const { databases, entries, files } = exported.get(name);
  const manifest = {
    schemaVersion: 2,
    collection: name,
    license: collection.license,
    upstreamRepository: collection.upstreamRepository,
    upstreamRevision: collection.upstreamRevision,
    databases,
    sharedCatalog: {
      path: catalogPath,
      sha256: sha256(readFileSync(join(repositoryRoot, catalogPath))),
    },
    scoreCount: entries.length,
    entries,
  };
  files.set("manifest.json", `${JSON.stringify(manifest, null, 2)}\n`);

  const root = join(repositoryRoot, collection.directory);
  const gabcRoot = join(root, "gabc");
  const present = existsSync(gabcRoot)
    ? readdirSync(gabcRoot).map((file) => `gabc/${file}`)
    : [];
  const stale = present.filter((file) => !files.has(file));

  if (check) {
    for (const [file, content] of files) {
      const path = join(root, file);
      if (!existsSync(path) || readFileSync(path, "utf8") !== content) {
        problems.push(`${collection.directory}/${file} is missing or differs`);
      }
    }
    for (const file of stale) {
      problems.push(`${collection.directory}/${file} is not in the databases`);
    }
  } else {
    mkdirSync(gabcRoot, { recursive: true });
    for (const file of stale) {
      rmSync(join(root, file));
    }
    for (const [file, content] of files) {
      writeFileSync(join(root, file), content, "utf8");
    }
  }
  console.log(
    `${name}: ${entries.length} ${collection.license} scores `
      + `${check ? "checked in" : "exported to"} ${collection.directory}`,
  );
}

if (problems.length > 0) {
  console.error(problems.slice(0, 20).join("\n"));
  console.error(
    `${problems.length} differences. Run make export-gpl-source.`,
  );
  process.exit(1);
}
