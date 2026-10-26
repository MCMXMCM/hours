// The contract between the web corpus exporter and the Hours web app.
//
// The web app never opens SQLite to pray an hour. Each distinct office is one
// immutable JSON file named by the hash of its contents; a small file per
// month maps civil dates to those offices; and a pointer names the release
// each edition currently serves. This module is imported by the exporter
// (Node) and by the browser, so it must remain free of Node-only imports.

import type {
  ChantScore,
  LiturgicalDay,
  OfficeDocumentFormat,
  OfficeHour,
  OfficeObservance,
  OfficeSectionKind,
  SourcePin
} from "./types.ts";

/**
 * The schema of the pointer, the manifests and the months. Schema 2 admits a
 * perennial edition, which stores one civil year of each year type and whose
 * Prime holds tokens for the Martyrology's Moon and year in both editions; a
 * reader of schema 1 would show such an edition wrongly, and is told that it
 * is out of date by the pointer.
 */
export const webCorpusSchema = 2;

/**
 * The schema of an office file. It is its own number because an office is
 * named by the hash of its contents: an office that has not changed keeps
 * its file through a change to the rest of the layout.
 */
export const webOfficeSchema = 1;

export const webEditions = ["roman1960", "roman1954"] as const;
export type WebEdition = typeof webEditions[number];

/** The rubrics string a compiled edition declares, by edition. */
export const webEditionRubrics: Record<WebEdition, string> = {
  roman1960: "Rubrics 1960 - 1960",
  roman1954: "Divino Afflatu - 1954"
};

export function webEditionForRubrics(rubrics: string): WebEdition | null {
  return webEditions.find(edition => webEditionRubrics[edition] === rubrics) ?? null;
}

/**
 * A chant as the browser receives it. The compiled timeline is omitted: the
 * browser derives it from the GABC with the compiler's own parser, and the
 * exporter refuses to write a score whose stored timeline that parser does
 * not reproduce exactly.
 */
export type WebChantScore = Omit<ChantScore, "timeline">;

export interface WebOfficeSection {
  kind: OfficeSectionKind;
  title: string;
  titleEnglish?: string | null;
  rubric?: string | null;
  rubricEnglish?: string | null;
  latin: string;
  english?: string | null;
  chant?: WebChantScore | null;
  /** In a Mass, whether the section is of the Ordinary rather than proper
   * to the day. */
  ordinary?: boolean;
}

/**
 * One distinct office: everything an hour contains except the civil date on
 * which it is prayed. Section and document identifiers are date-specific and
 * are assigned by the reader, as the native repository assigns them.
 */
export interface WebOffice {
  schema: typeof webOfficeSchema;
  hour: OfficeHour;
  titleLatin: string;
  titleEnglish?: string | null;
  contextLabel: string;
  sourceVersion: string;
  format?: OfficeDocumentFormat | null;
  visibleContentDigest?: string | null;
  observance?: OfficeObservance | null;
  sections: WebOfficeSection[];
}

/**
 * One of the Masses of a civil date (missalCorpus.ts): its document is a
 * `WebOffice` of the format "missal", named by its key as an office is.
 */
export interface WebMassListing {
  key: string;
  titleLatin: string;
  titleEnglish?: string | null;
  /** The name that tells a day's Masses apart ("Ad Missam in nocte"). */
  label?: string | null;
  labelEnglish?: string | null;
}

export interface WebMonthDay extends LiturgicalDay {
  /** The key of the office prayed at each hour of this civil date. */
  offices: Partial<Record<OfficeHour, string>>;
  /**
   * The Masses of this civil date, in the Missal's order. Absent from an
   * export made without the edition's Missal; a reader that does not know
   * the field passes it by.
   */
  masses?: WebMassListing[];
}

/**
 * A stored civil month. A perennial edition serves the same month of every
 * year of the stored year's type from it; the reader gives its days the
 * dates on which they are prayed.
 */
export interface WebMonth {
  schema: typeof webCorpusSchema;
  edition: WebEdition;
  /** `YYYY-MM`. */
  month: string;
  days: WebMonthDay[];
}

/**
 * An edition's searchable library: the compiled SQLite database, without
 * what a browser has no use for, as it is fetched for searching. The web app
 * runs on it the queries the native app runs on the edition itself. Where
 * the edition was exported with its Missal, the library also holds the
 * Missal's days (`missal_days`), the titles and sections of its Masses
 * (`missal_masses`), its texts (`missal_texts`) and scores (`missal_scores`)
 * and its manifest (`missal_manifest` in `meta`), for the searches of titles
 * and of the Mass's parts; and, where it was exported with the Kyriale too,
 * the Kyriale's settings of the Ordinary (`kyriale_settings`, with
 * `kyriale_manifest` in `meta`).
 */
export interface WebLibrary {
  /** Where the Brotli-compressed database lies within the corpus. */
  path: string;
  /** The size of the database, and of the file that carries it. */
  bytes: number;
  compressedBytes: number;
  /** SHA-256 of the database. */
  sha256: string;
}

/**
 * Changes whenever the exporter writes a library differently. Format 2 adds
 * the Missal's days and the titles of its Masses; format 3 the sections of
 * its Masses, its texts and scores, and the Kyriale's settings.
 */
export const webLibraryFormat = 3;

export interface WebEditionManifest {
  schema: typeof webCorpusSchema;
  edition: WebEdition;
  /** Names this export; it changes whenever any exported byte changes. */
  release: string;
  corpusVersion: string;
  rubrics: string;
  /** True for a source edition whose independent review is still pending. */
  isSample: boolean;
  /** The first and last civil dates the edition serves, as `YYYY-MM-DD`. */
  coverage: { startDate: string; endDate: string };
  /**
   * The civil years a perennial edition stores, in order: it serves every
   * date of `coverage`, each from the stored year of its year type (see
   * `yearTypes.ts`). Absent where every date served is stored.
   */
  storedYears?: number[] | null;
  /** The stored months present in this export, in order. A development export may hold only some. */
  months: string[];
  normalization: "NFC";
  counts: { scheduledOffices: number; distinctOffices: number; scores: number };
  sources: SourcePin[];
  notices: string[];
  /** Absent from an export made without one; the web app then offers no search. */
  library?: WebLibrary | null;
}

export interface WebCorpusPointer {
  schema: typeof webCorpusSchema;
  editions: Partial<Record<WebEdition, { release: string; manifest: string }>>;
}

export const webCorpusPointerPath = "current.json";

export function webOfficePath(key: string): string {
  return `o/${key.slice(0, 2)}/${key}.json`;
}

export function webManifestPath(edition: WebEdition, release: string): string {
  return `${edition}/${release}/manifest.json`;
}

/** A library is named for the compiled edition (and Missal) it was made from. */
export function webLibraryPath(edition: WebEdition, sourceKey: string): string {
  return `${edition}/library/${sourceKey}.v${webLibraryFormat}.sqlite.br`;
}

export function webMonthPath(edition: WebEdition, release: string, month: string): string {
  return `${edition}/${release}/months/${month}.json`;
}
