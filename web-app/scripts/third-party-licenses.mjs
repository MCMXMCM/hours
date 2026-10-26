#!/usr/bin/env node
// Writes `public/licenses.txt`: the notices of the software the built web
// app carries. A minified bundle keeps none of its sources' notices, and
// their licences ask that the notice travel with the copy.
//
// The list is every package the app's own dependencies bring in, found by
// following `dependencies` from package.json, together with the service
// worker's Workbox modules, which are bundled into it.

import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  writeFileSync,
} from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const modules = join(root, "node_modules");
const own = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));

/** Bundled into the service worker, though installed for development. */
const bundledForTheWorker = Object.keys(own.devDependencies).filter((name) =>
  name.startsWith("workbox-"),
);

function manifest(name) {
  const path = join(modules, name, "package.json");
  return existsSync(path) ? JSON.parse(readFileSync(path, "utf8")) : null;
}

const found = new Map();
const pending = [...Object.keys(own.dependencies), ...bundledForTheWorker];
while (pending.length > 0) {
  const name = pending.pop();
  if (found.has(name)) continue;
  const description = manifest(name);
  if (!description) {
    throw new Error(
      `${name} is depended on but not installed. Run \`npm ci\`.`,
    );
  }
  found.set(name, description);
  // A peer the app itself installs (React, for one) is reached from there.
  pending.push(...Object.keys(description.dependencies ?? {}));
}

/**
 * What is said of a package that is published without a licence file. Each
 * is written by hand, so that a new package of the kind stops the build
 * until someone has read its terms.
 */
const statedByHand = {
  "@sqlite.org/sqlite-wasm": [
    "SQLite, compiled to WebAssembly, is in the public domain:",
    "https://sqlite.org/copyright.html",
    "",
    "The package that distributes this build, with its TypeScript types, is",
    "under the Apache License, Version 2.0, whose text is at",
    "https://www.apache.org/licenses/LICENSE-2.0",
  ].join("\n"),
};

/**
 * A package's licence, and the notices of what it carries under other terms
 * (gabc-parser's glyph outlines are Exsurge's, under Exsurge's notice).
 */
function notice(name) {
  const directory = join(modules, name);
  const entries = readdirSync(directory);
  const file = entries.find((entry) =>
    /^(licen[cs]e|copying|notice)(\.(md|txt))?$/i.test(entry),
  );
  const carried = entries.find((entry) =>
    /^third[-_]party[-_]notices(\.(md|txt))?$/i.test(entry),
  );
  const own = file
    ? readFileSync(join(directory, file), "utf8").trim()
    : (statedByHand[name] ?? null);
  if (own === null || !carried) return own;
  return `${own}\n\n${readFileSync(join(directory, carried), "utf8").trim()}`;
}

const rule = "-".repeat(72);
const sections = [...found.keys()].sort().map((name) => {
  const description = found.get(name);
  const license =
    typeof description.license === "string"
      ? description.license
      : (description.license?.type ?? "see below");
  const text = notice(name);
  if (text === null) {
    throw new Error(`${name} carries no licence file to reproduce.`);
  }
  const source =
    typeof description.repository === "string"
      ? description.repository
      : (description.repository?.url ?? description.homepage ?? "");
  return [
    rule,
    `${name} ${description.version}`,
    `License: ${license}`,
    source ? `Source: ${source.replace(/^git\+/, "")}` : null,
    rule,
    "",
    text,
    "",
  ]
    .filter((line) => line !== null)
    .join("\n");
});

const head = [
  "Hours for the web: third-party software",
  "",
  "The web app at liturgia.horarum.com is built with the software below, each",
  "under the licence reproduced beneath its name. The Office's texts and",
  "chant, the typeface, and the harp's sound bank are acknowledged at",
  "https://horarum.com/licenses; the typeface's and the sound bank's own",
  "licences are served beside them, at /fonts/EBGaramond-OFL.txt and",
  "/harp/LICENSE.txt.",
  "",
].join("\n");

mkdirSync(join(root, "public"), { recursive: true });
writeFileSync(
  join(root, "public", "licenses.txt"),
  `${head}\n${sections.join("\n")}`,
);
console.log(
  `Wrote the notices of ${found.size} packages to public/licenses.txt.`,
);
