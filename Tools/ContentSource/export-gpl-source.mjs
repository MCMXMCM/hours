#!/usr/bin/env node

// Writes the editable GABC of every copyleft chant score in the bundled
// office databases to Content/, with a provenance manifest per collection.
// The bundled Missals and the Kyriale hold no such score, and the export
// stops if one appears there. Pass --check to compare the committed export
// with the databases instead.

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
// The Missals and the Kyriale keep each score whole, outside the catalog.
const missalScores = {
  "HoursApp/Resources/Missal/roman-1960-missal.sqlite":
    "SELECT id, payload FROM scores ORDER BY id",
  "HoursApp/Resources/Missal/roman-1954-missal.sqlite":
    "SELECT id, payload FROM scores ORDER BY id",
  "HoursApp/Resources/Missal/kyriale.sqlite":
    "SELECT position AS id, score AS payload FROM settings ORDER BY position",
};

// Every collection whose scores carry a copyleft license, with the directory
// its export is written to. A score under a license that is neither listed
// here nor known to be permissive stops the export, so new material cannot
// ship without its source. The upstream repository and the pinned revision
// of each are read from the source lock the databases were assembled with.
const collectionDirectories = {
  "Nocturnale Romanum": "Content/Nocturnale-Romanum",
  "Vesperale Romanum": "Content/Vesperale-Romanum",
  "Antiphonale Romanum (xmarteo)": "Content/Antiphonale-Romanum",
};
const lock = JSON.parse(
  readFileSync(join(repositoryRoot, "Tools/ContentCompiler/sources.lock.json"), "utf8"),
);
const collections = Object.fromEntries(
  Object.entries(collectionDirectories).map(([name, directory]) => {
    const source = lock.sources.find((entry) => entry.name === name);
    if (!source?.revision || !source.url || !source.license) {
      throw new Error(`The source lock does not pin ${name}.`);
    }
    return [name, {
      directory,
      license: source.license,
      upstreamRepository: source.url,
      upstreamRevision: source.revision,
    }];
  }),
);
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
  // A bundled edition (schema 4 or later) names the catalog it was packed with.
  if (manifest.schemaVersion >= 4 && meta("shared_catalog") !== catalogIdentity) {
    throw new Error(`${editionPath} belongs to another shared catalog.`);
  }

  const used = new Set();
  // A bundled edition keeps each score as its row number and payload.
  const rows = database
    .prepare("SELECT id, payload FROM scores ORDER BY id")
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
        `Score ${row.id} (${score.id}) in ${editionPath} is under `
          + `"${provenance.license}" from "${provenance.collection}", `
          + "which this export does not yet cover.",
      );
    }

    // A transcription is written once, named by its checksum, however many
    // scores of either edition sing it.
    const gabc = score.gabc.endsWith("\n") ? score.gabc : `${score.gabc}\n`;
    const file = `gabc/${sha256(gabc)}.gabc`;
    const target = exported.get(provenance.collection);
    target.files.set(file, gabc);
    target.entries.push({
      database: editionPath,
      scoreRow: row.id,
      contentScoreID: score.id,
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

for (const [missalPath, query] of Object.entries(missalScores)) {
  const database = new DatabaseSync(join(repositoryRoot, missalPath), {
    readOnly: true,
  });
  for (const row of database.prepare(query).all()) {
    const { id, provenance = {} } = decodePayload(row.payload);
    if (!permissiveLicenses.has(provenance.license)) {
      throw new Error(
        `Score ${row.id} (${id}) in ${missalPath} is under `
          + `"${provenance.license}" from "${provenance.collection}", `
          + "which this export does not yet cover.",
      );
    }
  }
}

const check = process.argv.includes("--check");
const problems = [];

for (const [name, collection] of Object.entries(collections)) {
  const { databases, entries, files } = exported.get(name);
  const manifest = {
    schemaVersion: 3,
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
    fileCount: files.size,
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
