import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { mkdirSync, readFileSync, statSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { promisify } from "node:util";
import { DatabaseSync } from "node:sqlite";
import { loadCompiledCorpus } from "./compiledCorpus.ts";
import {
  canonicalVisibleContentDigest,
  compileScheduledCorpus,
  dayKey
} from "./compiler.ts";
import { decodeContentPayload, encodeContentPayload } from "./contentPayload.ts";
import { curatedPromotionChecksum } from "./curatedOfficePromotions.ts";
import { normalizeDynamicOfficeText } from "./dynamicOfficeText.ts";
import { withResolvedEveningContexts } from "./eveningContext.ts";
import { exceptionalMartyrologyReview } from "./exceptionalMartyrology.ts";
import {
  parseDivinumOffice,
  loadSnapshotDirectory,
  classifyImportedSection,
  normalizeImportedOfficeCandidate,
  type ImportedOfficeCandidate
} from "./divinumImporter.ts";
import {
  officeConfigurationKey,
  perennialOrdoRange,
  uniqueOfficeConfigurations,
  type PerennialOrdoRange,
  type PerennialOrdoSchedule
} from "./perennialOrdo.ts";
import {
  officeHours,
  type CorpusInput,
  type LiturgicalDay,
  type LiturgicalRank,
  type LocalDay,
  type OfficeDocument,
  type OfficeHour,
  type OfficeSection,
  type OfficeSectionKind,
  type ScheduledCorpusInput
} from "./types.ts";

const execFileAsync = promisify(execFile);

const commandByHour: Record<OfficeHour, string> = {
  matins: "prayMatutinum",
  lauds: "prayLaudes",
  prime: "prayPrima",
  terce: "prayTertia",
  sext: "praySexta",
  none: "prayNona",
  vespers: "prayVespera",
  compline: "prayCompletorium"
};

const titles: Record<OfficeHour, { latin: string; english: string }> = {
  matins: { latin: "Ad Matutinum", english: "Matins" },
  lauds: { latin: "Ad Laudes", english: "Lauds" },
  prime: { latin: "Ad Primam", english: "Prime" },
  terce: { latin: "Ad Tertiam", english: "Terce" },
  sext: { latin: "Ad Sextam", english: "Sext" },
  none: { latin: "Ad Nonam", english: "None" },
  vespers: { latin: "Ad Vesperas", english: "Vespers" },
  compline: { latin: "Ad Completorium", english: "Compline" }
};

function localDay(value: string): LocalDay {
  const [year, month, day] = value.split("-").map(Number);
  return { year, month, day };
}

function normalizedLatin(value: string): string {
  return value
    .replace(/[æǽ]/gi, "ae")
    .replace(/œ/gi, "oe")
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase()
    .replace(/j/g, "i")
    .replace(/v/g, "u")
    .replace(/\b\d+\b/g, " ")
    .replace(/[^\p{Letter}\p{Number}]+/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function sourceRowKey(
  hour: OfficeHour,
  section: ImportedOfficeCandidate["sections"][number]
): string {
  return `${hour}\u001f${normalizedLatin([
    section.titleLatin,
    section.rubricLatin ?? "",
    section.latin
  ].join("\n"))}`;
}

function sourceOfficeKey(office: ImportedOfficeCandidate): string {
  return createHash("sha256")
    .update(office.hour)
    .update("\u001f")
    .update(office.sections.map(section => sourceRowKey(office.hour, section)).join("\u001e"))
    .digest("hex");
}

const scoreRecipeFingerprints = new WeakMap<object, string>();

function scoreRecipeFingerprint(score: NonNullable<OfficeSection["chant"]>): string {
  const cached = scoreRecipeFingerprints.get(score);
  if (cached) return cached;
  const value = [
    score.id,
    createHash("sha256").update(score.gabc).digest("hex"),
    score.provenance.snapshot
  ].join(":");
  scoreRecipeFingerprints.set(score, value);
  return value;
}

function stableRecipeKey(office: OfficeDocument): string {
  return createHash("sha256").update(JSON.stringify({
    hour: office.hour,
    titleLatin: office.titleLatin,
    titleEnglish: office.titleEnglish,
    contextLabel: office.contextLabel,
    sourceVersion: office.sourceVersion,
    format: office.format,
    observance: office.observance,
    sections: office.sections.map(section => ({
      kind: section.kind,
      title: section.title,
      titleEnglish: section.titleEnglish,
      rubric: section.rubric,
      rubricEnglish: section.rubricEnglish,
      latin: section.latin,
      english: section.english,
      chant: section.chant ? scoreRecipeFingerprint(section.chant) : null
    }))
  })).digest("hex");
}

function rank(value: string): LiturgicalRank | null {
  if (/\bI\.\s*classis\b/i.test(value)) return "firstClass";
  if (/\bII\.\s*classis\b/i.test(value)) return "secondClass";
  if (/\bIII\.\s*classis\b/i.test(value)) return "thirdClass";
  if (/\bIV\.\s*classis\b/i.test(value)) return "fourthClass";
  return null;
}

function stableID(value: string): string {
  return normalizedLatin(value).replace(/\s+/g, "-") || "office";
}

function sectionKind(
  section: ImportedOfficeCandidate["sections"][number]
): OfficeSectionKind {
  return classifyImportedSection(section);
}

interface CatalogVariant {
  date: string;
  observance: string;
  rank: string;
  season: string;
  weekday: number;
  rowIndex: number;
  sections: OfficeSection[];
}

interface ReusableCatalog {
  rows: Map<string, CatalogVariant[]>;
  offices: Map<string, Array<{ candidate: ImportedOfficeCandidate; office: OfficeDocument }>>;
  observanceTitles: Map<string, string>;
}

function weekday(date: string): number {
  return new Date(`${date}T12:00:00Z`).getUTCDay();
}

function catalogFrom2026(options: {
  database: string;
  divinumSnapshots: string;
}): ReusableCatalog {
  const source = loadSnapshotDirectory(options.divinumSnapshots).offices;
  const corpus = loadCompiledCorpus(options.database);
  const documents = new Map(corpus.offices.map(office => [office.id, office]));
  const rows = new Map<string, CatalogVariant[]>();
  const observanceTitles = new Map<string, string>();
  const offices = new Map<
    string,
    Array<{ candidate: ImportedOfficeCandidate; office: OfficeDocument }>
  >();

  for (const candidate of source) {
    const office = documents.get(`${candidate.date}-${candidate.hour}`);
    if (!office || office.format !== "authoritativeOrdered") continue;
    const observanceTitleEnglish = office.observance?.titleEnglish?.trim();
    if (observanceTitleEnglish) {
      observanceTitles.set(
        normalizedLatin(candidate.observanceLatin),
        observanceTitleEnglish
      );
    }
    const completeKey = sourceOfficeKey(candidate);
    const complete = offices.get(completeKey) ?? [];
    complete.push({ candidate, office });
    offices.set(completeKey, complete);

    const grouped = candidate.sections.map(() => [] as OfficeSection[]);
    let currentRow = 0;
    for (const section of office.sections) {
      const text = normalizedLatin(section.latin);
      let matchedRow = -1;
      if (text.length > 2) {
        for (let index = currentRow; index < candidate.sections.length; index += 1) {
          if (normalizedLatin(candidate.sections[index].latin).includes(text)) {
            matchedRow = index;
            break;
          }
        }
        if (matchedRow < 0) {
          matchedRow = candidate.sections.findIndex(sourceSection =>
            normalizedLatin(sourceSection.latin).includes(text)
          );
        }
      }
      if (matchedRow >= 0) currentRow = matchedRow;
      grouped[Math.min(currentRow, grouped.length - 1)].push(section);
    }

    for (const [rowIndex, sections] of grouped.entries()) {
      if (sections.length === 0) continue;
      const key = sourceRowKey(candidate.hour, candidate.sections[rowIndex]);
      const variants = rows.get(key) ?? [];
      variants.push({
        date: candidate.date,
        observance: normalizedLatin(candidate.observanceLatin),
        rank: normalizedLatin(candidate.rankLatin),
        season: normalizedLatin(candidate.seasonLatin),
        weekday: weekday(candidate.date),
        rowIndex,
        sections
      });
      rows.set(key, variants);
    }
  }
  return { rows, offices, observanceTitles };
}

function variantScore(
  variant: CatalogVariant,
  candidate: ImportedOfficeCandidate,
  rowIndex: number
): number {
  let score = 0;
  if (variant.observance === normalizedLatin(candidate.observanceLatin)) score += 10_000;
  if (variant.rank === normalizedLatin(candidate.rankLatin)) score += 500;
  if (variant.season === normalizedLatin(candidate.seasonLatin)) score += 250;
  if (variant.weekday === weekday(candidate.date)) score += 100;
  if (variant.rowIndex === rowIndex) score += 25;
  return score;
}

function plainSection(
  source: ImportedOfficeCandidate["sections"][number],
  index: number
): OfficeSection {
  return {
    id: `source-${index}`,
    kind: sectionKind(source),
    title: source.titleLatin,
    titleEnglish: source.titleEnglish || null,
    rubric: source.rubricLatin ?? null,
    rubricEnglish: source.rubricEnglish ?? null,
    latin: source.latin,
    english: source.english || null,
    chant: null
  };
}

function isUnreviewedPrimeChapterConclusion(
  hour: OfficeHour,
  source: ImportedOfficeCandidate["sections"][number]
): boolean {
  if (hour !== "prime" || normalizedLatin(source.titleLatin) !== "conclusio") {
    return false;
  }
  const latin = normalizedLatin(source.latin);
  return latin.includes("adiutorium nostrum in nomine domini")
    && latin.includes("benedicite")
    && latin.includes("dominus nos benedicat");
}

function assembledSections(
  candidate: ImportedOfficeCandidate,
  catalog: ReusableCatalog
): OfficeSection[] {
  const exact = catalog.offices.get(sourceOfficeKey(candidate));
  if (exact?.length) {
    const selected = exact.toSorted((left, right) =>
      variantScore({
        date: left.candidate.date,
        observance: normalizedLatin(left.candidate.observanceLatin),
        rank: normalizedLatin(left.candidate.rankLatin),
        season: normalizedLatin(left.candidate.seasonLatin),
        weekday: weekday(left.candidate.date),
        rowIndex: 0,
        sections: left.office.sections
      }, candidate, 0) < variantScore({
        date: right.candidate.date,
        observance: normalizedLatin(right.candidate.observanceLatin),
        rank: normalizedLatin(right.candidate.rankLatin),
        season: normalizedLatin(right.candidate.seasonLatin),
        weekday: weekday(right.candidate.date),
        rowIndex: 0,
        sections: right.office.sections
      }, candidate, 0) ? 1 : -1
    )[0];
    return selected.office.sections.map((section, index) => ({
      ...section,
      id: `section-${index}`
    }));
  }

  const result: OfficeSection[] = [];
  for (const [rowIndex, source] of candidate.sections.entries()) {
    // The reviewed ordered office ends Prime with its two scored Conclusio
    // blocks. The reusable Divinum candidate also carries an unscored
    // chapter-office appendage beginning "Adiutórium nostrum". It has no
    // reviewed catalog row and must not be restored as plain fallback text.
    if (isUnreviewedPrimeChapterConclusion(candidate.hour, source)) continue;

    const variants = catalog.rows.get(sourceRowKey(candidate.hour, source));
    if (!variants?.length) {
      result.push(plainSection(source, result.length));
      continue;
    }
    const selected = variants.toSorted((left, right) =>
      variantScore(right, candidate, rowIndex) - variantScore(left, candidate, rowIndex)
    )[0];
    result.push(...selected.sections.map(section => ({
      ...section,
      id: `section-${result.length}`
    })));
  }
  return result.map((section, index) => ({ ...section, id: `section-${index}` }));
}

function perennialOffice(
  candidate: ImportedOfficeCandidate,
  catalog: ReusableCatalog,
  release: boolean
): OfficeDocument {
  const normalized = normalizeDynamicOfficeText({
    id: `${candidate.date}-${candidate.hour}`,
    date: localDay(candidate.date),
    hour: candidate.hour,
    titleLatin: titles[candidate.hour].latin,
    titleEnglish: titles[candidate.hour].english,
    contextLabel: candidate.observanceLatin,
    sourceVersion: release
      ? "Rubrics 1960 - 1960 · perennial reviewed release"
      : "Rubrics 1960 - 1960 · perennial local-rules preview",
    format: "legacyReconstructed",
    visibleContentDigest: null,
    observance: {
      observanceID: `perennial/${stableID(candidate.observanceLatin)}`,
      titleLatin: candidate.observanceLatin,
      titleEnglish: catalog.observanceTitles.get(
        normalizedLatin(candidate.observanceLatin)
      ) ?? candidate.observanceLatin,
      rank: rank(candidate.rankLatin),
      color: null,
      season: candidate.seasonLatin,
      eveningContext: null,
      commemorations: []
    },
    sections: assembledSections(candidate, catalog)
  });
  if (!release) return normalized;
  return {
    ...normalized,
    format: "authoritativeOrdered",
    visibleContentDigest: canonicalVisibleContentDigest(normalized.sections)
  };
}

function cacheKey(date: string, hour: OfficeHour): string {
  return `${date}:${hour}`;
}

function generatorDate(date: string): string {
  const [year, month, day] = date.split("-");
  return `${month}-${day}-${year}`;
}

async function renderCandidate(options: {
  sourceRoot: string;
  date: string;
  hour: OfficeHour;
}): Promise<ImportedOfficeCandidate> {
  const generatorDirectory = resolve(
    options.sourceRoot,
    "standalone",
    "tools",
    "epubgen2"
  );
  const query = new URLSearchParams({
    date1: generatorDate(options.date),
    command: commandByHour[options.hour],
    version: "Rubrics 1960 - 1960",
    testmode: "regular",
    lang1: "Latin",
    lang2: "English",
    votive: "",
    nofancychars: "1"
  }).toString();
  const { stdout } = await execFileAsync("perl", ["EofficiumXhtml.pl", query], {
    cwd: generatorDirectory,
    encoding: "utf8",
    maxBuffer: 16 * 1_024 * 1_024
  });
  const sha256 = createHash("sha256").update(stdout).digest("hex");
  return parseDivinumOffice(stdout, {
    date: options.date,
    hour: options.hour,
    file: `${options.date}-${options.hour}.html`,
    sha256
  });
}

function openCache(path: string): DatabaseSync {
  mkdirSync(dirname(path), { recursive: true });
  const database = new DatabaseSync(path);
  database.exec(`
    PRAGMA journal_mode = WAL;
    PRAGMA synchronous = NORMAL;
    CREATE TABLE IF NOT EXISTS source_offices (
      key TEXT PRIMARY KEY NOT NULL,
      date TEXT NOT NULL,
      hour TEXT NOT NULL,
      payload BLOB NOT NULL
    ) WITHOUT ROWID;
  `);
  return database;
}

export async function populatePerennialSourceCache(options: {
  ordo: PerennialOrdoSchedule;
  sourceRoot: string;
  cache: string;
  range?: PerennialOrdoRange;
  concurrency?: number;
  progress?: (completed: number, total: number) => void;
}): Promise<void> {
  const configurations = [
    ...uniqueOfficeConfigurations(options.ordo, options.range).values()
  ];
  const database = openCache(options.cache);
  const existing = new Set(
    (database.prepare("SELECT key FROM source_offices").all() as Array<{ key: string }>)
      .map(row => row.key)
  );
  const pending = configurations.filter(item =>
    !existing.has(cacheKey(item.representativeDate, item.hour))
  );
  const insert = database.prepare(`
    INSERT OR REPLACE INTO source_offices(key, date, hour, payload)
    VALUES (?, ?, ?, ?)
  `);
  let cursor = 0;
  let completed = configurations.length - pending.length;
  const worker = async (): Promise<void> => {
    while (cursor < pending.length) {
      const item = pending[cursor];
      cursor += 1;
      const candidate = await renderCandidate({
        sourceRoot: options.sourceRoot,
        date: item.representativeDate,
        hour: item.hour
      });
      insert.run(
        cacheKey(item.representativeDate, item.hour),
        item.representativeDate,
        item.hour,
        encodeContentPayload(JSON.stringify(candidate))
      );
      completed += 1;
      if (completed % 250 === 0 || completed === configurations.length) {
        options.progress?.(completed, configurations.length);
      }
    }
  };
  try {
    await Promise.all(
      Array.from(
        { length: Math.max(1, Math.min(options.concurrency ?? 12, 32)) },
        worker
      )
    );
  } finally {
    database.close();
  }
}

function cachedCandidate(
  statement: ReturnType<DatabaseSync["prepare"]>,
  date: string,
  hour: OfficeHour,
  fallback?: { representativeDate: string; hour: OfficeHour }
): ImportedOfficeCandidate {
  let row = statement.get(cacheKey(date, hour)) as { payload: Uint8Array } | undefined;
  if (!row && fallback) {
    row = statement.get(
      cacheKey(fallback.representativeDate, fallback.hour)
    ) as { payload: Uint8Array } | undefined;
  }
  if (!row) throw new Error(`Perennial source cache lacks ${date}:${hour}`);
  return normalizeImportedOfficeCandidate(
    JSON.parse(decodeContentPayload(row.payload)) as ImportedOfficeCandidate
  );
}

function liturgicalDays(
  ordo: PerennialOrdoSchedule,
  range: PerennialOrdoRange
): LiturgicalDay[] {
  return ordo.days.filter(day =>
    day.date >= range.from && day.date <= range.to
  ).map(day => ({
    date: localDay(day.date),
    observanceID: `perennial/${stableID(day.titleLatin)}`,
    titleLatin: day.titleLatin,
    titleEnglish: null,
    rank: rank(day.rankLatin),
    color: null,
    season: "",
    eveningContext: null,
    commemorations: [],
    sourceVersion: "Rubrics 1960 - 1960"
  }));
}

interface CompilePerennialOptions {
  ordoPath: string;
  cache: string;
  database2026: string;
  divinumSnapshots2026: string;
  output: string;
  range?: PerennialOrdoRange;
}

function releaseSourceMetadata(
  manifest: ScheduledCorpusInput["manifest"]
): Pick<ScheduledCorpusInput["manifest"], "sources" | "notices"> {
  const reviewed = exceptionalMartyrologyReview();
  const review = reviewed.matrix;
  const approvalNotice = `Exceptional Martyrology approved by ${review.approval.reviewedBy} `
    + `on ${review.approval.reviewedAt}.`;
  return {
    sources: manifest.sources.map(source => {
      if (source.name === "Exceptional Martyrology English review matrix") {
        return {
          ...source,
          revision: `approved-${review.approval.reviewedAt}`,
          checksum: reviewed.checksum,
          notice: approvalNotice
        };
      }
      if (source.name === "Curated 2026 source-gap promotions") {
        return { ...source, checksum: curatedPromotionChecksum() };
      }
      return source;
    }),
    notices: [
      ...(manifest.notices ?? []).filter(notice =>
        notice !== "Release compilation requires recorded human approval."
      ),
      approvalNotice
    ]
  };
}

function resolveReleaseSchedule(
  input: ScheduledCorpusInput
): ScheduledCorpusInput {
  const recipes = new Map(input.recipes.map(recipe => [recipe.key, recipe.office]));
  const offices = input.schedule.map(item => {
    const office = recipes.get(item.recipeKey);
    if (!office) {
      throw new Error(`Release schedule references missing recipe ${item.recipeKey}`);
    }
    const date = dayKey(item.date);
    return {
      ...office,
      id: `${date}-${item.hour}`,
      date: item.date
    };
  });
  const resolved = withResolvedEveningContexts({
    manifest: input.manifest,
    days: input.days,
    offices
  } satisfies CorpusInput);
  const releaseRecipes = new Map<string, OfficeDocument>();
  const schedule = resolved.offices.map(office => {
    const key = stableRecipeKey(office);
    if (!releaseRecipes.has(key)) releaseRecipes.set(key, office);
    return { date: office.date, hour: office.hour, recipeKey: key };
  });
  return {
    ...input,
    days: resolved.days,
    recipes: [...releaseRecipes].map(([key, office]) => ({ key, office })),
    schedule
  };
}

function compilePerennial(
  options: CompilePerennialOptions,
  release: boolean
): { recipes: number; bytes: number; warnings: string[] } {
  const ordo = JSON.parse(readFileSync(options.ordoPath, "utf8")) as PerennialOrdoSchedule;
  const range = perennialOrdoRange(ordo, options.range);
  const catalog = catalogFrom2026({
    database: options.database2026,
    divinumSnapshots: options.divinumSnapshots2026
  });
  const cache = openCache(options.cache);
  const recipeByConfiguration = new Map<string, string>();
  const recipes = new Map<string, OfficeDocument>();
  const fullRangeConfigurations = uniqueOfficeConfigurations(ordo);
  try {
    const selectCandidate = cache.prepare(
      "SELECT payload FROM source_offices WHERE key = ?"
    );
    for (const [configuration, representative] of uniqueOfficeConfigurations(ordo, range)) {
      const candidate = cachedCandidate(
        selectCandidate,
        representative.representativeDate,
        representative.hour,
        fullRangeConfigurations.get(configuration)
      );
      const office = perennialOffice({
        ...candidate,
        date: representative.representativeDate
      }, catalog, release);
      const key = stableRecipeKey(office);
      recipes.set(key, office);
      recipeByConfiguration.set(configuration, key);
    }
  } finally {
    cache.close();
  }

  const days = liturgicalDays(ordo, range);
  const schedule: ScheduledCorpusInput["schedule"] = [];
  for (const [index, day] of ordo.days.entries()) {
    if (day.date < range.from || day.date > range.to) continue;
    const followingDay = ordo.days[index + 1];
    for (const hour of officeHours) {
      const recipeKey = recipeByConfiguration.get(
        officeConfigurationKey(day, hour, followingDay)
      );
      if (!recipeKey) throw new Error(`No recipe for ${day.date}:${hour}`);
      schedule.push({ date: localDay(day.date), hour, recipeKey });
    }
  }
  const seed = loadCompiledCorpus(options.database2026);
  const reviewedCenterYear = release
    ? Number(range.from.slice(0, 4)) + 1
    : null;
  const releaseMetadata = release
    ? releaseSourceMetadata(seed.manifest)
    : { sources: seed.manifest.sources, notices: seed.manifest.notices };
  let input: ScheduledCorpusInput = {
    manifest: {
      ...seed.manifest,
      ...releaseMetadata,
      corpusVersion: release
        ? `perennial-reviewed-${range.from.slice(0, 4)}-${range.to.slice(0, 4)}-v1`
        : "perennial-local-rules-preview",
      minimumAppVersion: release ? "1.0.3" : seed.manifest.minimumAppVersion,
      createdAt: new Date().toISOString(),
      coverage: {
        startDate: localDay(range.from),
        endDate: localDay(range.to),
        reviewedCenterYear,
        expectedOfficeCount: schedule.length,
        generatedOfficeCount: schedule.length,
        authoritativeOfficeCount: release ? schedule.length : 0,
        unresolvedScoreCount: 0,
        ambiguousScoreCount: 0,
        isSample: !release
      },
      packSHA256: "",
      signature: ""
    },
    days,
    recipes: [...recipes].map(([key, office]) => ({ key, office })),
    schedule
  };
  if (release) input = resolveReleaseSchedule(input);
  const warnings = compileScheduledCorpus(input, options.output, !release);
  return { recipes: input.recipes.length, bytes: statSync(options.output).size, warnings };
}

export function compilePerennialPreview(
  options: CompilePerennialOptions
): { recipes: number; bytes: number; warnings: string[] } {
  return compilePerennial(options, false);
}

export function compilePerennialRelease(
  options: CompilePerennialOptions
): { recipes: number; bytes: number; warnings: string[] } {
  return compilePerennial(options, true);
}
