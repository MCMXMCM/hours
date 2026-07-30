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
  "marianAntiphon"
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
  "legacyReconstructed",
  "contentUnavailable"
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
  };
  timeline: ChantTimeline;
}

export interface OfficeSection {
  id: string;
  kind: OfficeSectionKind;
  title: string;
  latin: string;
  english?: string | null;
  rubric?: string | null;
  chant?: ChantScore | null;
}

export interface OfficeObservance {
  observanceID: string;
  titleLatin: string;
  titleEnglish?: string | null;
  rank?: LiturgicalRank | null;
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
  color?: LiturgicalColor | null;
  season: string;
  eveningContext?: EveningContext | null;
  commemorations: Array<{ id: string; titleLatin: string; titleEnglish?: string | null }>;
  sourceVersion: string;
}

export interface Coverage {
  startDate: LocalDay;
  endDate: LocalDay;
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
}

export interface CorpusInput {
  manifest: Manifest;
  days: LiturgicalDay[];
  offices: OfficeDocument[];
}
