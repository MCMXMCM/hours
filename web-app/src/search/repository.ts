// The search half of `SQLiteContentRepository`, parallel to
// `HoursCore/ContentRepository.swift`: the statements the native app runs on
// an edition's database, and the ranking, de-duplication, and snippets it
// makes of their rows.
//
// The Swift is an actor over SQLite's C interface. Here the database is
// anything that runs a statement and returns its rows, every method is
// synchronous (the worker that owns the database supplies the asynchrony),
// and `Task.checkCancellation` has no counterpart. A Swift private helper is
// a module-private function of the same name; an error Swift throws is thrown
// here with the same description.
//
// Only a search-optimized edition (schema 3) is read. The branches Swift
// keeps for schemas 1 and 2 are not ported, and the shared catalog of the
// bundled schema 5 cannot be reached through `SearchDatabase`; for any of
// these a search throws `ContentPackError`.
//
// Comparison. Swift compares and hashes Strings by canonical equivalence.
// Wherever the Swift compares, searches, or keys a dictionary by a String,
// the strings are first put in one normal form (`Strings.canonical`), in
// which canonical equivalence is identity.

import {
  officeTraditions,
  OfficeTraditions,
  type OfficeTradition,
} from "@/app/officeTradition.ts";
import {
  LocalDays,
  ObservanceTitle,
  OfficeHours,
  type ChantScore,
  type LocalDay,
  type OfficeHour,
  type OfficeSectionKind,
} from "@/core/models.ts";
import * as NotationStrings from "@/core/notation/strings.ts";
import { RomanMartyrologyCalendar } from "@/core/romanMartyrology.ts";
import * as SwiftString from "@/core/swiftString.ts";
import * as FoundationStrings from "@/reader/presentation/strings.ts";
import type {
  LiturgicalSearchHit,
  LiturgicalSearchLanguage,
  LiturgicalSearchResult,
  LiturgicalUsageContext,
} from "./models.ts";
import {
  chantScore,
  decodedLiturgicalDay,
  decodedStoredChantScore,
  decodedStoredRecipeHeader,
  decodedStoredTextResource,
  DecodingError,
  parsedJSON,
  type StoredRecipeHeader,
  type StoredTextResource,
} from "./stored.ts";
import * as Strings from "./strings.ts";
import {
  firstServedYear,
  perennialYearPlan,
  storedRanges,
  type PerennialYearPlan,
} from "@compiler/yearTypes.ts";

export { DecodingError, type DecodingErrorKind } from "./stored.ts";

export type SearchValue = string | number | Uint8Array | null;

/** Anything that can run SQL: node:sqlite in tests, SQLite compiled to WebAssembly in the app. */
export interface SearchDatabase {
  /** Runs one statement; each row is its column values in SELECT order. */
  rows(sql: string, bindings?: readonly (string | number)[]): SearchValue[][];
}

export interface SearchRepositoryOptions {
  tradition: OfficeTradition;
  /** Turns a stored payload BLOB into its JSON text. Default: UTF-8 decode. */
  decodePayload?: (payload: Uint8Array) => string;
}

/**
 * One case of Swift's `ContentRepositoryError`, named by `kind`. Search
 * throws these two; the cases that concern an office or a date are not
 * ported.
 */
export type ContentRepositoryErrorDetail =
  | { readonly kind: "databaseUnavailable"; readonly detail: string }
  | { readonly kind: "invalidContent"; readonly detail: string };

function contentRepositoryErrorDescription(
  detail: ContentRepositoryErrorDetail,
): string {
  switch (detail.kind) {
    case "databaseUnavailable":
      return `The office corpus could not be opened. ${detail.detail}`;
    case "invalidContent":
      return `The office corpus is invalid. ${detail.detail}`;
  }
}

/** `message` is the Swift error's `errorDescription`. */
export class ContentRepositoryError extends Error {
  readonly detail: ContentRepositoryErrorDetail;

  constructor(detail: ContentRepositoryErrorDetail) {
    super(contentRepositoryErrorDescription(detail));
    this.name = "ContentRepositoryError";
    this.detail = detail;
  }
}

function databaseUnavailable(detail: string): ContentRepositoryError {
  return new ContentRepositoryError({ kind: "databaseUnavailable", detail });
}

function invalidContent(detail: string): ContentRepositoryError {
  return new ContentRepositoryError({ kind: "invalidContent", detail });
}

/**
 * The error search throws for an edition whose schema the port does not
 * read, as the native app's content-pack error described it. `message` is
 * that error's description.
 */
export class ContentPackError extends Error {
  readonly detail: {
    readonly kind: "unsupportedSchema";
    readonly schema: number;
  };

  constructor(schema: number) {
    super(`Content schema ${schema} is not supported.`);
    this.name = "ContentPackError";
    this.detail = { kind: "unsupportedSchema", schema };
  }
}

/** Swift's `SQLiteContentRepositoryCacheMetrics`. */
export interface SearchRepositoryCacheMetrics {
  readonly recipeHeaderEntries: number;
  readonly recipeHeaderHits: number;
}

/** The schema whose statements are ported. */
const searchOptimizedSchemaVersion = 3;

const recipeHeaderCacheLimit = 4_096;

// The pieces of the search statement that Swift chooses by schema, as it
// chooses them for schema 3.
const incipitsColumn = "text_resources.incipits_latin";
const scoreExistence =
  "EXISTS(SELECT 1 FROM text_scores WHERE text_scores.text_id = text_resources.id)";
const hourRelation = "text_recipes";
const weights = "24.0, 14.0, 14.0, 4.0, 4.0, 1.0, 1.0";

const utf8Encoder = new TextEncoder();
const lenientUTF8Decoder = new TextDecoder("utf-8");
const strictUTF8Decoder = new TextDecoder("utf-8", { fatal: true });

/** The default `decodePayload`: the payload is its JSON text in UTF-8. */
function decodedUTF8(payload: Uint8Array): string {
  try {
    return strictUTF8Decoder.decode(payload);
  } catch {
    throw new DecodingError("dataCorrupted");
  }
}

// What SQLite's column accessors return for a value of any storage class.

/** `sqlite3_column_text`, with `String(cString:)`: nil for NULL. */
function columnText(value: SearchValue | undefined): string | null {
  if (value === null || value === undefined) return null;
  if (typeof value === "string") return value;
  if (typeof value === "number") return String(value);
  return lenientUTF8Decoder.decode(value);
}

/**
 * `sqlite3_column_blob`, with `sqlite3_column_bytes`: nil for NULL and for a
 * value of no bytes. Text is read as its UTF-8.
 */
function columnBlob(value: SearchValue | undefined): Uint8Array | null {
  if (value === null || value === undefined) return null;
  const bytes =
    value instanceof Uint8Array ? value : utf8Encoder.encode(String(value));
  return bytes.length === 0 ? null : bytes;
}

/** `sqlite3_column_int64`. */
function columnInt64(value: SearchValue | undefined): number {
  if (typeof value === "number") return Math.trunc(value);
  if (typeof value === "string") {
    const parsed = Number.parseInt(value, 10);
    return Number.isNaN(parsed) ? 0 : parsed;
  }
  return 0;
}

/** `sqlite3_column_double`. */
function columnDouble(value: SearchValue | undefined): number {
  if (typeof value === "number") return value;
  if (typeof value === "string") {
    const parsed = Number.parseFloat(value);
    return Number.isNaN(parsed) ? 0 : parsed;
  }
  return 0;
}

function optionalText(value: SearchValue | undefined): string | null {
  return columnText(value);
}

/**
 * `LocalDay(iso8601:)`. Unlike `LocalDays.fromISO`, it divides as Swift's
 * `split(separator:)` does, which omits an empty piece, and reads each piece
 * as `Int(_:)` does.
 */
function localDay(iso8601: string): LocalDay | null {
  const parts = SwiftString.splitOmittingEmpty(
    iso8601,
    (character) => character === "-",
  );
  if (parts.length !== 3) return null;
  const year = FoundationStrings.swiftInt(parts[0]);
  const month = FoundationStrings.swiftInt(parts[1]);
  const day = FoundationStrings.swiftInt(parts[2]);
  if (year === null || month === null || day === null) return null;
  return { year, month, day };
}

/** `OfficeTradition(rubrics:)`. */
function officeTradition(rubrics: string): OfficeTradition | null {
  return (
    officeTraditions.find(
      (tradition) => OfficeTraditions.rubrics(tradition) === rubrics,
    ) ?? null
  );
}

/** A Character that is neither a letter nor a number divides a query into its words. */
function isTokenSeparator(character: string): boolean {
  return !SwiftString.isLetter(character) && !SwiftString.isNumber(character);
}

function ftsQuery(query: string, language: LiturgicalSearchLanguage): string {
  const rawTokens = SwiftString.splitOmittingEmpty(query, isTokenSeparator);
  if (rawTokens.length === 0) return "";
  function expression(columns: string, tokens: readonly string[]): string {
    return tokens
      .map((token) => {
        const escaped = NotationStrings.replacingOccurrences(token, '"', '""');
        return `{${columns}} : "${escaped}"*`;
      })
      .join(" AND ");
  }
  const latinColumns = "incipits_latin title_latin rubric_latin latin";
  const latin = expression(
    latinColumns,
    rawTokens.map((token) => searchNormalized(token, true)),
  );
  const english = expression(
    "title_english rubric_english english",
    rawTokens.map((token) => searchNormalized(token, false)),
  );
  switch (language) {
    case "latin":
      return latin;
    case "english":
      return english;
    case "all":
      return `(${latin}) OR (${english})`;
  }
}

/** `searchNormalized(_:latin:)`, which the Missal's search asks too. */
export function searchNormalized(value: string, latin: boolean): string {
  // Diacritics are folded before the ligatures are written out, in the
  // order the compiler indexes Latin: an accented ligature (ǽ) folds to the
  // plain one, which a replacement made first would pass over.
  //
  // The locale Swift folds in (Latin or English) has no casing rules of its
  // own, so it does not enter into the folding.
  let normalized = Strings.replacingOccurrencesCaseInsensitive(
    Strings.replacingOccurrencesCaseInsensitive(
      SwiftString.folding(value, {
        caseInsensitive: true,
        diacriticInsensitive: true,
      }),
      "æ",
      "ae",
    ),
    "œ",
    "oe",
  ).toLowerCase();
  if (latin) {
    normalized = NotationStrings.replacingOccurrences(normalized, "j", "i");
  }
  return normalized;
}

function matches(
  fields: readonly string[],
  query: string,
  latin: boolean,
): boolean {
  const haystack = Strings.canonical(searchNormalized(fields.join(" "), latin));
  return SwiftString.splitOmittingEmpty(query, isTokenSeparator).every(
    (token) =>
      FoundationStrings.contains(
        haystack,
        Strings.canonical(searchNormalized(token, latin)),
      ),
  );
}

/**
 * `matchesOfficeTitle(latin:english:query:language:)`: whether every word of
 * the query is found in a title, Latin or English. The Missal's search of
 * titles asks it too.
 */
export function matchesOfficeTitle(
  latin: string,
  english: string | null,
  query: string,
  language: LiturgicalSearchLanguage,
): boolean {
  const englishFields = english === null ? [] : [english];
  switch (language) {
    case "latin":
      return matches([latin], query, true);
    case "english":
      return matches(englishFields, query, false);
    case "all":
      return (
        matches([latin], query, true) || matches(englishFields, query, false)
      );
  }
}

/** The fields of a text that ranking and snippets read. */
export type SearchedText = Pick<
  StoredTextResource,
  "title" | "titleEnglish" | "rubric" | "latin" | "english"
>;

function matchedLanguage(
  resource: SearchedText,
  incipits: string,
  query: string,
  requested: LiturgicalSearchLanguage,
): LiturgicalSearchLanguage {
  if (requested !== "all") return requested;
  // The index reads a Latin query in the chant incipits as well, and a
  // resource may hold its words there alone, printing only "V/".
  const latinFields = [
    incipits,
    resource.title,
    resource.rubric,
    resource.latin,
  ].filter((field): field is string => field !== null);
  if (matches(latinFields, query, true)) return "latin";
  return "english";
}

/**
 * `searchPhraseRank`: how nearly a text answers the query as a phrase: 0
 * where its title or an incipit is the query, 1 where one begins with it, 2
 * where one holds it, 3 where the text does, and 4 where its words are found
 * apart. The Missal's results are ranked by it too, and merged by it with
 * the Office's.
 */
export function searchPhraseRank(
  resource: SearchedText,
  incipits: string,
  query: string,
  language: LiturgicalSearchLanguage,
): number {
  return phraseRank(resource, incipits, query, language);
}

function phraseRank(
  resource: SearchedText,
  incipits: string,
  query: string,
  language: LiturgicalSearchLanguage,
): number {
  const latin = language !== "english";
  const needle = Strings.canonical(
    SwiftString.trimmingWhitespaceAndNewlines(searchNormalized(query, latin)),
  );
  const title = Strings.canonical(
    searchNormalized(
      language === "english" ? (resource.titleEnglish ?? "") : resource.title,
      latin,
    ),
  );
  const incipit = latin
    ? Strings.canonical(searchNormalized(incipits, true))
    : "";
  const body = Strings.canonical(
    searchNormalized(
      language === "english" ? (resource.english ?? "") : resource.latin,
      latin,
    ),
  );
  if (
    title === needle ||
    SwiftString.splitOmittingEmpty(
      incipit,
      (character) => character === "\n",
    ).some((line) => line === needle)
  ) {
    return 0;
  }
  if (Strings.hasPrefix(title, needle) || Strings.hasPrefix(incipit, needle)) {
    return 1;
  }
  if (
    FoundationStrings.contains(title, needle) ||
    FoundationStrings.contains(incipit, needle)
  ) {
    return 2;
  }
  if (FoundationStrings.contains(body, needle)) return 3;
  return 4;
}

/**
 * `StoredTextResource.proclaiming(on:)`: the text as it is shown outside an
 * Office, naming the Moon and the year of `day`, or leaving them unsaid where
 * no day is in view.
 */
function proclaiming(
  resource: StoredTextResource,
  day: LocalDay | null,
): StoredTextResource {
  if (
    !RomanMartyrologyCalendar.awaitsProclamation(resource.latin) &&
    !(
      resource.english !== null &&
      RomanMartyrologyCalendar.awaitsProclamation(resource.english)
    )
  ) {
    return resource;
  }
  const shown = (text: string): string =>
    day === null
      ? RomanMartyrologyCalendar.withoutProclamation(text)
      : RomanMartyrologyCalendar.proclaiming(text, day);
  return {
    ...resource,
    latin: shown(resource.latin),
    english: resource.english === null ? null : shown(resource.english),
  };
}

/** `searchSnippet`: the paragraph, or incipit, that best answers the query. */
export function searchSnippet(
  resource: SearchedText,
  incipits: string,
  query: string,
  language: LiturgicalSearchLanguage,
): string {
  return snippet(resource, incipits, query, language);
}

function snippet(
  resource: SearchedText,
  incipits: string,
  query: string,
  language: LiturgicalSearchLanguage,
): string {
  const latin = language !== "english";
  const body =
    language === "english"
      ? (resource.english ?? resource.latin)
      : resource.latin;
  const candidates = FoundationStrings.componentsSeparatedBy(
    body,
    "\n\n",
  ).filter((paragraph) => paragraph.length > 0);
  if (latin && !matches([body], query, true)) {
    // A resource may print only "V/" where its words are sung, and
    // hold them in its chant's incipit. Where the body lacks a word
    // of the query, the incipit lines are read after its paragraphs;
    // of equal scores the first is kept, so a line is shown only
    // when it answers the query better than all the body. A body
    // that holds every word is shown by its own paragraphs.
    candidates.push(
      ...SwiftString.splitOmittingEmpty(
        incipits,
        (character) => character === "\n",
      ),
    );
  }
  const needle = Strings.canonical(
    SwiftString.trimmingWhitespaceAndNewlines(searchNormalized(query, latin)),
  );
  const tokens = SwiftString.splitOmittingEmpty(query, isTokenSeparator).map(
    (token) => Strings.canonical(searchNormalized(token, latin)),
  );
  function score(value: string): number {
    const normalized = Strings.canonical(searchNormalized(value, latin));
    return (
      (FoundationStrings.contains(normalized, needle) ? 100 : 0) +
      tokens.filter((token) => FoundationStrings.contains(normalized, token))
        .length
    );
  }
  // `candidates.max { score($0) < score($1) }` is the first of the
  // highest-scoring candidates. Each is scored once here, where Swift scores
  // the pair anew at every comparison.
  let selected = body;
  let selectedScore: number | null = null;
  for (const candidate of candidates) {
    const candidateScore = score(candidate);
    if (selectedScore === null || selectedScore < candidateScore) {
      selected = candidate;
      selectedScore = candidateScore;
    }
  }
  const collapsed = Strings.collapsingWhitespace(selected);
  if (!(Strings.characterCount(collapsed) > 240)) return collapsed;
  return `${Strings.prefix(collapsed, 239)}…`;
}

// ICU's `\b\d{1,3}:\d{1,3}[a-z]?\b|[*†‡✠]`: Foundation's regular expressions
// are ICU's, whose `\b` and `\d` are Unicode's and not ASCII's.
const scriptureReferenceOrSign = new RegExp(
  `${SwiftString.icuWordBoundary}[${SwiftString.icuDigit}]{1,3}:[${SwiftString.icuDigit}]{1,3}[a-z]?${SwiftString.icuWordBoundary}|[*†‡✠]`,
  "gu",
);

function deduplicatedSearchHits(
  hits: readonly LiturgicalSearchHit[],
  limit: number,
): LiturgicalSearchHit[] {
  const resultIndexByPassage = new Map<string, number>();
  const results: LiturgicalSearchHit[] = [];

  for (const hit of hits) {
    // The same passage may be printed with the source's line labels in
    // one resource and with verified Scripture references, or chant
    // pointing, in another. Neither makes it a different passage.
    const normalizedSnippet = Strings.collapsingWhitespace(
      searchNormalized(hit.snippet, hit.snippetLanguage !== "english").replace(
        scriptureReferenceOrSign,
        " ",
      ),
    );
    const passageKey = Strings.canonical(
      [hit.kind, hit.snippetLanguage, normalizedSnippet].join("\u{1f}"),
    );
    const index = resultIndexByPassage.get(passageKey);
    if (index !== undefined) {
      // Keep the passage's rank, but prefer a representation with notation.
      if (hit.hasScoredRealizations && !results[index].hasScoredRealizations) {
        results[index] = hit;
      }
      continue;
    }
    if (!(results.length < limit)) continue;
    resultIndexByPassage.set(passageKey, results.length);
    results.push(hit);
  }
  return results;
}

/**
 * Swift's `LiturgicalUsageContextKey`, as the key of a `Map`: an Office as it
 * is shown, its title without the marker of the week's Scripture, at an Hour.
 * Within a church year one observance bears it. From one year to another the
 * stored title and identifier of an observance may differ, and it is the
 * same Office, to be found once.
 */
function liturgicalUsageContextKey(context: LiturgicalUsageContext): string {
  return JSON.stringify([
    context.hour,
    Strings.canonical(ObservanceTitle.latin(context.observanceTitleLatin)),
  ]);
}

/** `Array(Set(modes)).sorted()`. */
function sortedDistinct(modes: readonly string[]): string[] {
  const distinct = new Map<string, string>();
  for (const mode of modes) {
    const key = Strings.canonical(mode);
    if (!distinct.has(key)) distinct.set(key, mode);
  }
  return [...distinct.values()].sort(Strings.compare);
}

type DayRange = { lowerBound: LocalDay; upperBound: LocalDay };

/**
 * `UsageSegment`: a stored range of dates to search for usages, with the
 * served year its dates are prayed in.
 */
interface UsageSegment {
  /** Null where the whole corpus is searched. */
  readonly stored: DayRange | null;
  /** Null where the corpus stores the dates it serves. */
  readonly servedYear: number | null;
}

function served(segment: UsageSegment, stored: LocalDay): LocalDay {
  return segment.servedYear === null
    ? stored
    : { year: segment.servedYear, month: stored.month, day: stored.day };
}

/**
 * `ContentCoverage.yearPlan()`, from the manifest as parsed: the plan of a
 * perennial edition, or null where every date served is stored.
 */
function yearPlan(manifest: Record<string, unknown>): PerennialYearPlan | null {
  const coverage = manifest.coverage;
  if (typeof coverage !== "object" || coverage === null) return null;
  const { storedYears, startDate, endDate } = coverage as Record<
    string,
    unknown
  >;
  if (storedYears === undefined || storedYears === null) return null;
  const year = (date: unknown): number | null => {
    if (typeof date !== "object" || date === null) return null;
    const { year, month, day } = date as Record<string, unknown>;
    return typeof year === "number" &&
      typeof month === "number" &&
      typeof day === "number"
      ? year
      : null;
  };
  const from = year(startDate);
  const to = year(endDate);
  const start = startDate as Record<string, unknown> | null;
  const end = endDate as Record<string, unknown> | null;
  if (
    from === null ||
    to === null ||
    from > to ||
    start?.month !== 1 ||
    start?.day !== 1 ||
    end?.month !== 12 ||
    end?.day !== 31
  ) {
    throw invalidContent("A perennial corpus must serve whole civil years.");
  }
  if (
    !Array.isArray(storedYears) ||
    !storedYears.every((value) => Number.isInteger(value))
  ) {
    throw invalidContent(
      "The corpus's stored years are not an ordered list of civil years.",
    );
  }
  try {
    return perennialYearPlan(from, to, storedYears as number[]);
  } catch (error) {
    throw invalidContent(
      error instanceof Error ? error.message : String(error),
    );
  }
}

function groupedUsageContexts(
  contexts: readonly LiturgicalUsageContext[],
): LiturgicalUsageContext[] {
  const grouped = new Map<string, LiturgicalUsageContext>();
  for (const context of contexts) {
    const key = liturgicalUsageContextKey(context);
    const existing = grouped.get(key);
    if (existing === undefined) {
      grouped.set(key, context);
      continue;
    }
    // The group is named as its first occurrence is, which is the one
    // opened.
    const [first, other] = LocalDays.isBefore(
      context.firstDate,
      existing.firstDate,
    )
      ? [context, existing]
      : [existing, context];
    grouped.set(key, {
      observanceID: first.observanceID ?? null,
      firstDate: first.firstDate,
      lastDate: LocalDays.isBefore(context.lastDate, existing.lastDate)
        ? existing.lastDate
        : context.lastDate,
      hour: first.hour,
      observanceTitleLatin: first.observanceTitleLatin,
      observanceTitleEnglish:
        first.observanceTitleEnglish ?? other.observanceTitleEnglish ?? null,
      occurrenceCount: existing.occurrenceCount + context.occurrenceCount,
      settingModes: sortedDistinct([
        ...existing.settingModes,
        ...context.settingModes,
      ]),
    });
  }
  const hourOrder = new Map<OfficeHour, number>(
    OfficeHours.allCases.map((hour, offset) => [hour, offset]),
  );
  const isOrderedBefore = (
    left: LiturgicalUsageContext,
    right: LiturgicalUsageContext,
  ): boolean => {
    const leftHour = hourOrder.get(left.hour) ?? 0;
    const rightHour = hourOrder.get(right.hour) ?? 0;
    if (leftHour !== rightHour) return leftHour < rightHour;
    const titleOrder = Strings.localizedStandardCompare(
      left.observanceTitleLatin,
      right.observanceTitleLatin,
    );
    if (titleOrder !== 0) return titleOrder < 0;
    // Titles that differ may yet compare alike. A dictionary's order is
    // unspecified, so the identifier decides between them (an absent one
    // first), and then the earlier first date.
    const leftID = left.observanceID ?? null;
    const rightID = right.observanceID ?? null;
    if (leftID === null && rightID !== null) return true;
    if (leftID !== null && rightID === null) return false;
    if (leftID !== null && rightID !== null) {
      const identifierOrder = Strings.compare(leftID, rightID);
      if (identifierOrder !== 0) return identifierOrder < 0;
    }
    return LocalDays.isBefore(left.firstDate, right.firstDate);
  };
  return [...grouped.values()].sort((left, right) =>
    isOrderedBefore(left, right) ? -1 : isOrderedBefore(right, left) ? 1 : 0,
  );
}

interface LiturgicalSearchCandidate {
  readonly rank: number;
  readonly databaseRank: number;
  readonly hit: LiturgicalSearchHit;
}

export class SearchRepository {
  private readonly database: SearchDatabase;
  private readonly decodePayload: (payload: Uint8Array) => string;
  private readonly schemaVersion: number;
  readonly tradition: OfficeTradition;
  /** The plan by which a perennial edition serves more years than it stores. */
  private readonly yearPlan: PerennialYearPlan | null;
  private readonly recipeHeaderCache = new Map<number, StoredRecipeHeader>();
  private readonly recipeHeaderInsertionOrder: number[] = [];
  private recipeHeaderCacheHitCount = 0;

  /**
   * `SQLiteContentRepository.init(databaseURL:expectedTradition:)`, for a
   * database already open: the edition must declare a schema and the rubrics
   * of the tradition expected. Of the edition's coverage search needs the
   * year plan alone, by which usages are dated as they are prayed.
   */
  constructor(database: SearchDatabase, options: SearchRepositoryOptions) {
    this.database = database;
    this.decodePayload = options.decodePayload ?? decodedUTF8;

    // `SharedContentDatabase.prepare`, as far as it concerns a standalone
    // edition.
    const manifest = this.metadata("manifest");
    if (manifest === null) throw invalidContent("Missing content manifest.");
    const object = parsedJSON(manifest);
    const schema =
      typeof object === "object" && object !== null && !Array.isArray(object)
        ? (object as Record<string, unknown>).schemaVersion
        : undefined;
    if (typeof schema !== "number" || !Number.isInteger(schema)) {
      throw invalidContent("Missing content manifest.");
    }
    const identity = this.metadata("shared_catalog");
    // `SharedContentDatabase.storageSchema`, the bundle-only schema.
    if (schema !== 5 && identity !== null) {
      throw invalidContent("Unexpected shared catalog in standalone content.");
    }

    // `readManifest`, of which search needs the rubrics alone.
    const rubrics = (object as Record<string, unknown>).rubrics;
    if (rubrics === undefined) throw new DecodingError("keyNotFound");
    if (rubrics === null) throw new DecodingError("valueNotFound");
    if (typeof rubrics !== "string") throw new DecodingError("typeMismatch");
    const tradition = officeTradition(rubrics);
    if (tradition === null || options.tradition !== tradition) {
      throw invalidContent("The corpus has incorrect office rubrics.");
    }
    this.tradition = tradition;
    this.schemaVersion = schema;
    this.yearPlan = yearPlan(object as Record<string, unknown>);
  }

  /**
   * `usageSegments(for:)`: the stored ranges that hold a range of served
   * dates. A corpus that stores what it serves has the range itself. A
   * perennial corpus has one range for each civil year touched; searched
   * whole, it has each stored year, dated as the first year it serves.
   */
  private usageSegments(usageRange: DayRange | null): UsageSegment[] {
    const plan = this.yearPlan;
    if (plan === null) return [{ stored: usageRange, servedYear: null }];
    const day = (iso: string): LocalDay => localDay(iso)!;
    if (usageRange !== null) {
      return storedRanges(
        plan,
        LocalDays.description(usageRange.lowerBound),
        LocalDays.description(usageRange.upperBound),
      ).map((range) => ({
        stored: { lowerBound: day(range.from), upperBound: day(range.to) },
        servedYear: range.servedYear,
      }));
    }
    return plan.years
      .flatMap((stored): UsageSegment[] => {
        const servedYear = firstServedYear(plan, stored);
        return servedYear === null
          ? []
          : [
              {
                stored: {
                  lowerBound: { year: stored, month: 1, day: 1 },
                  upperBound: { year: stored, month: 12, day: 31 },
                },
                servedYear,
              },
            ];
      })
      .sort((left, right) => (left.servedYear ?? 0) - (right.servedYear ?? 0));
  }

  contentSchemaVersion(): number {
    return this.schemaVersion;
  }

  cacheMetricsForTesting(): SearchRepositoryCacheMetrics {
    return {
      recipeHeaderEntries: this.recipeHeaderCache.size,
      recipeHeaderHits: this.recipeHeaderCacheHitCount,
    };
  }

  searchOfficeTitles(
    query: string,
    language: LiturgicalSearchLanguage = "all",
    hour: OfficeHour | null = null,
    usageRange: { lowerBound: LocalDay; upperBound: LocalDay } | null = null,
    limit = 50,
  ): LiturgicalUsageContext[] {
    this.requireSearchOptimizedSchema();
    if (
      !SwiftString.characters(query).some(
        (character) =>
          SwiftString.isLetter(character) || SwiftString.isNumber(character),
      )
    ) {
      return [];
    }
    const contexts: LiturgicalUsageContext[] = [];
    // Usages are gathered from each stored range in turn and dated as the
    // range is served, so that they are grouped by the dates prayed.
    for (const segment of this.usageSegments(usageRange)) {
      this.officeTitleContexts(query, language, hour, segment, contexts);
    }
    return groupedUsageContexts(contexts).slice(
      0,
      Math.max(1, Math.min(limit, 50)),
    );
  }

  /** `officeTitleContexts(query:language:hour:segment:into:)`. */
  private officeTitleContexts(
    query: string,
    language: LiturgicalSearchLanguage,
    hour: OfficeHour | null,
    segment: UsageSegment,
    contexts: LiturgicalUsageContext[],
  ): void {
    const conditions: string[] = [];
    const bindings: string[] = [];
    if (hour !== null) {
      conditions.push("office_schedule.hour = ?");
      bindings.push(hour);
    }
    if (segment.stored !== null) {
      conditions.push("office_schedule.date BETWEEN ? AND ?");
      bindings.push(LocalDays.description(segment.stored.lowerBound));
      bindings.push(LocalDays.description(segment.stored.upperBound));
    }
    const whereClause =
      conditions.length === 0 ? "" : `WHERE ${conditions.join(" AND ")}`;
    const sql = [
      "SELECT recipes.id, MIN(office_schedule.date), MAX(office_schedule.date),",
      "       COUNT(*), recipes.payload",
      "FROM office_schedule",
      "JOIN recipes ON recipes.id = office_schedule.recipe_id",
      whereClause,
      "GROUP BY recipes.id",
      "ORDER BY MIN(office_schedule.date), recipes.id",
    ].join("\n");

    for (const row of this.rows(sql, bindings)) {
      const firstDateValue = columnText(row[1]);
      const firstDate =
        firstDateValue === null ? null : localDay(firstDateValue);
      const lastDateValue = columnText(row[2]);
      const lastDate = lastDateValue === null ? null : localDay(lastDateValue);
      if (firstDate === null || lastDate === null) {
        throw invalidContent("An office title search row is malformed.");
      }
      const recipeID = columnInt64(row[0]);
      const header = this.decodedRecipeHeader(recipeID, row[4]);
      const observance = header.observance;
      if (
        observance === null ||
        !matchesOfficeTitle(
          observance.titleLatin,
          observance.titleEnglish ?? null,
          query,
          language,
        )
      ) {
        continue;
      }
      contexts.push({
        observanceID: observance.observanceID,
        firstDate: served(segment, firstDate),
        lastDate: served(segment, lastDate),
        hour: header.hour,
        observanceTitleLatin: observance.titleLatin,
        observanceTitleEnglish: observance.titleEnglish ?? null,
        occurrenceCount: columnInt64(row[3]),
        settingModes: [],
      });
    }
  }

  /**
   * `officeTitleDays(query:language:hour:usageRange:)`: the days, dated as
   * they are prayed, on which the Office of an Hour bears a title the query
   * matches. By these the Masses of a day are found under the day's title.
   */
  officeTitleDays(
    query: string,
    language: LiturgicalSearchLanguage,
    hour: OfficeHour,
    usageRange: DayRange | null = null,
  ): Set<string> {
    this.requireSearchOptimizedSchema();
    const days = new Set<string>();
    if (
      !SwiftString.characters(query).some(
        (character) =>
          SwiftString.isLetter(character) || SwiftString.isNumber(character),
      )
    ) {
      return days;
    }
    const matched = new Map<number, boolean>();
    for (const segment of this.usageSegments(usageRange)) {
      const conditions = ["office_schedule.hour = ?"];
      const bindings: string[] = [hour];
      if (segment.stored !== null) {
        conditions.push("office_schedule.date BETWEEN ? AND ?");
        bindings.push(LocalDays.description(segment.stored.lowerBound));
        bindings.push(LocalDays.description(segment.stored.upperBound));
      }
      const sql = [
        "SELECT office_schedule.date, recipes.id, recipes.payload",
        "FROM office_schedule",
        "JOIN recipes ON recipes.id = office_schedule.recipe_id",
        `WHERE ${conditions.join(" AND ")}`,
        "ORDER BY office_schedule.date",
      ].join("\n");
      for (const row of this.rows(sql, bindings)) {
        const dateValue = columnText(row[0]);
        const date = dateValue === null ? null : localDay(dateValue);
        if (date === null) {
          throw invalidContent("An office title search row is malformed.");
        }
        const recipeID = columnInt64(row[1]);
        let isMatched = matched.get(recipeID);
        if (isMatched === undefined) {
          const observance = this.decodedRecipeHeader(
            recipeID,
            row[2],
          ).observance;
          isMatched =
            observance !== null &&
            matchesOfficeTitle(
              observance.titleLatin,
              observance.titleEnglish ?? null,
              query,
              language,
            );
          matched.set(recipeID, isMatched);
        }
        if (isMatched) days.add(LocalDays.description(served(segment, date)));
      }
    }
    return days;
  }

  searchHits(
    query: string,
    language: LiturgicalSearchLanguage = "all",
    kind: OfficeSectionKind | null = null,
    hour: OfficeHour | null = null,
    requiresScore = false,
    limit = 50,
  ): LiturgicalSearchHit[] {
    this.requireSearchOptimizedSchema();
    const match = ftsQuery(query, language);
    if (match.length === 0) return [];
    const cappedLimit = Math.max(1, Math.min(limit, 50));
    const kindClause = kind === null ? "" : "AND text_resources.kind = ?";
    const scoreClause = requiresScore ? `AND ${scoreExistence}` : "";
    const hourClause =
      hour === null
        ? ""
        : [
            "AND EXISTS(",
            "  SELECT 1",
            `  FROM ${hourRelation}`,
            `  JOIN office_schedule ON office_schedule.recipe_id = ${hourRelation}.recipe_id`,
            `  WHERE ${hourRelation}.text_id = text_resources.id`,
            "    AND office_schedule.hour = ?",
            ")",
          ].join("\n");
    const sql = [
      "SELECT text_resources.id, text_resources.stable_key, text_resources.payload,",
      `       ${incipitsColumn}, bm25(text_fts, ${weights}), ${scoreExistence}`,
      "FROM text_fts",
      "JOIN text_resources ON text_resources.id = text_fts.rowid",
      "WHERE text_fts MATCH ?",
      `  ${kindClause}`,
      `  ${scoreClause}`,
      `  ${hourClause}`,
      `ORDER BY bm25(text_fts, ${weights}), length(text_resources.payload)`,
      "LIMIT ?",
    ].join("\n");
    // Several resources can print one passage; they are collapsed after
    // ranking. Widen the candidate set only when that leaves the page short.
    const rankedHits = (
      candidateLimit: number,
    ): { hits: LiturgicalSearchHit[]; exhausted: boolean } => {
      const bindings: (string | number)[] = [match];
      if (kind !== null) bindings.push(kind);
      if (hour !== null) bindings.push(hour);
      bindings.push(candidateLimit);

      const candidates: LiturgicalSearchCandidate[] = [];
      for (const row of this.rows(sql, bindings)) {
        const stableKeyValue = columnText(row[1]);
        const payloadValue = columnBlob(row[2]);
        if (stableKeyValue === null || payloadValue === null) {
          throw invalidContent("A search row is malformed.");
        }
        const id = stableKeyValue;
        // A list of results has no day in view.
        const resource = proclaiming(
          decodedStoredTextResource(this.decodedPayload(payloadValue)),
          null,
        );
        const incipits = optionalText(row[3]) ?? "";
        const snippetLanguage = matchedLanguage(
          resource,
          incipits,
          query,
          language,
        );
        const rank = phraseRank(resource, incipits, query, snippetLanguage);
        candidates.push({
          rank,
          databaseRank: columnDouble(row[4]),
          hit: {
            id,
            kind: resource.kind,
            titleLatin: resource.title,
            titleEnglish: resource.titleEnglish,
            snippet: snippet(resource, incipits, query, snippetLanguage),
            snippetLanguage,
            hasScoredRealizations: columnInt64(row[5]) !== 0,
            rank,
          },
        });
      }
      const ranked = [...candidates]
        .sort((left, right) => {
          if (left.rank !== right.rank) return left.rank < right.rank ? -1 : 1;
          if (left.databaseRank !== right.databaseRank) {
            return left.databaseRank < right.databaseRank ? -1 : 1;
          }
          return Strings.compare(left.hit.id, right.hit.id);
        })
        .map((candidate) => candidate.hit);
      return { hits: ranked, exhausted: candidates.length < candidateLimit };
    };

    let candidateLimit = Math.min(cappedLimit * 5, 250);
    for (;;) {
      const { hits: ranked, exhausted } = rankedHits(candidateLimit);
      const hits = deduplicatedSearchHits(ranked, cappedLimit);
      if (hits.length >= cappedLimit || exhausted || candidateLimit >= 2_000) {
        return hits;
      }
      candidateLimit = Math.min(candidateLimit * 4, 2_000);
    }
  }

  searchDetail(
    id: string,
    usageRange: { lowerBound: LocalDay; upperBound: LocalDay } | null = null,
  ): LiturgicalSearchResult {
    this.requireSearchOptimizedSchema();
    const rows = this.rows(
      "SELECT id, payload FROM text_resources WHERE stable_key = ? LIMIT 1",
      [id],
    );
    const payloadValue = rows.length === 0 ? null : columnBlob(rows[0][1]);
    if (payloadValue === null) {
      throw invalidContent(`Search resource ${id} is missing.`);
    }
    const numericID = columnInt64(rows[0][0]);
    const stored = decodedStoredTextResource(this.decodedPayload(payloadValue));
    const scores = this.scores(numericID);
    const contexts = this.contexts(numericID, usageRange);
    // The Martyrology names the Moon and the year of the day after the
    // Prime at which it is read: here the first within the range asked.
    const firstPrime =
      usageRange === null
        ? null
        : contexts
            .filter((context) => context.hour === "prime")
            .map((context) => context.firstDate)
            .reduce<LocalDay | null>(
              (first, date) =>
                first === null || LocalDays.isBefore(date, first)
                  ? date
                  : first,
              null,
            );
    const resource = proclaiming(
      stored,
      firstPrime === null ? null : LocalDays.adding(firstPrime, 1),
    );
    return {
      id,
      kind: resource.kind,
      titleLatin: resource.title,
      titleEnglish: resource.titleEnglish,
      rubricLatin: resource.rubric,
      rubricEnglish: resource.rubricEnglish,
      latin: resource.latin,
      english: resource.english,
      scoredRealizations: scores,
      contexts,
      massContexts: [],
      settingNotes: {},
    };
  }

  /** `scores(forTextResource:)`. */
  private scores(textID: number): ChantScore[] {
    const scoreRelation = "text_scores";
    const payloads = this.queryInteger(
      [
        "SELECT DISTINCT scores.payload",
        `FROM ${scoreRelation}`,
        `JOIN scores ON scores.id = ${scoreRelation}.score_id`,
        `WHERE ${scoreRelation}.text_id = ?`,
        `ORDER BY ${scoreRelation}.score_id`,
      ].join("\n"),
      textID,
    );
    return payloads.map((payload) =>
      chantScore(decodedStoredChantScore(this.decodedPayload(payload))),
    );
  }

  /** `contexts(forTextResource:usageRange:)`. */
  private contexts(
    textID: number,
    usageRange: { lowerBound: LocalDay; upperBound: LocalDay } | null,
  ): LiturgicalUsageContext[] {
    const contexts: LiturgicalUsageContext[] = [];
    // A text is commonly set to one chant throughout, so the same score
    // payload recurs from row to row. Swift decodes it for each; here a
    // payload already decoded in this pass is not decoded again.
    const settingModesByScore = new Map<string, readonly string[]>();
    for (const segment of this.usageSegments(usageRange)) {
      this.textContexts(textID, segment, contexts, settingModesByScore);
    }
    return groupedUsageContexts(contexts);
  }

  /** `textContexts(forTextResource:segment:into:)`. */
  private textContexts(
    textID: number,
    segment: UsageSegment,
    contexts: LiturgicalUsageContext[],
    settingModesByScore: Map<string, readonly string[]>,
  ): void {
    const relation = "text_recipes";
    const scoreJoin = [
      "JOIN recipe_sections",
      "  ON recipe_sections.recipe_id = text_recipes.recipe_id",
      " AND recipe_sections.text_id = text_recipes.text_id",
    ].join("\n");
    const scoreID = "recipe_sections.score_id";
    const rangeClause =
      segment.stored === null ? "" : "AND office_schedule.date BETWEEN ? AND ?";
    const sql = [
      "SELECT office_schedule.date, office_schedule.hour, days.payload,",
      "       scores.payload",
      `FROM ${relation}`,
      "JOIN office_schedule ON office_schedule.recipe_id = text_recipes.recipe_id",
      "JOIN days ON days.date = office_schedule.date",
      scoreJoin,
      `LEFT JOIN scores ON scores.id = ${scoreID}`,
      "WHERE text_recipes.text_id = ?",
      `  ${rangeClause}`,
      "ORDER BY office_schedule.date, office_schedule.hour, scores.id",
    ].join("\n");
    const bindings: (string | number)[] = [textID];
    if (segment.stored !== null) {
      bindings.push(
        LocalDays.description(segment.stored.lowerBound),
        LocalDays.description(segment.stored.upperBound),
      );
    }
    for (const row of this.rows(sql, bindings)) {
      const dateValue = columnText(row[0]);
      const date = dateValue === null ? null : localDay(dateValue);
      const hourValue = columnText(row[1]);
      const dayBytes = columnBlob(row[2]);
      if (
        date === null ||
        hourValue === null ||
        !OfficeHours.isOfficeHour(hourValue) ||
        dayBytes === null
      ) {
        throw invalidContent("A search context is malformed.");
      }
      const hour = hourValue;
      const day = decodedLiturgicalDay(this.decodedPayload(dayBytes));
      let settingModes: readonly string[];
      const scoreValue = row[3];
      if (scoreValue === null || scoreValue === undefined) {
        settingModes = [];
      } else {
        const scoreBytes = columnBlob(scoreValue);
        if (scoreBytes === null) {
          throw invalidContent("A search context score is malformed.");
        }
        const text = this.payloadText(scoreBytes);
        const known = settingModesByScore.get(text);
        if (known !== undefined) {
          settingModes = known;
        } else {
          const score = decodedStoredChantScore(parsedJSON(text));
          settingModes = score.mode === null ? [] : [score.mode];
          settingModesByScore.set(text, settingModes);
        }
      }
      contexts.push({
        observanceID: day.observanceID,
        firstDate: served(segment, date),
        lastDate: served(segment, date),
        hour,
        observanceTitleLatin: day.titleLatin,
        observanceTitleEnglish: day.titleEnglish ?? null,
        occurrenceCount: 1,
        settingModes,
      });
    }
  }

  /** `decodedRecipeHeader(id:statement:payloadColumn:)`. */
  private decodedRecipeHeader(
    id: number,
    payloadColumn: SearchValue | undefined,
  ): StoredRecipeHeader {
    const cached = this.recipeHeaderCache.get(id);
    if (cached !== undefined) {
      this.recipeHeaderCacheHitCount += 1;
      return cached;
    }

    const payloadValue = columnBlob(payloadColumn);
    if (payloadValue === null) {
      throw invalidContent("An office title search payload is missing.");
    }
    const header = decodedStoredRecipeHeader(this.decodedPayload(payloadValue));
    this.recipeHeaderCache.set(id, header);
    this.recipeHeaderInsertionOrder.push(id);

    if (this.recipeHeaderInsertionOrder.length > recipeHeaderCacheLimit) {
      const evictedID = this.recipeHeaderInsertionOrder.shift()!;
      this.recipeHeaderCache.delete(evictedID);
    }
    return header;
  }

  /** `queryInteger(sql:binding:)`: the first column of every row, as bytes. */
  private queryInteger(sql: string, binding: number): Uint8Array[] {
    return this.rows(sql, [binding]).map((row) => {
      const bytes = columnBlob(row[0]);
      if (bytes === null) {
        throw invalidContent("A content row has a null payload.");
      }
      return bytes;
    });
  }

  /** `SharedContentDatabase.metadata(_:key:)`. */
  private metadata(key: string): string | null {
    let rows: SearchValue[][];
    try {
      rows = this.database.rows("SELECT value FROM meta WHERE key=?", [key]);
    } catch {
      throw invalidContent("Cannot read content metadata.");
    }
    if (rows.length === 0) return null;
    const value = columnText(rows[0][0]);
    if (value === null) {
      throw invalidContent("Cannot read content metadata value.");
    }
    return value;
  }

  /**
   * Runs a statement. Swift reports a statement SQLite cannot prepare, bind,
   * or step as `databaseUnavailable` with SQLite's own message.
   */
  private rows(
    sql: string,
    bindings: readonly (string | number)[],
  ): SearchValue[][] {
    try {
      return this.database.rows(sql, bindings);
    } catch (error) {
      throw databaseUnavailable(
        error instanceof Error ? error.message : String(error),
      );
    }
  }

  /** `ContentPayloadCodec.decode(_:)`, as far as the JSON text. */
  private payloadText(payload: Uint8Array): string {
    const decode = this.decodePayload;
    return decode(payload);
  }

  /** `decoder.decode(_:from: ContentPayloadCodec.decode(payload))`, as far as the JSON value. */
  private decodedPayload(payload: Uint8Array): unknown {
    return parsedJSON(this.payloadText(payload));
  }

  /**
   * Swift reads schemas 1 through 4. Of these only schema 3 is ported, so
   * that where Swift would search an older edition by other statements (or,
   * for schema 1, find nothing), a search here says that the schema is not
   * supported.
   */
  private requireSearchOptimizedSchema(): void {
    if (this.schemaVersion !== searchOptimizedSchemaVersion) {
      throw new ContentPackError(this.schemaVersion);
    }
  }
}
