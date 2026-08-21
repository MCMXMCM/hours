#!/usr/bin/env node
import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { compileCorpus, loadCorpus, validateCorpus } from "./compiler.ts";
import { revisionFromLock, snapshotDivinumOfficium } from "./divinumOfficium.ts";
import {
  importSnapshotDirectory,
  loadSnapshotDirectory
} from "./divinumImporter.ts";
import {
  loadScoredSnapshotDirectory,
  mergeScoredSnapshotDirectories,
  snapshotScoredOffices
} from "./breviariumGregorianum.ts";
import { pinnedReadingToneGenerator } from "./chantTools.ts";
import {
  compileDevelopmentSnapshots,
  exportDevelopmentSnapshots
} from "./developmentCorpus.ts";
import { compileScoredReference, loadScoredReference } from "./scoredReference.ts";
import { compileScoredDevelopmentSnapshots } from "./scoredDevelopmentCorpus.ts";
import { compileKnownGeneratedComplineReadings } from "./generatedReadingCorpus.ts";
import { loadCompiledCorpus } from "./compiledCorpus.ts";
import {
  auditExpectedObservances,
  type ObservanceExpectation
} from "./observanceAudit.ts";
import { officeHours, type OfficeHour } from "./types.ts";
import {
  generatePerennialOrdo,
  uniqueOfficeConfigurations,
  type PerennialOrdoRange
} from "./perennialOrdo.ts";
import {
  compilePerennialPreview,
  compilePerennialRelease,
  populatePerennialSourceCache
} from "./perennialCorpus.ts";

function valueAfter(flag: string): string | undefined {
  const index = process.argv.indexOf(flag);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

function optionalPerennialRange(): PerennialOrdoRange | undefined {
  const from = valueAfter("--window-from");
  const to = valueAfter("--window-to");
  if (Boolean(from) !== Boolean(to)) usage();
  return from && to ? { from, to } : undefined;
}

function usage(): never {
  console.error("Usage: cli.ts validate --input corpus.json [--allow-incomplete]");
  console.error("   or: cli.ts compile --input corpus.json --output base-office.sqlite [--allow-incomplete]");
  console.error("   or: cli.ts recompile --input corpus.sqlite --output corpus.sqlite [--allow-incomplete]");
  console.error("   or: cli.ts snapshot --source-root divinum-officium --output snapshots --from YYYY-MM-DD --to YYYY-MM-DD");
  console.error("   or: cli.ts import-snapshots --input snapshots --output candidates.json");
  console.error("   or: cli.ts compile-snapshots --input snapshots --output base-office.sqlite [--seed corpus.json]");
  console.error("   or: cli.ts export-snapshots --input snapshots --output corpus.json [--seed corpus.json]");
  console.error("   or: cli.ts snapshot-scored-reference --chant-tools-root jgabc --output snapshots --from YYYY-MM-DD --to YYYY-MM-DD");
  console.error("   or: cli.ts merge-scored-snapshots --input shard1,shard2 --output snapshots");
  console.error("   or: cli.ts audit-observances --input scored-snapshots --expectations expectations.json [--divinum-input snapshots]");
  console.error("   or: cli.ts compile-scored-snapshots --input snapshots --scored-input scored-snapshots --output corpus.sqlite [--allow-reference-bundle]");
  console.error("   or: cli.ts inspect-scored-reference --input office.html");
  console.error("   or: cli.ts compile-scored-reference --input office.html --output fixture.sqlite --date YYYY-MM-DD --hour matins");
  console.error("   or: cli.ts enrich-known-readings --input corpus.sqlite --output corpus.sqlite --chant-tools-root jgabc");
  console.error("   or: cli.ts export-perennial-ordo --source-root divinum-officium --output ordo.json --from 1962 --to 2100");
  console.error("   or: cli.ts cache-perennial-recipes --ordo ordo.json --source-root divinum-officium --cache sources.sqlite [--window-from YYYY-MM-DD --window-to YYYY-MM-DD] [--concurrency 12]");
  console.error("   or: cli.ts compile-perennial-preview --ordo ordo.json --cache sources.sqlite --catalog base-office.sqlite --divinum-input snapshots/2026 --output base-office.sqlite [--window-from YYYY-MM-DD --window-to YYYY-MM-DD]");
  console.error("   or: cli.ts compile-perennial-release --ordo ordo.json --cache sources.sqlite --catalog base-office.sqlite --divinum-input snapshots/2026 --output base-office.sqlite [--window-from YYYY-MM-DD --window-to YYYY-MM-DD]");
  process.exit(64);
}

const command = process.argv[2];
if (!command) usage();
const allowIncomplete = process.argv.includes("--allow-incomplete");

try {
  if (command === "cache-perennial-recipes") {
    const ordoPath = valueAfter("--ordo");
    const sourceRoot = valueAfter("--source-root");
    const cache = valueAfter("--cache");
    if (!ordoPath || !sourceRoot || !cache) usage();
    const ordo = JSON.parse(readFileSync(resolve(ordoPath), "utf8"));
    await populatePerennialSourceCache({
      ordo,
      sourceRoot: resolve(sourceRoot),
      cache: resolve(cache),
      range: optionalPerennialRange(),
      concurrency: Number(valueAfter("--concurrency") ?? "12"),
      progress(completed, total) {
        console.log(`Resolved ${completed}/${total} reusable office configurations`);
      }
    });
    console.log(`Cached perennial recipe sources in ${resolve(cache)}`);
  } else if (
    command === "compile-perennial-preview"
    || command === "compile-perennial-release"
  ) {
    const ordoPath = valueAfter("--ordo");
    const cache = valueAfter("--cache");
    const catalog = valueAfter("--catalog");
    const divinumInput = valueAfter("--divinum-input");
    const output = valueAfter("--output");
    if (!ordoPath || !cache || !catalog || !divinumInput || !output) usage();
    const compile = command === "compile-perennial-release"
      ? compilePerennialRelease
      : compilePerennialPreview;
    const result = compile({
      ordoPath: resolve(ordoPath),
      cache: resolve(cache),
      database2026: resolve(catalog),
      divinumSnapshots2026: resolve(divinumInput),
      output: resolve(output),
      range: optionalPerennialRange()
    });
    console.log(
      `Compiled ${result.recipes} reusable ${
        command === "compile-perennial-release" ? "release" : "preview"
      } recipes to ${resolve(output)} `
      + `(${result.bytes} bytes)`
    );
    result.warnings.forEach(warning => console.warn(`warning: ${warning}`));
  } else if (command === "export-perennial-ordo") {
    const sourceRoot = valueAfter("--source-root");
    const outputPath = valueAfter("--output");
    const fromYear = Number(valueAfter("--from"));
    const toYear = Number(valueAfter("--to"));
    if (!sourceRoot || !outputPath || !fromYear || !toYear) usage();
    const revision = revisionFromLock(
      resolve("Tools/ContentCompiler/sources.lock.json"),
      "Divinum Officium"
    );
    const schedule = generatePerennialOrdo({
      sourceRoot: resolve(sourceRoot),
      sourceRevision: revision,
      fromYear,
      toYear
    });
    writeFileSync(resolve(outputPath), `${JSON.stringify(schedule)}\n`);
    console.log(
      `Exported ${schedule.days.length} resolved days and `
      + `${uniqueOfficeConfigurations(schedule).size} reusable office configurations`
    );
  } else if (command === "snapshot") {
    const sourceRoot = valueAfter("--source-root");
    const output = valueAfter("--output");
    const from = valueAfter("--from");
    const to = valueAfter("--to");
    if (!sourceRoot || !output || !from || !to) usage();
    const revision = revisionFromLock(
      resolve("Tools/ContentCompiler/sources.lock.json"),
      "Divinum Officium"
    );
    const records = snapshotDivinumOfficium({
      sourceRoot,
      outputRoot: output,
      from,
      to,
      expectedRevision: revision
    });
    console.log(`Captured ${records.length} pinned Divinum Officium snapshots`);
  } else if (command === "import-snapshots") {
    const inputPath = valueAfter("--input");
    const outputPath = valueAfter("--output");
    if (!inputPath || !outputPath) usage();
    const offices = importSnapshotDirectory(inputPath, outputPath);
    console.log(`Imported ${offices.length} bilingual office candidates for semantic review`);
  } else if (command === "compile-snapshots") {
    const inputPath = valueAfter("--input");
    const outputPath = valueAfter("--output");
    if (!inputPath || !outputPath) usage();
    const warnings = compileDevelopmentSnapshots({
      snapshots: inputPath,
      output: resolve(outputPath),
      seed: valueAfter("--seed")
    });
    console.log(`Compiled pinned development snapshots to ${resolve(outputPath)}`);
    warnings.forEach(warning => console.warn(`warning: ${warning}`));
  } else if (command === "export-snapshots") {
    const inputPath = valueAfter("--input");
    const outputPath = valueAfter("--output");
    if (!inputPath || !outputPath) usage();
    exportDevelopmentSnapshots({
      snapshots: inputPath,
      output: resolve(outputPath),
      seed: valueAfter("--seed")
    });
    console.log(`Exported pinned development snapshots to ${resolve(outputPath)}`);
  } else if (command === "snapshot-scored-reference") {
    const chantToolsRoot = valueAfter("--chant-tools-root");
    const output = valueAfter("--output");
    const from = valueAfter("--from");
    const to = valueAfter("--to");
    if (!chantToolsRoot || !output || !from || !to) usage();
    const revision = revisionFromLock(
      resolve("Tools/ContentCompiler/sources.lock.json"),
      "jgabc"
    );
    const records = await snapshotScoredOffices({
      outputRoot: output,
      from,
      to,
      generateReadingTone: pinnedReadingToneGenerator(
        chantToolsRoot,
        revision
      ),
      onProgress(completed, total, record) {
        if (completed === total || completed % 25 === 0) {
          console.log(
            `Captured ${completed}/${total} scored offices (${record.date} ${record.hour})`
          );
        }
      },
      onGap(completed, total, error) {
        console.warn(
          `gap: ${completed}/${total} ${error.date} ${error.hour}: ${error.message}`
        );
      }
    });
    console.log(`Captured ${records.length} Breviarium Gregorianum source concordances`);
  } else if (command === "compile-scored-snapshots") {
    const inputPath = valueAfter("--input");
    const scoredInputPath = valueAfter("--scored-input");
    const outputPath = valueAfter("--output");
    if (!inputPath || !scoredInputPath || !outputPath) usage();
    const warnings = compileScoredDevelopmentSnapshots({
      divinumSnapshots: inputPath,
      scoredSnapshots: scoredInputPath,
      output: resolve(outputPath),
      requireComplete: !process.argv.includes("--allow-incomplete"),
      allowBundledDevelopmentOutput: process.argv.includes("--allow-reference-bundle")
    });
    console.log(`Compiled scored development snapshots to ${resolve(outputPath)}`);
    warnings.forEach(warning => console.warn(`warning: ${warning}`));
  } else if (command === "merge-scored-snapshots") {
    const inputs = valueAfter("--input")?.split(",").filter(Boolean);
    const outputPath = valueAfter("--output");
    if (!inputs?.length || !outputPath) usage();
    const records = mergeScoredSnapshotDirectories(inputs, outputPath);
    console.log(`Merged ${records.length} scored office snapshots into ${resolve(outputPath)}`);
  } else if (command === "audit-observances") {
    const inputPath = valueAfter("--input");
    const expectationsPath = valueAfter("--expectations");
    if (!inputPath || !expectationsPath) usage();
    const expectations = JSON.parse(
      readFileSync(resolve(expectationsPath), "utf8")
    ) as ObservanceExpectation[];
    const expectedKeys = new Set(
      expectations.map(expectation => `${expectation.date}:${expectation.hour}`)
    );
    const records = loadScoredSnapshotDirectory(
      inputPath,
      record => expectedKeys.has(`${record.date}:${record.hour}`)
    );
    const divinumInputPath = valueAfter("--divinum-input");
    const independentKeys = new Set(
      expectations
        .filter(expectation => expectation.independentSource)
        .map(expectation => `${expectation.date}:${expectation.hour}`)
    );
    const independentOffices = divinumInputPath
      ? loadSnapshotDirectory(
        divinumInputPath,
        record => independentKeys.has(`${record.date}:${record.hour}`)
      ).offices
      : [];
    auditExpectedObservances(records, expectations, independentOffices);
    console.log(
      `Validated ${expectations.length} high-risk observance expectations`
    );
  } else if (command === "inspect-scored-reference") {
    const inputPath = valueAfter("--input");
    if (!inputPath) usage();
    const scores = loadScoredReference(inputPath);
    const sources = Map.groupBy(scores, score => score.source);
    console.log(`Found ${scores.length} unique GABC scores`);
    for (const [source, values] of sources) {
      console.log(`${source}: ${values.length}`);
    }
  } else if (command === "compile-scored-reference") {
    const inputPath = valueAfter("--input");
    const outputPath = valueAfter("--output");
    const date = valueAfter("--date");
    const hour = valueAfter("--hour");
    if (!inputPath || !outputPath || !date || !hour || !officeHours.includes(hour as OfficeHour)) {
      usage();
    }
    const warnings = compileScoredReference({
      input: inputPath,
      output: resolve(outputPath),
      date,
      hour: hour as OfficeHour
    });
    console.log(`Compiled scored reference to ${resolve(outputPath)}`);
    warnings.forEach(warning => console.warn(`warning: ${warning}`));
  } else if (command === "enrich-known-readings") {
    const inputPath = valueAfter("--input");
    const outputPath = valueAfter("--output");
    const chantToolsRoot = valueAfter("--chant-tools-root");
    if (!inputPath || !outputPath || !chantToolsRoot) usage();
    const revision = revisionFromLock(
      resolve("Tools/ContentCompiler/sources.lock.json"),
      "jgabc"
    );
    const result = compileKnownGeneratedComplineReadings({
      input: resolve(inputPath),
      output: resolve(outputPath),
      generateReadingTone: pinnedReadingToneGenerator(
        chantToolsRoot,
        revision
      ),
      revision
    });
    console.log(
      `Added ${result.addedSections} known generated reading tones and normalized `
      + `${result.normalizedSections} legacy score sections in ${resolve(outputPath)}`
    );
    result.warnings.forEach(warning => console.warn(`warning: ${warning}`));
  } else if (command === "recompile") {
    const inputPath = valueAfter("--input");
    const outputPath = valueAfter("--output");
    if (!inputPath || !outputPath) usage();
    const corpus = loadCompiledCorpus(resolve(inputPath));
    const warnings = compileCorpus(corpus, resolve(outputPath), allowIncomplete);
    console.log(
      `Recompiled ${corpus.offices.length} offices to ${resolve(outputPath)}`
    );
    warnings.forEach(warning => console.warn(`warning: ${warning}`));
  } else {
    const inputPath = valueAfter("--input");
    if (!inputPath) usage();
    const corpus = loadCorpus(resolve(inputPath));
    if (command === "validate") {
    const warnings = validateCorpus(corpus, allowIncomplete);
    console.log(`Validated ${corpus.offices.length} offices and ${corpus.days.length} liturgical days`);
    warnings.forEach(warning => console.warn(`warning: ${warning}`));
    } else if (command === "compile") {
      const outputPath = valueAfter("--output");
      if (!outputPath) usage();
      const warnings = compileCorpus(corpus, resolve(outputPath), allowIncomplete);
      console.log(`Compiled ${corpus.offices.length} offices to ${resolve(outputPath)}`);
      warnings.forEach(warning => console.warn(`warning: ${warning}`));
    } else {
      usage();
    }
  }
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
}
