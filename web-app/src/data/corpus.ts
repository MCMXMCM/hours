// Reads the Office from the static corpus the exporter writes (see
// Tools/ContentCompiler/Sources/webCorpusFormat.ts): a pointer to the
// release each edition serves, one small index per stored month, and one
// immutable file per distinct office. A perennial edition stores one civil
// year of each year type, and a date is read from the stored year of its
// type (Tools/ContentCompiler/Sources/yearTypes.ts).

import { parseGABC } from "@compiler/gabc.ts";
import {
  webCorpusPointerPath,
  webCorpusSchema,
  webMonthPath,
  webOfficePath,
  type WebCorpusPointer,
  type WebEdition,
  type WebEditionManifest,
  type WebMassListing,
  type WebMonth,
  type WebMonthDay,
  type WebOffice,
} from "@compiler/webCorpusFormat.ts";
import {
  perennialYearPlan,
  storedYear,
  type PerennialYearPlan,
} from "@compiler/yearTypes.ts";
import {
  LocalDays,
  type LiturgicalDay,
  type LocalDay,
  type OfficeDocument,
  type OfficeHour,
  type OfficeSection,
} from "@/core/models.ts";
import { RomanMartyrologyCalendar } from "@/core/romanMartyrology.ts";
import { retryingFetch, type Fetcher } from "./retryingFetch.ts";

export type {
  WebEdition,
  WebEditionManifest,
  WebMassListing,
} from "@compiler/webCorpusFormat.ts";

export type CorpusFailure =
  /** The date lies outside the edition, or outside what this build carries. */
  | "unavailable"
  /** The corpus could not be reached. */
  | "offline"
  /** The corpus is newer than this copy of the app understands. */
  | "outdated";

export class CorpusError extends Error {
  readonly failure: CorpusFailure;

  constructor(failure: CorpusFailure, message: string) {
    super(message);
    this.name = "CorpusError";
    this.failure = failure;
  }
}

export type { Fetcher } from "./retryingFetch.ts";

/** An edition's searchable library, as the search worker is told of it. */
export interface CorpusLibrary {
  readonly url: string;
  readonly bytes: number;
  readonly compressedBytes: number;
  readonly name: string;
}

/** A day of the calendar, with the key of the office prayed at each hour. */
export interface CalendarDay extends LiturgicalDay {
  readonly offices: Partial<Record<OfficeHour, string>>;
  /** The day's Masses, where the corpus has the edition's Missal. */
  readonly masses?: readonly WebMassListing[];
}

function monthOf(day: LocalDay): string {
  return LocalDays.description(day).slice(0, 7);
}

/**
 * A stored office or Mass as a document of a civil date: each section with
 * its identifier and the timeline of its chant, the rest as stored.
 */
function storedDocument(
  id: string,
  sectionPrefix: string,
  date: LocalDay,
  stored: WebOffice,
): OfficeDocument {
  const sections: OfficeSection[] = stored.sections.map(
    (section, position) => ({
      id: `${sectionPrefix}-section-${position}`,
      kind: section.kind,
      title: section.title,
      titleEnglish: section.titleEnglish ?? null,
      rubric: section.rubric ?? null,
      rubricEnglish: section.rubricEnglish ?? null,
      latin: section.latin,
      english: section.english ?? null,
      chant: section.chant
        ? {
            ...section.chant,
            // The exporter has verified that this reproduces the compiled timeline.
            timeline: parseGABC(section.chant.gabc, section.chant.id),
          }
        : null,
      ...(section.ordinary ? { ordinary: true } : {}),
    }),
  );
  return {
    id,
    date,
    hour: stored.hour,
    titleLatin: stored.titleLatin,
    titleEnglish: stored.titleEnglish ?? null,
    contextLabel: stored.contextLabel,
    sourceVersion: stored.sourceVersion,
    format: stored.format ?? null,
    visibleContentDigest: stored.visibleContentDigest ?? null,
    observance: stored.observance ?? null,
    sections,
  };
}

/**
 * The office of a civil date, assembled from its stored form exactly as the
 * native repository assembles it: date-bearing identifiers, the timeline of
 * each chant, and the Martyrology's proclamation of the following day.
 */
export function officeDocument(
  edition: WebEdition,
  date: LocalDay,
  hour: OfficeHour,
  stored: WebOffice,
): OfficeDocument {
  const day = LocalDays.description(date);
  return RomanMartyrologyCalendar.materialize(
    storedDocument(
      `${edition === "roman1960" ? "" : `${edition}:`}${day}-${hour}`,
      `${day}-${hour}`,
      date,
      stored,
    ),
  );
}

/**
 * A Mass of a civil date, as the native repository makes it a document
 * (SQLiteMissalRepository): identifiers of its own, beside the Hours'.
 */
export function massDocument(
  edition: WebEdition,
  date: LocalDay,
  index: number,
  stored: WebOffice,
): OfficeDocument {
  const day = LocalDays.description(date);
  return storedDocument(
    `missa:${edition}:${day}:${index + 1}`,
    `${day}-missa${index + 1}`,
    date,
    stored,
  );
}

export class Corpus {
  private readonly base: string;
  private readonly fetcher: Fetcher;
  private pointerRequest: Promise<WebCorpusPointer> | null = null;
  private readonly manifests = new Map<
    WebEdition,
    Promise<WebEditionManifest>
  >();
  private readonly plans = new Map<
    WebEdition,
    Promise<PerennialYearPlan | null>
  >();
  private readonly storedMonths = new Map<string, Promise<WebMonth>>();
  private readonly months = new Map<string, Promise<CalendarDay[]>>();
  private readonly offices = new Map<string, Promise<WebOffice>>();

  constructor(base = "/corpus/", fetcher: Fetcher = retryingFetch) {
    this.base = base.endsWith("/") ? base : `${base}/`;
    this.fetcher = fetcher;
  }

  private async read<T extends { schema?: number }>(
    path: string,
    init?: RequestInit,
  ): Promise<T> {
    let response: Response;
    try {
      response = await this.fetcher(this.base + path, init);
    } catch {
      throw new CorpusError(
        "offline",
        `The Office could not be reached (${path}).`,
      );
    }
    if (response.status === 404 || response.status === 403) {
      throw new CorpusError("unavailable", `The Office has no ${path}.`);
    }
    if (!response.ok) {
      throw new CorpusError(
        "offline",
        `The Office answered ${response.status} for ${path}.`,
      );
    }
    const value = (await response.json()) as T;
    if (typeof value.schema === "number" && value.schema > webCorpusSchema) {
      throw new CorpusError(
        "outdated",
        "This copy of Hours is older than the Office it found.",
      );
    }
    return value;
  }

  private remember<Key, Value>(
    cache: Map<Key, Promise<Value>>,
    key: Key,
    load: () => Promise<Value>,
  ): Promise<Value> {
    let request = cache.get(key);
    if (!request) {
      request = load();
      cache.set(key, request);
      // A failure is not remembered; the next reader tries again.
      request.catch(() => cache.delete(key));
    }
    return request;
  }

  /** The release each edition currently serves. Never taken from a stale cache. */
  pointer(): Promise<WebCorpusPointer> {
    if (!this.pointerRequest) {
      this.pointerRequest = this.read<WebCorpusPointer>(webCorpusPointerPath, {
        cache: "no-cache",
      });
      this.pointerRequest.catch(() => {
        this.pointerRequest = null;
      });
    }
    return this.pointerRequest;
  }

  manifest(edition: WebEdition): Promise<WebEditionManifest> {
    return this.remember(this.manifests, edition, async () => {
      const entry = (await this.pointer()).editions[edition];
      if (!entry) {
        throw new CorpusError(
          "unavailable",
          `This build does not carry the ${edition} edition.`,
        );
      }
      return this.read<WebEditionManifest>(entry.manifest);
    });
  }

  /**
   * Where the edition's searchable library lies and how large it is, or
   * `null` when this corpus was exported without one.
   */
  async library(edition: WebEdition): Promise<CorpusLibrary | null> {
    const library = (await this.manifest(edition)).library;
    if (!library) return null;
    const file = library.path.split("/").at(-1) ?? library.path;
    return {
      url: this.base + library.path,
      bytes: library.bytes,
      compressedBytes: library.compressedBytes,
      // Kept under a name that changes when the library does.
      name: `${edition}-${file.replace(/\.sqlite\.br$/, "")}`,
    };
  }

  /** The first and last civil dates the edition serves. */
  async coverage(
    edition: WebEdition,
  ): Promise<{ start: LocalDay; end: LocalDay }> {
    const manifest = await this.manifest(edition);
    return {
      start: LocalDays.fromISO(manifest.coverage.startDate)!,
      end: LocalDays.fromISO(manifest.coverage.endDate)!,
    };
  }

  /**
   * The plan by which a perennial edition serves more years than it stores;
   * `null` for an edition that stores every date it serves.
   */
  private plan(edition: WebEdition): Promise<PerennialYearPlan | null> {
    return this.remember(this.plans, edition, async () => {
      const manifest = await this.manifest(edition);
      if (!manifest.storedYears) return null;
      return perennialYearPlan(
        Number(manifest.coverage.startDate.slice(0, 4)),
        Number(manifest.coverage.endDate.slice(0, 4)),
        manifest.storedYears,
      );
    });
  }

  /** A stored month, as the exporter wrote it. */
  private storedMonth(edition: WebEdition, month: string): Promise<WebMonth> {
    return this.remember(this.storedMonths, `${edition}:${month}`, async () => {
      const manifest = await this.manifest(edition);
      if (!manifest.months.includes(month)) {
        throw new CorpusError(
          "unavailable",
          `${month} is outside the ${edition} edition.`,
        );
      }
      return this.read<WebMonth>(
        webMonthPath(edition, manifest.release, month),
      );
    });
  }

  /**
   * The days of a civil month under the dates on which they are prayed, read
   * from the stored month that serves it.
   */
  private month(edition: WebEdition, month: string): Promise<CalendarDay[]> {
    return this.remember(this.months, `${edition}:${month}`, async () => {
      const plan = await this.plan(edition);
      if (!plan) {
        const index = await this.storedMonth(edition, month);
        return index.days satisfies WebMonthDay[] as CalendarDay[];
      }
      const year = Number(month.slice(0, 4));
      const stored = storedYear(plan, year);
      if (stored === null) {
        throw new CorpusError(
          "unavailable",
          `${month} is outside the ${edition} edition.`,
        );
      }
      const index = await this.storedMonth(
        edition,
        `${String(stored).padStart(4, "0")}${month.slice(4)}`,
      );
      if (stored === year) {
        return index.days satisfies WebMonthDay[] as CalendarDay[];
      }
      // Years of one type are of one length, so every day of the stored
      // month has its day in the month served.
      return index.days.map((day) => ({
        ...day,
        date: LocalDays.make(year, day.date.month, day.date.day),
      }));
    });
  }

  /** Every day of a calendar month (`month` counts from one). */
  async daysInMonth(
    edition: WebEdition,
    year: number,
    month: number,
  ): Promise<CalendarDay[]> {
    return this.month(edition, monthOf(LocalDays.make(year, month, 1)));
  }

  async day(edition: WebEdition, date: LocalDay): Promise<CalendarDay> {
    const days = await this.daysInMonth(edition, date.year, date.month);
    const found = days.find((day) => LocalDays.equals(day.date, date));
    if (!found) {
      throw new CorpusError(
        "unavailable",
        `${LocalDays.description(date)} is outside the ${edition} edition.`,
      );
    }
    return found;
  }

  async office(
    edition: WebEdition,
    date: LocalDay,
    hour: OfficeHour,
  ): Promise<OfficeDocument> {
    const day = await this.day(edition, date);
    const key = day.offices[hour];
    if (!key) {
      throw new CorpusError(
        "unavailable",
        `${LocalDays.description(date)} has no ${hour} in the ${edition} edition.`,
      );
    }
    const stored = await this.remember(this.offices, key, () =>
      this.read<WebOffice>(webOfficePath(key)),
    );
    return officeDocument(edition, date, hour, stored);
  }

  /** The Masses of a civil date; none where the corpus has no Missal. */
  async masses(
    edition: WebEdition,
    date: LocalDay,
  ): Promise<readonly WebMassListing[]> {
    return (await this.day(edition, date)).masses ?? [];
  }

  /** A Mass of a civil date, by its place among the day's Masses. */
  async mass(
    edition: WebEdition,
    date: LocalDay,
    index: number,
  ): Promise<OfficeDocument> {
    const listing = (await this.masses(edition, date))[index];
    if (!listing) {
      throw new CorpusError(
        "unavailable",
        `${LocalDays.description(date)} has no Mass ${index + 1} in the ${edition} edition.`,
      );
    }
    const stored = await this.remember(this.offices, listing.key, () =>
      this.read<WebOffice>(webOfficePath(listing.key)),
    );
    return massDocument(edition, date, index, stored);
  }

  /** Fetches an office so that it is at hand, and cached, before it is opened. */
  prefetch(edition: WebEdition, date: LocalDay, hour: OfficeHour): void {
    void this.office(edition, date, hour).catch(() => undefined);
  }

  /** Fetches a day's Masses so that they are at hand, and cached. */
  prefetchMasses(edition: WebEdition, date: LocalDay): void {
    void this.masses(edition, date)
      .then((listings) =>
        Promise.all(
          listings.map((_, index) => this.mass(edition, date, index)),
        ),
      )
      .catch(() => undefined);
  }
}
