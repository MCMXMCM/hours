// The payloads search reads from an edition's database, decoded as
// `JSONDecoder.hoursContentDecoder` decodes them into `StoredTextResource`
// and `StoredRecipeHeader` (private to `HoursCore/ContentRepository.swift`),
// `LiturgicalDay`, and `ChantScore`.
//
// A synthesized `Decodable` conformance requires every property that is not
// optional, refuses a value of another type, and refuses a raw value its enum
// does not declare; the functions below do the same, in the order of the
// Swift declarations, and fail with the description Foundation gives the
// corresponding `DecodingError`. A key Swift does not declare is passed over.

import { parseGABC } from "@compiler/gabc.ts";
import {
  officeHours,
  officeSectionKinds,
  type ChantClef,
  type ChantEvent,
  type ChantNotationModifier,
  type ChantProvenance,
  type ChantReviewStatus,
  type ChantScore,
  type ChantTimeline,
  type Commemoration,
  type EveningContext,
  type LiturgicalColor,
  type LiturgicalDay,
  type LiturgicalRank,
  type LocalDay,
  type OfficeDocumentFormat,
  type OfficeHour,
  type OfficeObservance,
  type OfficeSectionKind,
} from "@/core/models.ts";

/** The case of Swift's `DecodingError` that a failure stands for. */
export type DecodingErrorKind =
  "keyNotFound" | "valueNotFound" | "typeMismatch" | "dataCorrupted";

/**
 * A failure of `JSONDecoder.decode(_:from:)`. `message` is the error's
 * `localizedDescription`, which is all the search screen shows of it.
 */
export class DecodingError extends Error {
  readonly kind: DecodingErrorKind;

  constructor(kind: DecodingErrorKind) {
    super(
      kind === "keyNotFound" || kind === "valueNotFound"
        ? "The data couldn’t be read because it is missing."
        : "The data couldn’t be read because it isn’t in the correct format.",
    );
    this.name = "DecodingError";
    this.kind = kind;
  }
}

// The raw values of the Swift enums a payload may name.
const liturgicalRanks: readonly LiturgicalRank[] = [
  "firstClass",
  "secondClass",
  "thirdClass",
  "fourthClass",
];
const liturgicalColors: readonly LiturgicalColor[] = [
  "white",
  "red",
  "green",
  "violet",
  "rose",
  "black",
];
const eveningContexts: readonly EveningContext[] = [
  "firstVespers",
  "secondVespers",
  "ferialVespers",
];
const officeDocumentFormats: readonly OfficeDocumentFormat[] = [
  "authoritativeOrdered",
  "sourceOrdered",
  "legacyReconstructed",
  "contentUnavailable",
];
const chantReviewStatuses: readonly ChantReviewStatus[] = [
  "exactMatch",
  "humanReviewed",
  "generatedFormula",
  "sourceTranscription",
  "ambiguous",
  "missing",
];
const chantNotationModifiers: readonly ChantNotationModifier[] = [
  "mora",
  "episema",
  "quilisma",
  "liquescent",
  "flat",
  "natural",
  "sharp",
  "phraseBoundary",
];
const chantClefKinds: readonly ChantClef["kind"][] = ["c", "f"];

type Container = Readonly<Record<string, unknown>>;

/** `decoder.container(keyedBy:)`. */
function container(value: unknown): Container {
  if (value === null || value === undefined) {
    throw new DecodingError("valueNotFound");
  }
  if (typeof value !== "object" || Array.isArray(value)) {
    throw new DecodingError("typeMismatch");
  }
  return value as Container;
}

/** `container.contains(_:)`. */
function contains(keyed: Container, key: string): boolean {
  return Object.hasOwn(keyed, key);
}

/** The value `decode(_:forKey:)` reads: present, and not null. */
function required(keyed: Container, key: string): unknown {
  if (!contains(keyed, key)) throw new DecodingError("keyNotFound");
  const value = keyed[key];
  if (value === null) throw new DecodingError("valueNotFound");
  return value;
}

/** `decodeIfPresent(_:forKey:)`: nil for an absent key or a null. */
function optional<Value>(
  keyed: Container,
  key: string,
  decode: (value: unknown) => Value,
): Value | null {
  if (!contains(keyed, key)) return null;
  const value = keyed[key];
  return value === null ? null : decode(value);
}

function string(value: unknown): string {
  if (typeof value !== "string") throw new DecodingError("typeMismatch");
  return value;
}

/** An `Int`: a JSON number without a fraction ("1.0" is one). */
function int(value: unknown): number {
  if (typeof value !== "number") throw new DecodingError("typeMismatch");
  if (!Number.isInteger(value)) throw new DecodingError("dataCorrupted");
  return value;
}

function double(value: unknown): number {
  if (typeof value !== "number") throw new DecodingError("typeMismatch");
  return value;
}

function bool(value: unknown): boolean {
  if (typeof value !== "boolean") throw new DecodingError("typeMismatch");
  return value;
}

function array<Element>(
  value: unknown,
  decode: (element: unknown) => Element,
): Element[] {
  if (!Array.isArray(value)) throw new DecodingError("typeMismatch");
  return value.map((element) => {
    if (element === null) throw new DecodingError("valueNotFound");
    return decode(element);
  });
}

/** An enum with String raw values. */
function rawValue<Case extends string>(
  cases: readonly Case[],
): (value: unknown) => Case {
  return (value) => {
    const raw = string(value);
    const found = cases.find((candidate) => candidate === raw);
    if (found === undefined) throw new DecodingError("dataCorrupted");
    return found;
  };
}

const officeSectionKind = rawValue<OfficeSectionKind>(officeSectionKinds);
const officeHour = rawValue<OfficeHour>(officeHours);
const liturgicalRank = rawValue(liturgicalRanks);
const liturgicalColor = rawValue(liturgicalColors);
const eveningContext = rawValue(eveningContexts);
const officeDocumentFormat = rawValue(officeDocumentFormats);
const chantReviewStatus = rawValue(chantReviewStatuses);
const chantNotationModifier = rawValue(chantNotationModifiers);
const chantClefKind = rawValue(chantClefKinds);

/** `JSONDecoder.decode(_:from:)`'s reading of the text itself. */
export function parsedJSON(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    throw new DecodingError("dataCorrupted");
  }
}

export interface StoredTextResource {
  readonly kind: OfficeSectionKind;
  readonly title: string;
  readonly titleEnglish: string | null;
  readonly rubric: string | null;
  readonly rubricEnglish: string | null;
  readonly latin: string;
  readonly english: string | null;
}

export function decodedStoredTextResource(json: unknown): StoredTextResource {
  const keyed = container(json);
  return {
    kind: officeSectionKind(required(keyed, "kind")),
    title: string(required(keyed, "title")),
    titleEnglish: optional(keyed, "titleEnglish", string),
    rubric: optional(keyed, "rubric", string),
    rubricEnglish: optional(keyed, "rubricEnglish", string),
    latin: string(required(keyed, "latin")),
    english: optional(keyed, "english", string),
  };
}

function decodedCommemoration(json: unknown): Commemoration {
  const keyed = container(json);
  return {
    id: string(required(keyed, "id")),
    titleLatin: string(required(keyed, "titleLatin")),
    titleEnglish: optional(keyed, "titleEnglish", string),
  };
}

function decodedOfficeObservance(json: unknown): OfficeObservance {
  const keyed = container(json);
  return {
    observanceID: string(required(keyed, "observanceID")),
    titleLatin: string(required(keyed, "titleLatin")),
    titleEnglish: optional(keyed, "titleEnglish", string),
    rank: optional(keyed, "rank", liturgicalRank),
    sourceRank: optional(keyed, "sourceRank", string),
    color: optional(keyed, "color", liturgicalColor),
    season: optional(keyed, "season", string),
    eveningContext: optional(keyed, "eveningContext", eveningContext),
    commemorations: array(
      required(keyed, "commemorations"),
      decodedCommemoration,
    ),
  };
}

export interface StoredRecipeHeader {
  readonly hour: OfficeHour;
  readonly titleLatin: string;
  readonly titleEnglish: string | null;
  readonly contextLabel: string;
  readonly sourceVersion: string;
  readonly format: OfficeDocumentFormat | null;
  readonly visibleContentDigest: string | null;
  readonly observance: OfficeObservance | null;
}

export function decodedStoredRecipeHeader(json: unknown): StoredRecipeHeader {
  const keyed = container(json);
  return {
    hour: officeHour(required(keyed, "hour")),
    titleLatin: string(required(keyed, "titleLatin")),
    titleEnglish: optional(keyed, "titleEnglish", string),
    contextLabel: string(required(keyed, "contextLabel")),
    sourceVersion: string(required(keyed, "sourceVersion")),
    format: optional(keyed, "format", officeDocumentFormat),
    visibleContentDigest: optional(keyed, "visibleContentDigest", string),
    observance: optional(keyed, "observance", decodedOfficeObservance),
  };
}

function decodedLocalDay(json: unknown): LocalDay {
  const keyed = container(json);
  return {
    year: int(required(keyed, "year")),
    month: int(required(keyed, "month")),
    day: int(required(keyed, "day")),
  };
}

export function decodedLiturgicalDay(json: unknown): LiturgicalDay {
  const keyed = container(json);
  return {
    date: decodedLocalDay(required(keyed, "date")),
    observanceID: string(required(keyed, "observanceID")),
    titleLatin: string(required(keyed, "titleLatin")),
    titleEnglish: optional(keyed, "titleEnglish", string),
    rank: optional(keyed, "rank", liturgicalRank),
    sourceRank: optional(keyed, "sourceRank", string),
    color: optional(keyed, "color", liturgicalColor),
    season: string(required(keyed, "season")),
    eveningContext: optional(keyed, "eveningContext", eveningContext),
    commemorations: array(
      required(keyed, "commemorations"),
      decodedCommemoration,
    ),
    sourceVersion: string(required(keyed, "sourceVersion")),
  };
}

function decodedChantClef(json: unknown): ChantClef {
  const keyed = container(json);
  return {
    kind: chantClefKind(required(keyed, "kind")),
    line: int(required(keyed, "line")),
    flattensB: bool(required(keyed, "flattensB")),
  };
}

/** `ChantEvent.CompactClef`, as a `ChantClef`. */
function decodedCompactClef(json: unknown): ChantClef {
  const keyed = container(json);
  return {
    kind: chantClefKind(required(keyed, "k")),
    line: int(required(keyed, "l")),
    flattensB: bool(required(keyed, "b")),
  };
}

/**
 * `ChantEvent.init(from:)`: an event is stored under its property names, or
 * under the compact keys the compiler writes.
 */
function decodedChantEvent(json: unknown): ChantEvent {
  const keyed = container(json);
  if (contains(keyed, "id")) {
    return {
      id: string(required(keyed, "id")),
      phraseID: string(required(keyed, "phraseID")),
      syllableID: string(required(keyed, "syllableID")),
      syllable: string(required(keyed, "syllable")),
      relativePitch: int(required(keyed, "relativePitch")),
      durationWeight: double(required(keyed, "durationWeight")),
      modifiers: array(required(keyed, "modifiers"), chantNotationModifier),
      clef: optional(keyed, "clef", decodedChantClef),
    };
  }
  return {
    id: string(required(keyed, "i")),
    phraseID: string(required(keyed, "p")),
    syllableID: string(required(keyed, "y")),
    syllable: string(required(keyed, "s")),
    relativePitch: int(required(keyed, "n")),
    durationWeight: double(required(keyed, "d")),
    modifiers: array(required(keyed, "m"), chantNotationModifier),
    clef: optional(keyed, "c", decodedCompactClef),
  };
}

function decodedChantTimeline(json: unknown): ChantTimeline {
  const keyed = container(json);
  return { events: array(required(keyed, "events"), decodedChantEvent) };
}

// Swift's `ChantProvenance` holds the first five properties. The web model
// also carries what the compiler stores of a source's terms, as an office's
// own chants do when the reader loads them; Swift passes those keys over,
// and so no value of theirs is refused here.
const carriedProvenanceKeys = [
  "sourceRevision",
  "notice",
  "modifications",
  "correspondingSource",
] as const;

function decodedChantProvenance(json: unknown): ChantProvenance {
  const keyed = container(json);
  const carried: {
    -readonly [Key in (typeof carriedProvenanceKeys)[number]]?: string;
  } = {};
  for (const key of carriedProvenanceKeys) {
    const value = keyed[key];
    if (typeof value === "string") carried[key] = value;
  }
  return {
    collection: string(required(keyed, "collection")),
    sourceBook: string(required(keyed, "sourceBook")),
    // A `URL?` in Swift, which refuses the one string `URL(string:)` does.
    sourceURL: optional(keyed, "sourceURL", (value) => {
      const text = string(value);
      if (text.length === 0) throw new DecodingError("dataCorrupted");
      return text;
    }),
    license: string(required(keyed, "license")),
    snapshot: string(required(keyed, "snapshot")),
    ...carried,
  };
}

/**
 * A `ChantScore` as an edition stores it. The database the native app reads
 * stores the score's timeline; the library the web app searches does not,
 * and `timeline` is then `null`.
 */
export interface StoredChantScore {
  readonly id: string;
  readonly incipit: string;
  readonly gabc: string;
  readonly mode: string | null;
  readonly reviewStatus: ChantReviewStatus;
  readonly provenance: ChantProvenance;
  readonly timeline: ChantTimeline | null;
}

export function decodedStoredChantScore(json: unknown): StoredChantScore {
  const keyed = container(json);
  return {
    id: string(required(keyed, "id")),
    incipit: string(required(keyed, "incipit")),
    gabc: string(required(keyed, "gabc")),
    mode: optional(keyed, "mode", string),
    reviewStatus: chantReviewStatus(required(keyed, "reviewStatus")),
    provenance: decodedChantProvenance(required(keyed, "provenance")),
    timeline: optional(keyed, "timeline", decodedChantTimeline),
  };
}

/**
 * The score Swift decodes. A timeline the library leaves out is derived from
 * the GABC by the compiler's own parser, which the library's exporter has
 * verified to reproduce the stored timeline of every score.
 */
export function chantScore(stored: StoredChantScore): ChantScore {
  return {
    id: stored.id,
    incipit: stored.incipit,
    gabc: stored.gabc,
    mode: stored.mode,
    reviewStatus: stored.reviewStatus,
    provenance: stored.provenance,
    timeline: stored.timeline ?? parseGABC(stored.gabc, stored.id),
  };
}
