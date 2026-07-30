import { createHash } from "node:crypto";
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  writeFileSync
} from "node:fs";
import { join, resolve } from "node:path";
import {
  parseOrderedReferenceOffice,
  parseReferenceObservance,
  type ReferenceObservanceMetadata,
  type OrderedReferenceOffice,
  type OrderedReferenceSection
} from "./orderedReference.ts";
import { parseScoredReference, type ScoredReference } from "./scoredReference.ts";
import { canonicalVisibleContentDigest } from "./compiler.ts";
import { officeHours, type OfficeHour } from "./types.ts";
import type { ReadingToneGenerator } from "./chantTools.ts";

const defaultBaseURL = "https://breviariumgregorianum.com/index.php";
const orderedParserVersion = 2;

const officeParameterByHour: Record<OfficeHour, string> = {
  matins: "matutinum",
  lauds: "laudes",
  prime: "prima",
  terce: "tertia",
  sext: "sexta",
  none: "nona",
  vespers: "vesperas",
  compline: "completorium"
};

export interface ScoredSnapshotRecord {
  date: string;
  hour: OfficeHour;
  file: string;
  sha256: string;
  sourceURL: string;
  scoreCount: number;
  scoresFile?: string;
  scoresSHA256?: string;
  orderedFile?: string;
  orderedSHA256?: string;
  orderedSectionCount?: number;
  visibleContentDigest?: string;
  orderedParserVersion?: number;
}

export interface ScoredSnapshotManifest {
  source: "Breviarium Gregorianum";
  purpose: "source-concordance";
  baseURL: string;
  rubrics: "Rubrics 1960 - 1960";
  from: string;
  to: string;
  records: ScoredSnapshotRecord[];
  errors: ScoredSnapshotError[];
}

function recordFiles(record: ScoredSnapshotRecord): string[] {
  return [
    record.file,
    record.scoresFile,
    record.orderedFile
  ].filter((value): value is string => Boolean(value));
}

export interface ScoredSnapshotError {
  date: string;
  hour: OfficeHour;
  sourceURL: string;
  message: string;
}

export interface LoadedScoredOffice extends ScoredSnapshotRecord {
  scores: ScoredReference[];
  orderedSections?: OrderedReferenceSection[];
  observance: ReferenceObservanceMetadata;
}

function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function civilDates(from: string, to: string): string[] {
  const first = new Date(`${from}T12:00:00Z`);
  const last = new Date(`${to}T12:00:00Z`);
  if (Number.isNaN(first.valueOf()) || Number.isNaN(last.valueOf()) || first > last) {
    throw new Error("Invalid Breviarium Gregorianum snapshot date range");
  }
  const dates: string[] = [];
  for (const cursor = new Date(first); cursor <= last; cursor.setUTCDate(cursor.getUTCDate() + 1)) {
    dates.push(cursor.toISOString().slice(0, 10));
  }
  return dates;
}

export function scoredOfficeURL(
  date: string,
  hour: OfficeHour,
  baseURL = defaultBaseURL
): string {
  const url = new URL(baseURL);
  url.search = new URLSearchParams({
    // The compact view only exposes the first pointed verse of each psalm.
    // Detailed mode carries the complete generated psalm-tone GABC and the
    // repeated antiphon in its proper place after the psalmody.
    compact: "",
    date,
    lang: "en",
    office: officeParameterByHour[hour],
    version: "Rubrics 1960 - 1960"
  }).toString();
  return url.toString();
}

function writeManifest(root: string, manifest: ScoredSnapshotManifest): void {
  const target = join(root, "snapshot-manifest.json");
  const temporary = join(root, "snapshot-manifest.json.part");
  writeFileSync(temporary, `${JSON.stringify(manifest, null, 2)}\n`);
  renameSync(temporary, target);
}

async function fetchPage(url: string): Promise<string> {
  let lastError: unknown;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      const response = await fetch(url, {
        headers: {
          "Accept": "text/html,application/xhtml+xml",
          "User-Agent": "HoursContentCompiler/0.1 (source concordance snapshot)"
        },
        signal: AbortSignal.timeout(30_000)
      });
      if (!response.ok) {
        const error = new Error(`HTTP ${response.status}`);
        if (response.status === 404) throw { nonRetryable: true, error };
        throw error;
      }
      const html = await response.text();
      if (!/<html|<!doctype/i.test(html)) throw new Error("response is not HTML");
      return html;
    } catch (error) {
      if (
        error
        && typeof error === "object"
        && "nonRetryable" in error
        && "error" in error
      ) {
        throw (error as { error: Error }).error;
      }
      lastError = error;
      if (attempt < 3) {
        await new Promise(resolveDelay => setTimeout(resolveDelay, attempt * 750));
      }
    }
  }
  const detail = lastError instanceof Error ? `: ${lastError.message}` : "";
  throw new Error(`Unable to capture ${url}${detail}`, { cause: lastError });
}

export async function snapshotScoredOffices(options: {
  outputRoot: string;
  from: string;
  to: string;
  baseURL?: string;
  delayMS?: number;
  generateReadingTone?: ReadingToneGenerator;
  onProgress?: (completed: number, total: number, record: ScoredSnapshotRecord) => void;
  onGap?: (completed: number, total: number, error: ScoredSnapshotError) => void;
}): Promise<ScoredSnapshotRecord[]> {
  const root = resolve(options.outputRoot);
  const baseURL = options.baseURL ?? defaultBaseURL;
  const manifestPath = join(root, "snapshot-manifest.json");
  mkdirSync(root, { recursive: true });

  let existing: ScoredSnapshotManifest | undefined;
  if (existsSync(manifestPath)) {
    existing = JSON.parse(readFileSync(manifestPath, "utf8")) as ScoredSnapshotManifest;
    if (
      existing.source !== "Breviarium Gregorianum"
      || existing.baseURL !== baseURL
      || existing.rubrics !== "Rubrics 1960 - 1960"
    ) {
      throw new Error("Existing scored snapshot manifest has different source settings");
    }
  }
  const reusable = new Map((existing?.records ?? []).map(record => [
    `${record.date}:${record.hour}`,
    record
  ]));
  const records: ScoredSnapshotRecord[] = [];
  const work = civilDates(options.from, options.to)
    .flatMap(date => officeHours.map(hour => ({ date, hour })));
  const manifest: ScoredSnapshotManifest = {
    source: "Breviarium Gregorianum",
    purpose: "source-concordance",
    baseURL,
    rubrics: "Rubrics 1960 - 1960",
    from: options.from,
    to: options.to,
    records,
    errors: []
  };

  for (const [index, item] of work.entries()) {
    const key = `${item.date}:${item.hour}`;
    const cached = reusable.get(key);
    const sourceURL = scoredOfficeURL(item.date, item.hour, baseURL);
    if (
      cached
      && cached.sourceURL === sourceURL
      && existsSync(join(root, cached.file))
    ) {
      const html = readFileSync(join(root, cached.file), "utf8");
      const scoresPath = cached.scoresFile
        ? join(root, cached.scoresFile)
        : undefined;
      const scoresJSON = scoresPath && existsSync(scoresPath)
        ? readFileSync(scoresPath, "utf8")
        : undefined;
      const orderedPath = cached.orderedFile
        ? join(root, cached.orderedFile)
        : undefined;
      const orderedJSON = orderedPath && existsSync(orderedPath)
        ? readFileSync(orderedPath, "utf8")
        : undefined;
      const scores = scoresJSON
        ? JSON.parse(scoresJSON) as ScoredReference[]
        : parseScoredReference(html, {
          generateReadingTone: options.generateReadingTone
        });
      const scoresMatch = scoresJSON
        ? sha256(scoresJSON) === cached.scoresSHA256
        : true;
      const cachedOrderedSections = orderedJSON
        ? JSON.parse(orderedJSON) as OrderedReferenceSection[]
        : undefined;
      const orderedMatch = orderedJSON && cachedOrderedSections
        ? sha256(orderedJSON) === cached.orderedSHA256
          && cachedOrderedSections.length === cached.orderedSectionCount
          && canonicalVisibleContentDigest(cachedOrderedSections)
            === cached.visibleContentDigest
          && cached.orderedParserVersion === orderedParserVersion
        : false;
      if (
        sha256(html) === cached.sha256
        && scoresMatch
        && scores.length === cached.scoreCount
      ) {
        if (!scoresJSON || !orderedMatch) {
          const scoresFile = cached.scoresFile
            ?? `${item.date}-${item.hour}.scores.json`;
          const currentScoresJSON = scoresJSON
            ?? `${JSON.stringify(scores, null, 2)}\n`;
          if (!scoresJSON) {
            writeFileSync(join(root, scoresFile), currentScoresJSON);
          }
          let ordered: OrderedReferenceOffice;
          try {
            ordered = parseOrderedReferenceOffice(html, {
              generateReadingTone: options.generateReadingTone
            });
          } catch (error) {
            const gap: ScoredSnapshotError = {
              ...item,
              sourceURL,
              message: error instanceof Error ? error.message : String(error)
            };
            manifest.errors.push(gap);
            writeManifest(root, manifest);
            options.onGap?.(index + 1, work.length, gap);
            continue;
          }
          const orderedFile = cached.orderedFile
            ?? `${item.date}-${item.hour}.ordered.json`;
          const currentOrderedJSON = `${JSON.stringify(ordered.sections, null, 2)}\n`;
          writeFileSync(join(root, orderedFile), currentOrderedJSON);
          const visibleContentDigest = canonicalVisibleContentDigest(ordered.sections);
          const upgraded = {
            ...cached,
            scoresFile,
            scoresSHA256: sha256(currentScoresJSON),
            orderedFile,
            orderedSHA256: sha256(currentOrderedJSON),
            orderedSectionCount: ordered.sections.length,
            visibleContentDigest,
            orderedParserVersion
          };
          records.push(upgraded);
          writeManifest(root, manifest);
          options.onProgress?.(index + 1, work.length, upgraded);
        } else {
          records.push(cached);
          options.onProgress?.(index + 1, work.length, cached);
        }
        continue;
      }
    }

    let html: string;
    try {
      html = await fetchPage(sourceURL);
    } catch (error) {
      const gap: ScoredSnapshotError = {
        ...item,
        sourceURL,
        message: error instanceof Error ? error.message : String(error)
      };
      manifest.errors.push(gap);
      writeManifest(root, manifest);
      options.onGap?.(index + 1, work.length, gap);
      continue;
    }
    const file = `${item.date}-${item.hour}.html`;
    writeFileSync(join(root, file), html);
    let scores: ScoredReference[];
    let ordered: OrderedReferenceOffice;
    try {
      scores = parseScoredReference(html, {
        generateReadingTone: options.generateReadingTone
      });
      ordered = parseOrderedReferenceOffice(html, {
        generateReadingTone: options.generateReadingTone
      });
    } catch (error) {
      const gap: ScoredSnapshotError = {
        ...item,
        sourceURL,
        message: error instanceof Error ? error.message : String(error)
      };
      manifest.errors.push(gap);
      writeManifest(root, manifest);
      options.onGap?.(index + 1, work.length, gap);
      continue;
    }
    const scoresFile = `${item.date}-${item.hour}.scores.json`;
    const scoresJSON = `${JSON.stringify(scores, null, 2)}\n`;
    writeFileSync(join(root, scoresFile), scoresJSON);
    const orderedFile = `${item.date}-${item.hour}.ordered.json`;
    const orderedJSON = `${JSON.stringify(ordered.sections, null, 2)}\n`;
    writeFileSync(join(root, orderedFile), orderedJSON);
    const record: ScoredSnapshotRecord = {
      ...item,
      file,
      sha256: sha256(html),
      sourceURL,
      scoreCount: scores.length,
      scoresFile,
      scoresSHA256: sha256(scoresJSON),
      orderedFile,
      orderedSHA256: sha256(orderedJSON),
      orderedSectionCount: ordered.sections.length,
      visibleContentDigest: canonicalVisibleContentDigest(ordered.sections),
      orderedParserVersion
    };
    records.push(record);
    writeManifest(root, manifest);
    options.onProgress?.(index + 1, work.length, record);
    if ((options.delayMS ?? 150) > 0 && index + 1 < work.length) {
      await new Promise(resolveDelay => setTimeout(resolveDelay, options.delayMS ?? 150));
    }
  }
  writeManifest(root, manifest);
  return records;
}

export function loadScoredSnapshotDirectory(
  inputRoot: string,
  include: (record: ScoredSnapshotRecord) => boolean = () => true
): LoadedScoredOffice[] {
  const root = resolve(inputRoot);
  const manifest = JSON.parse(
    readFileSync(join(root, "snapshot-manifest.json"), "utf8")
  ) as ScoredSnapshotManifest;
  if (
    manifest.source !== "Breviarium Gregorianum"
    || manifest.purpose !== "source-concordance"
    || manifest.rubrics !== "Rubrics 1960 - 1960"
  ) {
    throw new Error("Invalid Breviarium Gregorianum scored snapshot manifest");
  }
  return manifest.records.filter(include).map(record => {
    const html = readFileSync(join(root, record.file), "utf8");
    if (sha256(html) !== record.sha256) {
      throw new Error(`${record.file} does not match its scored snapshot checksum`);
    }
    let scores: ScoredReference[];
    if (record.scoresFile && record.scoresSHA256) {
      const scoresJSON = readFileSync(join(root, record.scoresFile), "utf8");
      if (sha256(scoresJSON) !== record.scoresSHA256) {
        throw new Error(`${record.scoresFile} does not match its scored payload checksum`);
      }
      scores = JSON.parse(scoresJSON) as ScoredReference[];
    } else {
      scores = parseScoredReference(html);
    }
    if (scores.length !== record.scoreCount) {
      throw new Error(`${record.file} no longer parses to its recorded score count`);
    }
    let orderedSections: OrderedReferenceSection[] | undefined;
    if (
      record.orderedFile
      && record.orderedSHA256
      && record.orderedSectionCount !== undefined
    ) {
      const orderedJSON = readFileSync(join(root, record.orderedFile), "utf8");
      if (sha256(orderedJSON) !== record.orderedSHA256) {
        throw new Error(`${record.orderedFile} does not match its ordered payload checksum`);
      }
      orderedSections = JSON.parse(orderedJSON) as OrderedReferenceSection[];
      if (orderedSections.length !== record.orderedSectionCount) {
        throw new Error(
          `${record.orderedFile} no longer contains its recorded section count`
        );
      }
      const actualVisibleDigest = canonicalVisibleContentDigest(orderedSections);
      if (
        record.orderedParserVersion !== orderedParserVersion
        ||
        !record.visibleContentDigest
        || actualVisibleDigest !== record.visibleContentDigest
      ) {
        throw new Error(
          `${record.orderedFile} does not match its pinned visible-content digest`
        );
      }
    }
    return {
      ...record,
      scores,
      orderedSections,
      observance: parseReferenceObservance(html, record.hour)
    };
  });
}

export function mergeScoredSnapshotDirectories(
  inputRoots: string[],
  outputRoot: string
): ScoredSnapshotRecord[] {
  if (inputRoots.length === 0) {
    throw new Error("At least one scored snapshot directory is required");
  }
  const manifests = inputRoots.map(inputRoot => {
    const root = resolve(inputRoot);
    const manifest = JSON.parse(
      readFileSync(join(root, "snapshot-manifest.json"), "utf8")
    ) as ScoredSnapshotManifest;
    loadScoredSnapshotDirectory(root);
    return { root, manifest };
  });
  const first = manifests[0].manifest;
  if (manifests.some(({ manifest }) =>
    manifest.source !== first.source
    || manifest.purpose !== first.purpose
    || manifest.baseURL !== first.baseURL
    || manifest.rubrics !== first.rubrics
  )) {
    throw new Error("Scored snapshot shards have incompatible source settings");
  }

  const recordsByOffice = new Map<string, {
    root: string;
    record: ScoredSnapshotRecord;
  }>();
  for (const { root, manifest } of manifests) {
    for (const record of manifest.records) {
      const key = `${record.date}:${record.hour}`;
      const existing = recordsByOffice.get(key);
      if (existing && JSON.stringify(existing.record) !== JSON.stringify(record)) {
        throw new Error(`Scored snapshot shards disagree for ${key}`);
      }
      recordsByOffice.set(key, { root, record });
    }
  }

  const root = resolve(outputRoot);
  mkdirSync(root, { recursive: true });
  const records = [...recordsByOffice.values()]
    .sort((left, right) =>
      `${left.record.date}:${left.record.hour}`
        .localeCompare(`${right.record.date}:${right.record.hour}`)
    );
  for (const { root: sourceRoot, record } of records) {
    for (const file of recordFiles(record)) {
      copyFileSync(join(sourceRoot, file), join(root, file));
    }
  }
  const errors = manifests
    .flatMap(({ manifest }) => manifest.errors)
    .sort((left, right) =>
      `${left.date}:${left.hour}`.localeCompare(`${right.date}:${right.hour}`)
    );
  const merged: ScoredSnapshotManifest = {
    source: "Breviarium Gregorianum",
    purpose: "source-concordance",
    baseURL: first.baseURL,
    rubrics: first.rubrics,
    from: manifests.map(({ manifest }) => manifest.from).sort()[0],
    to: manifests.map(({ manifest }) => manifest.to).sort().at(-1)!,
    records: records.map(({ record }) => record),
    errors
  };
  writeManifest(root, merged);
  return merged.records;
}
