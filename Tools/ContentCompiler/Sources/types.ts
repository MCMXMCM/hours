export const officeHours = [
  "matins",
  "lauds",
  "prime",
  "terce",
  "sext",
  "none",
  "vespers",
  "compline"
] as const;
export type OfficeHour = typeof officeHours[number];

export const reviewStatuses = [
  "exactMatch",
  "humanReviewed",
  "generatedFormula",
  "sourceTranscription",
  "ambiguous",
  "missing"
] as const;
export type ReviewStatus = typeof reviewStatuses[number];

export const chantNotationModifiers = [
  "mora",
  "episema",
  "quilisma",
  "liquescent",
  "flat",
  "natural",
  "sharp",
  "phraseBoundary"
] as const;
export type ChantNotationModifier = typeof chantNotationModifiers[number];

/** The kinds of section a Mass holds, beside the Office's own. */
export const massSectionKinds = [
  "introit",
  "kyrie",
  "gloria",
  "epistle",
  "gradual",
  "alleluia",
  "tract",
  "sequence",
  "gospel",
  "credo",
  "offertory",
  "secret",
  "preface",
  "sanctus",
  "canon",
  "paterNoster",
  "agnusDei",
  "communion",
  "postcommunion",
  "dismissal",
  "lastGospel"
] as const;
export type MassSectionKind = typeof massSectionKinds[number];

export const officeSectionKinds = [
  "opening",
  "invitatory",
  "prayer",
  "rubric",
  "reading",
  "absolution",
  "blessing",
  "psalm",
  "antiphon",
  "chapter",
  "responsory",
  "hymn",
  "versicle",
  "canticle",
  "collect",
  "preces",
  "conclusion",
  "marianAntiphon",
  // The parts of the Mass, beside the Office's own (missalImport.ts).
  ...massSectionKinds
] as const;
export type OfficeSectionKind = typeof officeSectionKinds[number];

export const liturgicalRanks = [
  "firstClass",
  "secondClass",
  "thirdClass",
  "fourthClass"
] as const;
export type LiturgicalRank = typeof liturgicalRanks[number];

export const liturgicalColors = [
  "white",
  "red",
  "green",
  "violet",
  "rose",
  "black"
] as const;
export type LiturgicalColor = typeof liturgicalColors[number];

export const eveningContexts = [
  "firstVespers",
  "secondVespers",
  "ferialVespers"
] as const;
export type EveningContext = typeof eveningContexts[number];

export const documentFormats = [
  "authoritativeOrdered",
  "sourceOrdered",
  "legacyReconstructed",
  "contentUnavailable",
  /** A Mass of the Missal, in the order of its source. */
  "missal"
] as const;
export type OfficeDocumentFormat = typeof documentFormats[number];

export interface LocalDay {
  year: number;
  month: number;
  day: number;
}

export interface SourcePin {
  name: string;
  revision: string;
  license: string;
  url: string;
  checksum: string;
  notice?: string | null;
  modifications?: string | null;
  correspondingSource?: string | null;
}

export interface ChantEvent {
  id: string;
  phraseID: string;
  syllableID: string;
  syllable: string;
  relativePitch: number;
  durationWeight: number;
  modifiers: ChantNotationModifier[];
  clef?: ChantClef | null;
}

export interface ChantClef {
  kind: "c" | "f";
  line: 1 | 2 | 3 | 4;
  flattensB: boolean;
}

export interface ChantTimeline {
  events: ChantEvent[];
}

export interface ChantScore {
  id: string;
  incipit: string;
  gabc: string;
  mode?: string | null;
  reviewStatus: ReviewStatus;
  provenance: {
    collection: string;
    sourceBook: string;
    sourceURL?: string | null;
    license: string;
    snapshot: string;
    sourceRevision?: string | null;
    notice?: string | null;
    modifications?: string | null;
    correspondingSource?: string | null;
  };
  timeline: ChantTimeline;
}

export interface OfficeSection {
  id: string;
  kind: OfficeSectionKind;
  title: string;
  titleEnglish?: string | null;
  latin: string;
  english?: string | null;
  rubric?: string | null;
  rubricEnglish?: string | null;
  chant?: ChantScore | null;
  /** In a Mass, whether the section is of the Ordinary rather than proper
   * to the day; the reader can show the propers alone. */
  ordinary?: boolean;
}

export interface OfficeObservance {
  observanceID: string;
  titleLatin: string;
  titleEnglish?: string | null;
  rank?: LiturgicalRank | null;
  sourceRank?: string | null;
  color?: LiturgicalColor | null;
  season?: string | null;
  eveningContext?: EveningContext | null;
  commemorations: Array<{ id: string; titleLatin: string; titleEnglish?: string | null }>;
}

export interface OfficeDocument {
  id: string;
  date: LocalDay;
  hour: OfficeHour;
  titleLatin: string;
  titleEnglish?: string | null;
  contextLabel: string;
  sourceVersion: string;
  format?: OfficeDocumentFormat;
  visibleContentDigest?: string | null;
  observance?: OfficeObservance | null;
  sections: OfficeSection[];
}

export interface LiturgicalDay {
  date: LocalDay;
  observanceID: string;
  titleLatin: string;
  titleEnglish?: string | null;
  rank?: LiturgicalRank | null;
  sourceRank?: string | null;
  color?: LiturgicalColor | null;
  season: string;
  eveningContext?: EveningContext | null;
  commemorations: Array<{ id: string; titleLatin: string; titleEnglish?: string | null }>;
  sourceVersion: string;
}

export interface Coverage {
  startDate: LocalDay;
  endDate: LocalDay;
  /**
   * The civil years a perennial edition stores, in order. Such an edition
   * serves every date from `startDate` through `endDate`, reading each from
   * the stored year of its year type (see yearTypes.ts), and its office
   * counts are those of the stored years. Absent where every date served is
   * stored.
   */
  storedYears?: number[] | null;
  reviewedCenterYear?: number | null;
  expectedOfficeCount: number;
  generatedOfficeCount: number;
  authoritativeOfficeCount?: number | null;
  unresolvedScoreCount: number;
  ambiguousScoreCount: number;
  isSample: boolean;
}

export interface Manifest {
  schemaVersion: number;
  corpusVersion: string;
  minimumAppVersion: string;
  createdAt: string;
  rubrics: string;
  sources: SourcePin[];
  coverage: Coverage;
  packSHA256: string;
  packURL?: string | null;
  signature: string;
  compilerRevision?: string | null;
  normalizedCounts?: {
    textResources: number;
    scoredChantRealizations: number;
    recipes: number;
    scheduledOffices: number;
  } | null;
  notices?: string[];
}

export interface CorpusInput {
  manifest: Manifest;
  days: LiturgicalDay[];
  offices: OfficeDocument[];
}

/**
 * Compiler-only normalized input. A recipe is stored once and the civil-date
 * schedule refers to it by key; callers never need to materialize hundreds of
 * thousands of duplicate OfficeDocument values in memory.
 */
export interface ScheduledCorpusInput {
  manifest: Manifest;
  days: LiturgicalDay[];
  recipes: Array<{
    key: string;
    office: OfficeDocument;
  }>;
  schedule: Array<{
    date: LocalDay;
    hour: OfficeHour;
    recipeKey: string;
  }>;
}
