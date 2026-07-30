import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, statSync, unlinkSync } from "node:fs";
import { dirname } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { encodeContentPayload } from "./contentPayload.ts";
import { parseGABC } from "./gabc.ts";
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
  type CorpusInput,
  type LocalDay,
  type OfficeDocument,
  type OfficeSection
} from "./types.ts";

const requiredRubrics = "Rubrics 1960 - 1960";
const unresolvedStatuses = new Set(["ambiguous", "missing"]);
const releaseStart = "1962-01-01";
const releaseEnd = "2100-12-31";
const releaseOfficeCount = 406_152;
const development2026PackBudgetBytes = 256 * 1024 * 1024;

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

export function validateCorpus(input: CorpusInput, allowIncomplete = false): string[] {
  const warnings: string[] = [];
  if (input.manifest.schemaVersion !== 1) throw new Error("Unsupported corpus schema");
  if (input.manifest.rubrics !== requiredRubrics) {
    throw new Error(`Corpus must use exactly "${requiredRubrics}"`);
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
      if (!score.gabc.trim()) throw new Error(`Score ${score.id} lacks GABC`);
      score.timeline = parseGABC(score.gabc, score.id);
      for (const event of score.timeline.events) {
        for (const modifier of event.modifiers) {
          assertEnum(modifier, chantNotationModifiers, `Score ${score.id} modifier`);
        }
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
    if (
      dayKey(coverage.startDate) !== releaseStart
      || dayKey(coverage.endDate) !== releaseEnd
      || coverage.expectedOfficeCount !== releaseOfficeCount
    ) {
      throw new Error(
        `Release corpus must cover ${releaseStart} through ${releaseEnd} with ${releaseOfficeCount} canonical-hour offices`
      );
    }
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

function scoreID(score: ChantScore): string {
  return createHash("sha256").update(stableJSON(score)).digest("hex");
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

function storedOffice(office: OfficeDocument): OfficeDocument & {
  sections: Array<OfficeDocument["sections"][number] & { scoreID?: string | null }>;
} {
  return {
    ...office,
    sections: office.sections.map(section => ({
      ...section,
      chant: null,
      scoreID: section.chant ? scoreID(section.chant) : null
    }))
  };
}

function templateFor(office: ReturnType<typeof storedOffice>): Omit<OfficeDocument, "date" | "id"> {
  const { date: _, id: __, ...template } = office;
  return template;
}

export function compileCorpus(input: CorpusInput, output: string, allowIncomplete = false): string[] {
  const warnings = validateCorpus(input, allowIncomplete);
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
    CREATE TABLE documents (
      id TEXT PRIMARY KEY NOT NULL,
      payload BLOB NOT NULL
    ) WITHOUT ROWID;
    CREATE TABLE scores (
      id TEXT PRIMARY KEY NOT NULL,
      payload BLOB NOT NULL
    ) WITHOUT ROWID;
    CREATE TABLE section_scores (
      document_id TEXT NOT NULL REFERENCES documents(id),
      section_id TEXT NOT NULL,
      score_id TEXT NOT NULL REFERENCES scores(id),
      PRIMARY KEY(document_id, section_id)
    ) WITHOUT ROWID;
    CREATE TABLE office_index (
      date TEXT NOT NULL,
      hour TEXT NOT NULL CHECK(hour IN (
        'matins', 'lauds', 'prime', 'terce', 'sext', 'none', 'vespers', 'compline'
      )),
      document_id TEXT NOT NULL REFERENCES documents(id),
      PRIMARY KEY(date, hour)
    ) WITHOUT ROWID;
    CREATE INDEX office_document_index ON office_index(document_id);
    CREATE INDEX section_score_score_index ON section_scores(score_id);
  `);

  const insertMeta = db.prepare("INSERT INTO meta(key, value) VALUES (?, ?)");
  const insertDay = db.prepare("INSERT INTO days(date, payload) VALUES (?, ?)");
  const insertDocument = db.prepare("INSERT OR IGNORE INTO documents(id, payload) VALUES (?, ?)");
  const insertScore = db.prepare("INSERT OR IGNORE INTO scores(id, payload) VALUES (?, ?)");
  const insertSectionScore = db.prepare(`
    INSERT OR IGNORE INTO section_scores(document_id, section_id, score_id)
    VALUES (?, ?, ?)
  `);
  const insertIndex = db.prepare("INSERT INTO office_index(date, hour, document_id) VALUES (?, ?, ?)");
  db.exec("BEGIN IMMEDIATE");
  try {
    insertMeta.run("manifest", stableJSON(input.manifest));
    insertMeta.run("rubrics", input.manifest.rubrics);
    for (const day of input.days) {
      insertDay.run(dayKey(day.date), encodeContentPayload(stableJSON(day)));
    }
    for (const office of input.offices) {
      const stored = storedOffice(office);
      const canonical = stableJSON(templateFor(stored));
      const documentID = createHash("sha256").update(canonical).digest("hex");
      const payload = stableJSON({ ...stored, id: documentID });
      insertDocument.run(documentID, encodeContentPayload(payload));
      for (const section of office.sections) {
        if (!section.chant) continue;
        const id = scoreID(section.chant);
        insertScore.run(
          id,
          encodeContentPayload(stableJSON(compactScoreForStorage(section.chant)))
        );
        insertSectionScore.run(documentID, section.id, id);
      }
      insertIndex.run(dayKey(office.date), office.hour, documentID);
    }
    db.exec("COMMIT");
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  } finally {
    db.close();
  }
  const outputBytes = statSync(output).size;
  if (
    dayKey(input.manifest.coverage.startDate) === "2026-01-01"
    && dayKey(input.manifest.coverage.endDate) === "2026-12-31"
    && outputBytes > development2026PackBudgetBytes
  ) {
    unlinkSync(output);
    throw new Error(
      `2026 corpus is ${outputBytes} bytes and exceeds the `
      + `${development2026PackBudgetBytes}-byte pack-size budget`
    );
  }
  return warnings;
}
