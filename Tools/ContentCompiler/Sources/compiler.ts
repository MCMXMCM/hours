import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, statSync, unlinkSync } from "node:fs";
import { dirname } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { encodeContentPayload } from "./contentPayload.ts";
import { parseGABC } from "./gabc.ts";
import { requireApprovedExceptionalMartyrology } from "./exceptionalMartyrology.ts";
import {
  chantNotationModifiers,
  documentFormats,
  eveningContexts,
  liturgicalColors,
  liturgicalRanks,
  officeHours,
  officeSectionKinds,
  reviewStatuses,
  type ChantScore,
  type Coverage,
  type CorpusInput,
  type LocalDay,
  type OfficeDocument,
  type OfficeSection,
  type ScheduledCorpusInput
} from "./types.ts";

const requiredRubrics = "Rubrics 1960 - 1960";
const unresolvedStatuses = new Set(["ambiguous", "missing"]);
const reviewedWindowPreviousYears = 1;
const reviewedWindowFutureYears = 10;
const oneYearPackBudgetBytes = 64 * 1024 * 1024;
const reviewedWindowPackBudgetBytes = 128 * 1024 * 1024;
const parityPackBudgetBytes = 256 * 1024 * 1024;
const reviewedWindowMaximumDays = 4_383;
const compilerSourceFiles = [
  "compiler.ts",
  "compiledCorpus.ts",
  "contentPayload.ts",
  "curatedOfficePromotions.ts",
  "divinumImporter.ts",
  "dynamicOfficeText.ts",
  "eveningContext.ts",
  "exceptionalMartyrology.ts",
  "gabc.ts",
  "inlineRubrics.ts",
  "liturgicalIdentity.ts",
  "perennialCorpus.ts",
  "perennialOrdo.ts",
  "types.ts"
] as const;

export function contentCompilerRevision(): string {
  const revision = process.env.CONTENT_COMPILER_REVISION?.trim();
  if (revision) return revision;

  const hash = createHash("sha256");
  for (const filename of compilerSourceFiles) {
    hash.update(filename);
    hash.update("\0");
    hash.update(readFileSync(new URL(filename, import.meta.url)));
    hash.update("\0");
  }
  return `sha256:${hash.digest("hex")}`;
}

export function dayKey(value: LocalDay): string {
  return `${String(value.year).padStart(4, "0")}-${String(value.month).padStart(2, "0")}-${String(value.day).padStart(2, "0")}`;
}

function isoDate(value: LocalDay, label: string): void {
  const key = dayKey(value);
  const parsed = new Date(`${key}T00:00:00Z`);
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(key)
    || Number.isNaN(parsed.valueOf())
    || parsed.getUTCFullYear() !== value.year
    || parsed.getUTCMonth() + 1 !== value.month
    || parsed.getUTCDate() !== value.day
  ) {
    throw new Error(`${label} must be an ISO civil date`);
  }
}

function validateReviewedReleaseWindow(coverage: Coverage): void {
  const centerYear = coverage.reviewedCenterYear;
  if (!Number.isInteger(centerYear)) {
    throw new Error("Release corpus must record its reviewedCenterYear");
  }
  const start = `${centerYear! - reviewedWindowPreviousYears}-01-01`;
  const end = `${centerYear! + reviewedWindowFutureYears}-12-31`;
  const days = (
    Date.parse(`${end}T00:00:00Z`) - Date.parse(`${start}T00:00:00Z`)
  ) / 86_400_000 + 1;
  const officeCount = days * officeHours.length;
  if (
    dayKey(coverage.startDate) !== start
    || dayKey(coverage.endDate) !== end
    || coverage.expectedOfficeCount !== officeCount
  ) {
    throw new Error(
      `Release corpus centered on ${centerYear} must cover ${start} through `
      + `${end} with ${officeCount} canonical-hour offices`
    );
  }
}

export function loadCorpus(path: string): CorpusInput {
  return JSON.parse(readFileSync(path, "utf8")) as CorpusInput;
}

function assertEnum(
  value: string | null | undefined,
  allowed: readonly string[],
  label: string
): void {
  if (value !== null && value !== undefined && !allowed.includes(value)) {
    throw new Error(`${label} has unknown value "${value}"`);
  }
}

export function canonicalVisibleContentDigest(sections: OfficeSection[]): string {
  const visible = sections.map(section => ({
    kind: section.kind,
    title: section.title,
    latin: section.latin,
    english: section.english ?? null,
    rubric: section.rubric ?? null,
    chant: section.chant
      ? {
        gabc: section.chant.gabc,
        reviewStatus: section.chant.reviewStatus
      }
      : null
  }));
  return createHash("sha256").update(stableJSON(visible)).digest("hex");
}

export function validateCorpus(
  input: CorpusInput,
  allowIncomplete = false,
  validatedScoreObjects?: WeakSet<object>
): string[] {
  const warnings: string[] = [];
  if (![1, 2, 3].includes(input.manifest.schemaVersion)) {
    throw new Error("Unsupported corpus schema");
  }
  if (input.manifest.rubrics !== requiredRubrics) {
    throw new Error(`Corpus must use exactly "${requiredRubrics}"`);
  }
  for (const source of input.manifest.sources) {
    if (
      !source.name.trim()
      || !source.revision.trim()
      || !source.license.trim()
      || !source.url.trim()
      || !source.checksum.trim()
    ) {
      throw new Error("Every corpus source must include provenance, license, revision, URL, and checksum");
    }
    if (
      source.license.startsWith("GPL-")
      && !(source.correspondingSource ?? source.url).trim()
    ) {
      throw new Error(`GPL source ${source.name} lacks a corresponding-source location`);
    }
  }
  isoDate(input.manifest.coverage.startDate, "coverage.startDate");
  isoDate(input.manifest.coverage.endDate, "coverage.endDate");

  const dayDates = new Set<string>();
  for (const day of input.days) {
    isoDate(day.date, "day.date");
    const date = dayKey(day.date);
    if (dayDates.has(date)) throw new Error(`Duplicate day ${date}`);
    dayDates.add(date);
    assertEnum(day.rank, liturgicalRanks, `Day ${date} rank`);
    assertEnum(day.color, liturgicalColors, `Day ${date} color`);
    assertEnum(day.eveningContext, eveningContexts, `Day ${date} eveningContext`);
  }

  const officeKeys = new Set<string>();
  let unresolved = 0;
  let ambiguous = 0;
  for (const office of input.offices) {
    isoDate(office.date, "office.date");
    const date = dayKey(office.date);
    if (!dayDates.has(date)) throw new Error(`Office ${office.id} has no liturgical day`);
    const key = `${date}:${office.hour}`;
    if (officeKeys.has(key)) throw new Error(`Duplicate office ${key}`);
    officeKeys.add(key);
    assertEnum(office.hour, officeHours, `Office ${office.id} hour`);
    assertEnum(office.format, documentFormats, `Office ${office.id} format`);
    if (office.format === "contentUnavailable") {
      if (office.sections.length !== 0) {
        throw new Error(`Unavailable office ${office.id} must not contain prayer text`);
      }
      if (office.visibleContentDigest !== null && office.visibleContentDigest !== undefined) {
        throw new Error(`Unavailable office ${office.id} must not claim a visible-content digest`);
      }
      if (!office.observance?.titleLatin.trim()) {
        throw new Error(`Unavailable office ${office.id} lacks observance metadata`);
      }
    } else if (office.sections.length === 0) {
      throw new Error(`Office ${office.id} has no sections`);
    }
    if (office.observance) {
      assertEnum(office.observance.rank, liturgicalRanks, `Office ${office.id} rank`);
      assertEnum(office.observance.color, liturgicalColors, `Office ${office.id} color`);
      assertEnum(
        office.observance.eveningContext,
        eveningContexts,
        `Office ${office.id} eveningContext`
      );
      if (
        (office.format === "authoritativeOrdered"
          || office.format === "contentUnavailable")
        && (office.hour === "vespers" || office.hour === "compline")
        && !office.observance.eveningContext
      ) {
        throw new Error(
          `Office ${office.id} lacks resolved evening context`
        );
      }
    }

    const sectionIDs = new Set<string>();
    for (const section of office.sections) {
      if (sectionIDs.has(section.id)) throw new Error(`Duplicate section ${section.id}`);
      sectionIDs.add(section.id);
      assertEnum(section.kind, officeSectionKinds, `Section ${section.id} kind`);
      if (!section.latin.trim()) throw new Error(`Section ${section.id} is missing Latin`);
      const score = section.chant;
      if (!score) continue;
      assertEnum(score.reviewStatus, reviewStatuses, `Score ${score.id} reviewStatus`);
      if (unresolvedStatuses.has(score.reviewStatus)) unresolved += 1;
      if (score.reviewStatus === "ambiguous") ambiguous += 1;
      if (!score.provenance.license.trim()) throw new Error(`Score ${score.id} lacks license provenance`);
      if (!score.provenance.sourceBook.trim() || !score.provenance.snapshot.trim()) {
        throw new Error(`Score ${score.id} lacks exact source and snapshot provenance`);
      }
      if (
        score.provenance.license.startsWith("GPL-")
        && !(score.provenance.correspondingSource ?? score.provenance.sourceURL)?.trim()
      ) {
        throw new Error(`GPL score ${score.id} lacks a corresponding-source location`);
      }
      if (!score.gabc.trim()) throw new Error(`Score ${score.id} lacks GABC`);
      if (!validatedScoreObjects?.has(score)) {
        const parsedTimeline = parseGABC(score.gabc, score.id);
        if (score.timeline.events.length > 0) {
          const stored = stableJSON(score.timeline);
          const reparsed = stableJSON(parsedTimeline);
          if (stored !== reparsed) {
            throw new Error(
              `Score ${score.id} has GABC/timeline syllable or neume drift`
            );
          }
        }
        score.timeline = parsedTimeline;
        for (const event of score.timeline.events) {
          for (const modifier of event.modifiers) {
            assertEnum(modifier, chantNotationModifiers, `Score ${score.id} modifier`);
          }
        }
        validatedScoreObjects?.add(score);
      }
    }
    if (office.format === "authoritativeOrdered") {
      const digest = canonicalVisibleContentDigest(office.sections);
      if (office.visibleContentDigest !== digest) {
        throw new Error(
          `Office ${office.id} visible-content digest does not match its ordered blocks`
        );
      }
      if (!office.observance?.titleLatin.trim()) {
        throw new Error(`Office ${office.id} lacks hour-specific observance metadata`);
      }
    }
  }

  if (input.manifest.coverage.generatedOfficeCount !== input.offices.length) {
    throw new Error("Manifest generatedOfficeCount does not match office records");
  }
  if (input.manifest.coverage.unresolvedScoreCount !== unresolved) {
    throw new Error("Manifest unresolvedScoreCount does not match score records");
  }
  if (input.manifest.coverage.ambiguousScoreCount !== ambiguous) {
    throw new Error("Manifest ambiguousScoreCount does not match score records");
  }

  const coverage = input.manifest.coverage;
  const authoritativeOfficeCount = input.offices.filter(
    office => office.format === "authoritativeOrdered"
  ).length;
  if (
    coverage.authoritativeOfficeCount !== null
    && coverage.authoritativeOfficeCount !== undefined
    && coverage.authoritativeOfficeCount !== authoritativeOfficeCount
  ) {
    throw new Error(
      "Manifest authoritativeOfficeCount does not match authoritative documents"
    );
  }
  const expectedDates: string[] = [];
  for (
    const cursor = new Date(`${dayKey(coverage.startDate)}T12:00:00Z`);
    cursor <= new Date(`${dayKey(coverage.endDate)}T12:00:00Z`);
    cursor.setUTCDate(cursor.getUTCDate() + 1)
  ) {
    expectedDates.push(cursor.toISOString().slice(0, 10));
  }
  const missingDates = expectedDates.filter(date => !dayDates.has(date));
  if (missingDates.length > 0) {
    throw new Error(`Corpus has non-consecutive date coverage; first missing day ${missingDates[0]}`);
  }
  if (!allowIncomplete) {
    for (const date of expectedDates) {
      const missingHour = officeHours.find(hour => !officeKeys.has(`${date}:${hour}`));
      if (missingHour) {
        throw new Error(`Corpus is missing ${date}:${missingHour}`);
      }
    }
  }
  if (!coverage.isSample) {
    validateReviewedReleaseWindow(coverage);
    requireApprovedExceptionalMartyrology();
  }
  const incomplete =
    coverage.isSample ||
    coverage.generatedOfficeCount !== coverage.expectedOfficeCount ||
    (coverage.authoritativeOfficeCount ?? 0) !== coverage.expectedOfficeCount ||
    unresolved > 0 ||
    ambiguous > 0;
  if (incomplete && !allowIncomplete) {
    throw new Error("Release corpus gate failed: coverage is incomplete or contains unresolved chant");
  }
  if (coverage.isSample) warnings.push("Development sample: not an authoritative release corpus");
  if ((coverage.authoritativeOfficeCount ?? 0) !== coverage.expectedOfficeCount) {
    warnings.push(
      `${coverage.expectedOfficeCount - (coverage.authoritativeOfficeCount ?? 0)} `
      + "offices are not authoritative ordered documents"
    );
  }
  if (unresolved > 0) warnings.push(`${unresolved} scores require human resolution`);
  return warnings;
}

function stableJSON(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map(item => item === undefined ? "null" : stableJSON(item)).join(",")}]`;
  }
  if (value && typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>)
      .filter(([, item]) => item !== undefined)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([key, item]) => `${JSON.stringify(key)}:${stableJSON(item)}`);
    return `{${entries.join(",")}}`;
  }
  return JSON.stringify(value) ?? "null";
}

const scoreIDs = new WeakMap<object, string>();

function scoreID(score: ChantScore): string {
  const cached = scoreIDs.get(score);
  if (cached) return cached;
  const value = createHash("sha256").update(stableJSON(score)).digest("hex");
  scoreIDs.set(score, value);
  return value;
}

type NormalizedTextResource = Omit<OfficeSection, "id" | "chant">;

function textResource(section: OfficeSection): NormalizedTextResource {
  const { id: _id, chant: _chant, ...resource } = section;
  return resource;
}

function textResourceID(section: OfficeSection): string {
  return createHash("sha256")
    .update(stableJSON(textResource(section)))
    .digest("hex");
}

function latinSearchText(value: string): string {
  return value
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .replace(/æ/gi, match => match === "Æ" ? "AE" : "ae")
    .replace(/œ/gi, match => match === "Œ" ? "OE" : "oe")
    .replace(/j/gi, match => match === "J" ? "I" : "i")
    .toLowerCase();
}

function recipeHeader(office: OfficeDocument): Omit<OfficeDocument, "id" | "date" | "sections"> {
  const { id: _id, date: _date, sections: _sections, ...header } = office;
  return header;
}

function recipeReferences(office: OfficeDocument): Array<{
  textID: string;
  scoreID: string | null;
}> {
  return office.sections.map(section => ({
    textID: textResourceID(section),
    scoreID: section.chant ? scoreID(section.chant) : null
  }));
}

function recipeID(office: OfficeDocument): string {
  return createHash("sha256")
    .update(stableJSON({
      header: recipeHeader(office),
      sections: recipeReferences(office)
    }))
    .digest("hex");
}

function compactScoreForStorage(score: ChantScore): unknown {
  return {
    ...score,
    timeline: {
      events: score.timeline.events.map(event => ({
        i: event.id,
        p: event.phraseID,
        y: event.syllableID,
        s: event.syllable,
        n: event.relativePitch,
        d: event.durationWeight,
        m: event.modifiers,
        c: event.clef
          ? {
            k: event.clef.kind,
            l: event.clef.line,
            b: event.clef.flattensB
          }
          : null
      }))
    }
  };
}

export function compileCorpus(input: CorpusInput, output: string, allowIncomplete = false): string[] {
  const warnings = validateCorpus(input, allowIncomplete);
  const recipes = new Map<string, OfficeDocument>();
  const schedule: Array<{ date: LocalDay; hour: OfficeDocument["hour"]; recipeKey: string }> = [];
  for (const office of input.offices) {
    const key = recipeID(office);
    recipes.set(key, office);
    schedule.push({ date: office.date, hour: office.hour, recipeKey: key });
  }
  writeNormalizedCorpus({
    manifest: input.manifest,
    days: input.days,
    recipes,
    schedule
  }, output);
  return warnings;
}

function validateScheduledCorpus(
  input: ScheduledCorpusInput,
  allowIncomplete: boolean
): string[] {
  const recipeKeys = new Set<string>();
  const recipes = new Map<string, OfficeDocument>();
  for (const recipe of input.recipes) {
    if (!recipe.key.trim()) throw new Error("Scheduled corpus has an empty recipe key");
    if (recipeKeys.has(recipe.key)) {
      throw new Error(`Scheduled corpus has duplicate recipe key ${recipe.key}`);
    }
    recipeKeys.add(recipe.key);
    recipes.set(recipe.key, recipe.office);
  }

  const daysByDate = new Map(input.days.map(day => [dayKey(day.date), day]));
  const scheduleKeys = new Set<string>();
  let unresolved = 0;
  let ambiguous = 0;
  let authoritative = 0;
  const recipeCounts = new Map([...recipes].map(([key, office]) => [key, {
    unresolved: office.sections.filter(section =>
      section.chant && unresolvedStatuses.has(section.chant.reviewStatus)
    ).length,
    ambiguous: office.sections.filter(section =>
      section.chant?.reviewStatus === "ambiguous"
    ).length,
    authoritative: office.format === "authoritativeOrdered"
  }]));
  for (const item of input.schedule) {
    isoDate(item.date, "schedule.date");
    assertEnum(item.hour, officeHours, `Schedule ${dayKey(item.date)} hour`);
    const date = dayKey(item.date);
    if (!daysByDate.has(date)) {
      throw new Error(`Scheduled office ${date}:${item.hour} has no liturgical day`);
    }
    const key = `${date}:${item.hour}`;
    if (scheduleKeys.has(key)) throw new Error(`Duplicate scheduled office ${key}`);
    scheduleKeys.add(key);
    const office = recipes.get(item.recipeKey);
    if (!office) throw new Error(`Scheduled office ${key} references missing recipe ${item.recipeKey}`);
    if (office.hour !== item.hour) {
      throw new Error(`Scheduled office ${key} references a ${office.hour} recipe`);
    }
    const counts = recipeCounts.get(item.recipeKey)!;
    if (counts.authoritative) authoritative += 1;
    unresolved += counts.unresolved;
    ambiguous += counts.ambiguous;
  }

  const coverage = input.manifest.coverage;
  if (coverage.generatedOfficeCount !== input.schedule.length) {
    throw new Error("Manifest generatedOfficeCount does not match scheduled offices");
  }
  if (coverage.unresolvedScoreCount !== unresolved) {
    throw new Error("Manifest unresolvedScoreCount does not match scheduled score uses");
  }
  if (coverage.ambiguousScoreCount !== ambiguous) {
    throw new Error("Manifest ambiguousScoreCount does not match scheduled score uses");
  }
  if (
    coverage.authoritativeOfficeCount !== null
    && coverage.authoritativeOfficeCount !== undefined
    && coverage.authoritativeOfficeCount !== authoritative
  ) {
    throw new Error("Manifest authoritativeOfficeCount does not match scheduled documents");
  }

  // Reuse the ordinary document validator once per unique recipe. The
  // representative date is real, but it is deliberately independent of the
  // many dates that will later reference the same immutable recipe.
  const validatedScores = new WeakSet<object>();
  for (const office of recipes.values()) {
    const representativeDay = daysByDate.get(dayKey(office.date));
    if (!representativeDay) {
      throw new Error(`Recipe representative ${office.id} has no liturgical day`);
    }
    const recipeInput: CorpusInput = {
      manifest: {
        ...input.manifest,
        coverage: {
          startDate: office.date,
          endDate: office.date,
          expectedOfficeCount: 1,
          generatedOfficeCount: 1,
          authoritativeOfficeCount: office.format === "authoritativeOrdered" ? 1 : 0,
          unresolvedScoreCount: office.sections.filter(section =>
            section.chant && unresolvedStatuses.has(section.chant.reviewStatus)
          ).length,
          ambiguousScoreCount: office.sections.filter(section =>
            section.chant?.reviewStatus === "ambiguous"
          ).length,
          isSample: true
        }
      },
      days: [representativeDay],
      offices: [office]
    };
    validateCorpus(recipeInput, true, validatedScores);
  }

  const expectedDates: string[] = [];
  for (
    const cursor = new Date(`${dayKey(coverage.startDate)}T12:00:00Z`);
    cursor <= new Date(`${dayKey(coverage.endDate)}T12:00:00Z`);
    cursor.setUTCDate(cursor.getUTCDate() + 1)
  ) {
    expectedDates.push(cursor.toISOString().slice(0, 10));
  }
  for (const date of expectedDates) {
    if (!daysByDate.has(date)) throw new Error(`Corpus is missing liturgical day ${date}`);
    if (!allowIncomplete) {
      const missingHour = officeHours.find(hour => !scheduleKeys.has(`${date}:${hour}`));
      if (missingHour) throw new Error(`Corpus is missing ${date}:${missingHour}`);
    }
  }
  if (!coverage.isSample) {
    validateReviewedReleaseWindow(coverage);
    requireApprovedExceptionalMartyrology();
  }
  const incomplete = coverage.isSample
    || input.schedule.length !== coverage.expectedOfficeCount
    || authoritative !== coverage.expectedOfficeCount
    || unresolved > 0
    || ambiguous > 0;
  if (incomplete && !allowIncomplete) {
    throw new Error("Release corpus gate failed: coverage is incomplete or contains unresolved chant");
  }
  const warnings: string[] = [];
  if (coverage.isSample) warnings.push("Development sample: not an authoritative release corpus");
  if (authoritative !== coverage.expectedOfficeCount) {
    warnings.push(`${coverage.expectedOfficeCount - authoritative} offices are not authoritative ordered documents`);
  }
  if (unresolved > 0) warnings.push(`${unresolved} scores require human resolution`);
  return warnings;
}

export function compileScheduledCorpus(
  input: ScheduledCorpusInput,
  output: string,
  allowIncomplete = false
): string[] {
  const warnings = validateScheduledCorpus(input, allowIncomplete);
  writeNormalizedCorpus({
    manifest: input.manifest,
    days: input.days,
    recipes: new Map(input.recipes.map(recipe => [recipe.key, recipe.office])),
    schedule: input.schedule
  }, output);
  return warnings;
}

function writeNormalizedCorpus(input: {
  manifest: ScheduledCorpusInput["manifest"];
  days: ScheduledCorpusInput["days"];
  recipes: Map<string, OfficeDocument>;
  schedule: ScheduledCorpusInput["schedule"];
}, output: string): void {
  const textsByKey = new Map<string, NormalizedTextResource>();
  const scoresByKey = new Map<string, ChantScore>();
  const incipitsByTextKey = new Map<string, Set<string>>();
  const recipesByKey = input.recipes;
  for (const office of recipesByKey.values()) {
    for (const section of office.sections) {
      const textKey = textResourceID(section);
      textsByKey.set(textKey, textResource(section));
      if (section.chant) {
        scoresByKey.set(scoreID(section.chant), section.chant);
        const incipits = incipitsByTextKey.get(textKey) ?? new Set<string>();
        if (section.chant.incipit.trim()) incipits.add(section.chant.incipit.trim());
        incipitsByTextKey.set(textKey, incipits);
      }
    }
  }
  const textNumberByKey = new Map(
    [...textsByKey.keys()].sort().map((key, index) => [key, index + 1])
  );
  const scoreNumberByKey = new Map(
    [...scoresByKey.keys()].sort().map((key, index) => [key, index + 1])
  );
  const recipeNumberByKey = new Map(
    [...recipesByKey.keys()].sort().map((key, index) => [key, index + 1])
  );
  const manifest = {
    ...input.manifest,
    schemaVersion: 3,
    compilerRevision: contentCompilerRevision(),
    normalizedCounts: {
      textResources: textsByKey.size,
      scoredChantRealizations: scoresByKey.size,
      recipes: recipesByKey.size,
      scheduledOffices: input.schedule.length
    },
    notices: [...new Set([
      ...(input.manifest.notices ?? []),
      ...input.manifest.sources.flatMap(source => source.notice ? [source.notice] : [])
    ])]
  };
  mkdirSync(dirname(output), { recursive: true });
  try { unlinkSync(output); } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
  }

  const db = new DatabaseSync(output);
  db.exec(`
    PRAGMA journal_mode = DELETE;
    PRAGMA synchronous = FULL;
    PRAGMA foreign_keys = ON;
    CREATE TABLE meta (
      key TEXT PRIMARY KEY NOT NULL,
      value TEXT NOT NULL
    ) WITHOUT ROWID;
    CREATE TABLE days (
      date TEXT PRIMARY KEY NOT NULL,
      payload BLOB NOT NULL
    ) WITHOUT ROWID;
    CREATE TABLE text_resources (
      id INTEGER PRIMARY KEY NOT NULL,
      stable_key TEXT UNIQUE NOT NULL,
      kind TEXT NOT NULL,
      incipits_latin TEXT NOT NULL,
      payload BLOB NOT NULL
    );
    CREATE VIRTUAL TABLE text_fts USING fts5(
      incipits_latin,
      title_latin,
      title_english,
      rubric_latin,
      rubric_english,
      latin,
      english,
      content='',
      tokenize='unicode61 remove_diacritics 2'
    );
    CREATE TABLE scores (
      id INTEGER PRIMARY KEY NOT NULL,
      stable_key TEXT UNIQUE NOT NULL,
      payload BLOB NOT NULL
    );
    CREATE TABLE recipes (
      id INTEGER PRIMARY KEY NOT NULL,
      stable_key TEXT UNIQUE NOT NULL,
      payload BLOB NOT NULL
    );
    CREATE TABLE recipe_sections (
      recipe_id INTEGER NOT NULL REFERENCES recipes(id),
      position INTEGER NOT NULL,
      text_id INTEGER NOT NULL REFERENCES text_resources(id),
      score_id INTEGER REFERENCES scores(id),
      PRIMARY KEY(recipe_id, position)
    ) WITHOUT ROWID;
    CREATE TABLE office_schedule (
      date TEXT NOT NULL,
      hour TEXT NOT NULL CHECK(hour IN (
        'matins', 'lauds', 'prime', 'terce', 'sext', 'none', 'vespers', 'compline'
      )),
      recipe_id INTEGER NOT NULL REFERENCES recipes(id),
      PRIMARY KEY(date, hour)
    ) WITHOUT ROWID;
    CREATE TABLE text_scores (
      text_id INTEGER NOT NULL REFERENCES text_resources(id),
      score_id INTEGER NOT NULL REFERENCES scores(id),
      PRIMARY KEY(text_id, score_id)
    ) WITHOUT ROWID;
    CREATE TABLE text_recipes (
      text_id INTEGER NOT NULL REFERENCES text_resources(id),
      recipe_id INTEGER NOT NULL REFERENCES recipes(id),
      PRIMARY KEY(text_id, recipe_id)
    ) WITHOUT ROWID;
    CREATE TABLE widget_calendar (
      date TEXT PRIMARY KEY NOT NULL,
      title_latin TEXT NOT NULL,
      rank TEXT
    ) WITHOUT ROWID;
    CREATE INDEX office_recipe_index ON office_schedule(recipe_id);
  `);

  const insertMeta = db.prepare("INSERT INTO meta(key, value) VALUES (?, ?)");
  const insertDay = db.prepare("INSERT INTO days(date, payload) VALUES (?, ?)");
  const insertText = db.prepare(`
    INSERT INTO text_resources(id, stable_key, kind, incipits_latin, payload)
    VALUES (?, ?, ?, ?, ?)
  `);
  const insertSearchText = db.prepare(`
    INSERT INTO text_fts(
      rowid, incipits_latin, title_latin, title_english,
      rubric_latin, rubric_english, latin, english
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `);
  const insertScore = db.prepare("INSERT INTO scores(id, stable_key, payload) VALUES (?, ?, ?)");
  const insertRecipe = db.prepare("INSERT INTO recipes(id, stable_key, payload) VALUES (?, ?, ?)");
  const insertRecipeSection = db.prepare(`
    INSERT INTO recipe_sections(recipe_id, position, text_id, score_id)
    VALUES (?, ?, ?, ?)
  `);
  const insertTextScore = db.prepare(`
    INSERT OR IGNORE INTO text_scores(text_id, score_id) VALUES (?, ?)
  `);
  const insertTextRecipe = db.prepare(`
    INSERT OR IGNORE INTO text_recipes(text_id, recipe_id) VALUES (?, ?)
  `);
  const insertSchedule = db.prepare(`
    INSERT INTO office_schedule(date, hour, recipe_id) VALUES (?, ?, ?)
  `);
  const insertWidgetDay = db.prepare(`
    INSERT INTO widget_calendar(date, title_latin, rank) VALUES (?, ?, ?)
  `);
  db.exec("BEGIN IMMEDIATE");
  let committed = false;
  try {
    insertMeta.run("manifest", stableJSON(manifest));
    insertMeta.run("rubrics", input.manifest.rubrics);
    for (const day of input.days) {
      insertDay.run(dayKey(day.date), encodeContentPayload(stableJSON(day)));
      insertWidgetDay.run(dayKey(day.date), day.titleLatin, day.rank ?? null);
    }
    for (const [key, resource] of [...textsByKey.entries()].sort(([a], [b]) => a.localeCompare(b))) {
      const id = textNumberByKey.get(key)!;
      const incipits = [...(incipitsByTextKey.get(key) ?? [])].toSorted().join("\n");
      insertText.run(id, key, resource.kind, incipits, encodeContentPayload(stableJSON(resource)));
      insertSearchText.run(
        id,
        latinSearchText(incipits),
        latinSearchText(resource.title),
        resource.titleEnglish ?? null,
        resource.rubric ? latinSearchText(resource.rubric) : null,
        resource.rubricEnglish ?? null,
        latinSearchText(resource.latin),
        resource.english ?? null
      );
    }
    for (const [key, score] of [...scoresByKey.entries()].sort(([a], [b]) => a.localeCompare(b))) {
      insertScore.run(
        scoreNumberByKey.get(key)!,
        key,
        encodeContentPayload(stableJSON(compactScoreForStorage(score)))
      );
    }
    for (const [key, office] of [...recipesByKey.entries()].sort(([a], [b]) => a.localeCompare(b))) {
      const id = recipeNumberByKey.get(key)!;
      insertRecipe.run(
        id,
        key,
        encodeContentPayload(stableJSON(recipeHeader(office)))
      );
      for (const [position, section] of office.sections.entries()) {
        const textID = textNumberByKey.get(textResourceID(section))!;
        const storedScoreID = section.chant
          ? scoreNumberByKey.get(scoreID(section.chant))!
          : null;
        insertRecipeSection.run(id, position, textID, storedScoreID);
        insertTextRecipe.run(textID, id);
        if (storedScoreID !== null) insertTextScore.run(textID, storedScoreID);
      }
    }
    for (const item of input.schedule) {
      insertSchedule.run(
        dayKey(item.date),
        item.hour,
        recipeNumberByKey.get(item.recipeKey)!
      );
    }
    db.exec("COMMIT");
    committed = true;
    db.exec("INSERT INTO text_fts(text_fts) VALUES('optimize'); ANALYZE; VACUUM");
  } catch (error) {
    if (!committed) db.exec("ROLLBACK");
    throw error;
  } finally {
    db.close();
  }
  const outputBytes = statSync(output).size;
  const coverageDays = Math.round(
    (new Date(`${dayKey(input.manifest.coverage.endDate)}T12:00:00Z`).valueOf()
      - new Date(`${dayKey(input.manifest.coverage.startDate)}T12:00:00Z`).valueOf())
      / 86_400_000
  ) + 1;
  const budget = coverageDays <= 366
    ? oneYearPackBudgetBytes
    : coverageDays <= reviewedWindowMaximumDays
      ? reviewedWindowPackBudgetBytes
      : parityPackBudgetBytes;
  if (outputBytes > budget) {
    unlinkSync(output);
    throw new Error(
      `Corpus is ${outputBytes} bytes and exceeds the ${budget}-byte pack-size budget`
    );
  }
}
