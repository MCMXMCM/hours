// The search half of `SQLiteMissalRepository`, parallel to
// `HoursCore/MissalRepository.swift`: the Masses a search of titles finds,
// and the parts of the Mass a search of their words finds. The native app
// reads them from the edition's Missal; here they are read from the Missal's
// days, Masses, texts and scores, and the Kyriale's settings, which the
// library carries beside the edition (see `webLibrary.ts` in the content
// compiler).

import {
  LocalDays,
  ObservanceTitle,
  officeSectionKinds,
  type ChantScore,
  type OfficeHour,
  type OfficeSectionKind,
} from "@/core/models.ts";
import * as SwiftString from "@/core/swiftString.ts";
import {
  OrdinaryParts,
  type LiturgicalSearchHit,
  type LiturgicalSearchLanguage,
  type LiturgicalSearchResult,
  type MassPartFilter,
  type MassUsageContext,
  type OrdinaryPart,
} from "./models.ts";
import {
  MassPartIndex,
  type MassPartEntry,
  type MissalSearchText,
  type MissalSection,
} from "./missalParts.ts";
import type { DayRange } from "./protocol.ts";
import { chantScore, decodedStoredChantScore } from "./stored.ts";
import {
  ContentRepositoryError,
  matchesOfficeTitle,
  type SearchDatabase,
  type SearchRepository,
  type SearchValue,
} from "./repository.ts";
import * as Strings from "./strings.ts";
import {
  firstServedYear,
  perennialYearPlan,
  storedRanges,
  type PerennialYearPlan,
} from "@compiler/yearTypes.ts";

/** The schema of the Missal this reader knows (`SQLiteMissalRepository.schema`). */
const missalSchema = 1;

/** The Hour whose Office names the day a Mass is said on: the Mass of the day is sung after Terce. */
export const massDayHour: OfficeHour = "terce";

/** What the search of titles reads of a Mass. */
interface StoredMassTitles {
  readonly titleLatin: string;
  readonly titleEnglish: string | null;
  readonly label: string | null;
  readonly labelEnglish: string | null;
}

/** A stored range of the Missal's days, with the served year its days are said in. */
interface MissalSegment {
  /** `YYYY-MM-DD`; null where the whole Missal is searched. */
  readonly stored: { readonly from: string; readonly to: string } | null;
  /** Null where the Missal stores the days it serves. */
  readonly servedYear: number | null;
}

const decoder = new TextDecoder("utf-8");

function invalidContent(detail: string): ContentRepositoryError {
  return new ContentRepositoryError({ kind: "invalidContent", detail });
}

function text(value: SearchValue | undefined): string | null {
  if (value === null || value === undefined) return null;
  if (typeof value === "string") return value;
  if (typeof value === "number") return String(value);
  return decoder.decode(value);
}

function parsed(value: string, detail: string): unknown {
  try {
    return JSON.parse(value);
  } catch {
    throw invalidContent(detail);
  }
}

function optionalString(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

/** `LiturgicalUsageContext`'s key for a Mass: its title and its name among the day's Masses. */
function massKey(titles: StoredMassTitles): string {
  return JSON.stringify([
    Strings.canonical(ObservanceTitle.latin(titles.titleLatin)),
    Strings.canonical(titles.label ?? ""),
  ]);
}

/** The order of `searchMassTitles`: by the day found, then the Missal's order. */
function isOrderedBefore(
  left: MassUsageContext,
  right: MassUsageContext,
): boolean {
  if (!LocalDays.equals(left.firstDate, right.firstDate)) {
    return LocalDays.isBefore(left.firstDate, right.firstDate);
  }
  if (left.index !== right.index) return left.index < right.index;
  return (
    Strings.localizedStandardCompare(left.titleLatin, right.titleLatin) < 0
  );
}

/** A setting of the Kyriale (`KyrialeCatalog.Setting`). */
interface KyrialeSetting {
  readonly part: OrdinaryPart;
  readonly note: string | null;
  readonly score: ChantScore;
}

function sortedSettings(values: Iterable<string>): string[] {
  return [...new Set(values)].sort(Strings.localizedStandardCompare);
}

export class MissalSearch {
  private readonly database: SearchDatabase;
  /** The plan by which a perennial Missal serves more years than it stores. */
  private readonly plan: PerennialYearPlan | null;
  private readonly titleCache = new Map<number, StoredMassTitles>();
  /** Every part of the Mass: read on the first search, and kept. */
  private partIndex: MassPartIndex | null = null;

  private constructor(
    database: SearchDatabase,
    plan: PerennialYearPlan | null,
  ) {
    this.database = database;
    this.plan = plan;
  }

  /** The Missal a library carries; null for a library made without one. */
  static open(database: SearchDatabase): MissalSearch | null {
    const rows = database.rows(
      "SELECT value FROM meta WHERE key = 'missal_manifest'",
    );
    if (rows.length === 0) return null;
    const manifest = parsed(
      text(rows[0][0]) ?? "",
      "The Missal has no manifest.",
    ) as Record<string, unknown> | null;
    if (manifest?.schema !== missalSchema) {
      throw invalidContent(
        `The Missal has schema ${String(manifest?.schema)}; this app reads ${missalSchema}.`,
      );
    }
    const coverage = manifest.coverage as Record<string, unknown> | undefined;
    const storedYears = coverage?.storedYears;
    if (storedYears === undefined || storedYears === null) {
      return new MissalSearch(database, null);
    }
    const startDate = optionalString(coverage?.startDate) ?? "";
    const endDate = optionalString(coverage?.endDate) ?? "";
    if (
      !Array.isArray(storedYears) ||
      !storedYears.every((year) => Number.isInteger(year))
    ) {
      throw invalidContent("The Missal's stored years are not civil years.");
    }
    try {
      return new MissalSearch(
        database,
        perennialYearPlan(
          Number(startDate.slice(0, 4)),
          Number(endDate.slice(0, 4)),
          storedYears as number[],
        ),
      );
    } catch (error) {
      throw invalidContent(
        error instanceof Error ? error.message : String(error),
      );
    }
  }

  /**
   * `searchMassTitles(query:language:usageRange:officeDays:limit:)`: each
   * Mass whose title the query matches, or that is said on one of
   * `officeDays` (the days whose Office the query matches), once, at its
   * first occurrence in the range.
   */
  searchMassTitles(
    query: string,
    language: LiturgicalSearchLanguage,
    usageRange: DayRange | null,
    officeDays: ReadonlySet<string>,
    limit = 50,
  ): MassUsageContext[] {
    if (
      !SwiftString.characters(query).some(
        (character) =>
          SwiftString.isLetter(character) || SwiftString.isNumber(character),
      )
    ) {
      return [];
    }
    const titleMatches = new Map<number, boolean>();
    const grouped = new Map<string, MassUsageContext>();
    for (const segment of this.segments(usageRange)) {
      const sql =
        segment.stored === null
          ? "SELECT date, masses FROM missal_days ORDER BY date"
          : "SELECT date, masses FROM missal_days WHERE date BETWEEN ? AND ? ORDER BY date";
      const bindings =
        segment.stored === null ? [] : [segment.stored.from, segment.stored.to];
      for (const row of this.database.rows(sql, bindings)) {
        const stored = LocalDays.fromISO(text(row[0]) ?? "");
        const ids = parsed(
          text(row[1]) ?? "",
          "A day of the Missal is malformed.",
        );
        if (
          stored === null ||
          !Array.isArray(ids) ||
          !ids.every((id) => Number.isInteger(id))
        ) {
          throw invalidContent("A day of the Missal is malformed.");
        }
        const date =
          segment.servedYear === null
            ? stored
            : LocalDays.make(segment.servedYear, stored.month, stored.day);
        const isOfficeDay = officeDays.has(LocalDays.description(date));
        (ids as number[]).forEach((id, index) => {
          const titles = this.titles(id);
          let matched = titleMatches.get(id);
          if (matched === undefined) {
            matched = matchesOfficeTitle(
              titles.titleLatin,
              titles.titleEnglish,
              query,
              language,
            );
            titleMatches.set(id, matched);
          }
          if (!matched && !isOfficeDay) return;
          const key = massKey(titles);
          const existing = grouped.get(key);
          if (existing === undefined) {
            grouped.set(key, {
              firstDate: date,
              lastDate: date,
              index,
              titleLatin: titles.titleLatin,
              titleEnglish: titles.titleEnglish,
              label: titles.label,
              labelEnglish: titles.labelEnglish,
              occurrenceCount: 1,
            });
            return;
          }
          // The Mass is named as its first occurrence is, which is the one
          // opened.
          const isEarlier = LocalDays.isBefore(date, existing.firstDate);
          grouped.set(key, {
            ...existing,
            ...(isEarlier
              ? {
                  firstDate: date,
                  index,
                  titleLatin: titles.titleLatin,
                  titleEnglish: titles.titleEnglish,
                  label: titles.label,
                  labelEnglish: titles.labelEnglish,
                }
              : {}),
            lastDate: LocalDays.isBefore(existing.lastDate, date)
              ? date
              : existing.lastDate,
            occurrenceCount: existing.occurrenceCount + 1,
          });
        });
      }
    }
    return [...grouped.values()]
      .sort((left, right) =>
        isOrderedBefore(left, right)
          ? -1
          : isOrderedBefore(right, left)
            ? 1
            : 0,
      )
      .slice(0, Math.max(1, Math.min(limit, 50)));
  }

  /** `prepareMassPartSearch()`: reads what a search of the parts reads, ahead of the first. */
  prepareMassPartSearch(): void {
    this.parts();
  }

  /**
   * `searchMassParts(query:language:filter:limit:)`: the parts of the Mass,
   * ordinary and proper, whose words hold the query's.
   */
  searchMassParts(
    query: string,
    language: LiturgicalSearchLanguage,
    filter: MassPartFilter,
    limit = 50,
  ): LiturgicalSearchHit[] {
    if (
      !SwiftString.characters(query).some(
        (character) =>
          SwiftString.isLetter(character) || SwiftString.isNumber(character),
      )
    ) {
      return [];
    }
    return this.parts().search(query, language, filter, limit);
  }

  /**
   * `massPartDetail(id:usageRange:)`: a part of the Mass that search found,
   * its words, the settings it is sung to, and the Masses within the range
   * that say it.
   */
  massPartDetail(
    id: string,
    usageRange: DayRange | null,
  ): LiturgicalSearchResult {
    const index = this.parts();
    const entry = index.entry(id);
    if (entry === null)
      throw invalidContent(`Search resource ${id} is missing.`);
    const missalScores = new Map<number, ChantScore>();
    for (const scoreID of entry.scoreIDs) {
      const rows = this.database.rows(
        "SELECT payload FROM missal_scores WHERE id = ?",
        [scoreID],
      );
      const payload = rows.length === 0 ? null : text(rows[0][0]);
      if (payload === null) {
        throw invalidContent(`A chant of the Missal is missing.`);
      }
      missalScores.set(
        scoreID,
        chantScore(
          decodedStoredChantScore(
            parsed(payload, "A chant of the Missal is malformed."),
          ),
        ),
      );
    }
    let scores: ChantScore[];
    const notes: Record<string, string> = {};
    // The name of each setting a Mass sings a part of the Ordinary to.
    const settingNames = new Map<number, string>();
    const settings =
      entry.part === null ? [] : this.kyrialeSettings(entry.part);
    if (entry.part !== null && settings.length > 0) {
      const byChant = new Map<string, ChantScore>();
      for (const setting of settings) {
        if (setting.note !== null) notes[setting.score.id] = setting.note;
        const url = setting.score.provenance.sourceURL;
        if (url != null) byChant.set(url, setting.score);
      }
      scores = settings.map((setting) => setting.score);
      // A chant the Missal sings that the Kyriale does not give is offered
      // after the book's own.
      for (const scoreID of entry.scoreIDs) {
        const score = missalScores.get(scoreID);
        if (score === undefined) continue;
        const url = score.provenance.sourceURL;
        const named = url == null ? undefined : byChant.get(url);
        if (named !== undefined) {
          settingNames.set(scoreID, named.incipit);
        } else {
          settingNames.set(scoreID, score.incipit);
          scores.push(score);
        }
      }
    } else {
      scores = entry.scoreIDs.flatMap((scoreID) => {
        const score = missalScores.get(scoreID);
        return score === undefined ? [] : [score];
      });
      if (entry.part !== null) {
        for (const [scoreID, score] of missalScores) {
          settingNames.set(scoreID, score.incipit);
        }
      }
    }
    return {
      id: entry.id,
      kind: entry.kind,
      titleLatin: entry.title,
      titleEnglish: entry.titleEnglish,
      rubricLatin: entry.rubric,
      rubricEnglish: entry.rubricEnglish,
      latin: entry.latin,
      english: entry.english,
      scoredRealizations: scores,
      contexts: [],
      massContexts: this.massContexts(entry, index, usageRange, settingNames),
      settingNotes: notes,
    };
  }

  /**
   * `massContexts(of:in:usageRange:settingNames:)`: the Masses within the
   * range that say a part, each once, at its first occurrence, in the order
   * of the days; for a part of the Ordinary, with the settings each sings it
   * to.
   */
  private massContexts(
    entry: MassPartEntry,
    index: MassPartIndex,
    usageRange: DayRange | null,
    settingNames: ReadonlyMap<number, string>,
  ): MassUsageContext[] {
    const scoresByMass = new Map<number, Set<number>>();
    for (const textID of entry.textIDs) {
      for (const use of index.uses.get(textID) ?? []) {
        let used = scoresByMass.get(use.mass);
        if (used === undefined) {
          used = new Set();
          scoresByMass.set(use.mass, used);
        }
        if (use.score !== null) used.add(use.score);
      }
    }
    if (scoresByMass.size === 0) return [];
    const grouped = new Map<string, MassUsageContext>();
    for (const segment of this.segments(usageRange)) {
      const sql =
        segment.stored === null
          ? "SELECT date, masses FROM missal_days ORDER BY date"
          : "SELECT date, masses FROM missal_days WHERE date BETWEEN ? AND ? ORDER BY date";
      const bindings =
        segment.stored === null ? [] : [segment.stored.from, segment.stored.to];
      for (const row of this.database.rows(sql, bindings)) {
        const stored = LocalDays.fromISO(text(row[0]) ?? "");
        const ids = parsed(
          text(row[1]) ?? "",
          "A day of the Missal is malformed.",
        );
        if (
          stored === null ||
          !Array.isArray(ids) ||
          !ids.every((id) => Number.isInteger(id))
        ) {
          throw invalidContent("A day of the Missal is malformed.");
        }
        const date =
          segment.servedYear === null
            ? stored
            : LocalDays.make(segment.servedYear, stored.month, stored.day);
        (ids as number[]).forEach((id, position) => {
          const used = scoresByMass.get(id);
          if (used === undefined) return;
          const titles = this.titles(id);
          const settings = [...used].flatMap((scoreID) => {
            const name = settingNames.get(scoreID);
            return name === undefined ? [] : [name];
          });
          const key = massKey(titles);
          const existing = grouped.get(key);
          if (existing === undefined) {
            grouped.set(key, {
              firstDate: date,
              lastDate: date,
              index: position,
              titleLatin: titles.titleLatin,
              titleEnglish: titles.titleEnglish,
              label: titles.label,
              labelEnglish: titles.labelEnglish,
              occurrenceCount: 1,
              settings: sortedSettings(settings),
            });
            return;
          }
          // The Mass is named as its first occurrence is, which is the one
          // opened.
          const isEarlier = LocalDays.isBefore(date, existing.firstDate);
          grouped.set(key, {
            ...existing,
            ...(isEarlier
              ? {
                  firstDate: date,
                  index: position,
                  titleLatin: titles.titleLatin,
                  titleEnglish: titles.titleEnglish,
                  label: titles.label,
                  labelEnglish: titles.labelEnglish,
                }
              : {}),
            lastDate: LocalDays.isBefore(existing.lastDate, date)
              ? date
              : existing.lastDate,
            occurrenceCount: existing.occurrenceCount + 1,
            settings: sortedSettings([
              ...(existing.settings ?? []),
              ...settings,
            ]),
          });
        });
      }
    }
    return [...grouped.values()].sort((left, right) =>
      isOrderedBefore(left, right) ? -1 : isOrderedBefore(right, left) ? 1 : 0,
    );
  }

  /** The Kyriale's settings of a part, in the book's order; none in a library without it. */
  private kyrialeSettings(part: OrdinaryPart): KyrialeSetting[] {
    if (!this.hasKyriale()) return [];
    return this.database
      .rows(
        "SELECT note, score FROM kyriale_settings WHERE part = ? ORDER BY position",
        [part],
      )
      .map((row) => ({
        part,
        note: text(row[0]),
        score: chantScore(
          decodedStoredChantScore(
            parsed(
              text(row[1]) ?? "",
              "A setting of the Kyriale is malformed.",
            ),
          ),
        ),
      }));
  }

  private hasKyriale(): boolean {
    return (
      this.database.rows(
        "SELECT 1 FROM sqlite_master WHERE name = 'kyriale_settings'",
      ).length > 0
    );
  }

  /** `loadedPartIndex()`: every part of the Mass, read on the first search. */
  private parts(): MassPartIndex {
    if (this.partIndex !== null) return this.partIndex;
    const hasParts =
      this.database.rows(
        "SELECT 1 FROM sqlite_master WHERE name = 'missal_texts'",
      ).length > 0;
    const texts: MissalSearchText[] = [];
    const sections = new Map<number, MissalSection[]>();
    if (hasParts) {
      for (const row of this.database.rows(
        "SELECT id, payload FROM missal_texts ORDER BY id",
      )) {
        const value = parsed(
          text(row[1]) ?? "",
          "A text of the Missal is malformed.",
        ) as Record<string, unknown> | null;
        const kind = officeSectionKinds.find(
          (candidate) => candidate === value?.kind,
        ) as OfficeSectionKind | undefined;
        const title = optionalString(value?.title);
        const latin = optionalString(value?.latin);
        if (kind === undefined || title === null || latin === null) {
          throw invalidContent("A text of the Missal is malformed.");
        }
        texts.push({
          id: Number(row[0]),
          kind,
          title,
          titleEnglish: optionalString(value?.titleEnglish),
          rubric: optionalString(value?.rubric),
          rubricEnglish: optionalString(value?.rubricEnglish),
          latin,
          english: optionalString(value?.english),
          ordinary: value?.ordinary === true,
        });
      }
      for (const row of this.database.rows(
        "SELECT id, payload FROM missal_masses ORDER BY id",
      )) {
        const value = parsed(
          text(row[1]) ?? "",
          "A Mass of the Missal is malformed.",
        ) as Record<string, unknown> | null;
        const references = value?.sections;
        if (
          !Array.isArray(references) ||
          !references.every(
            (reference) =>
              Array.isArray(reference) &&
              reference.length === 2 &&
              reference.every((value) => Number.isInteger(value)),
          )
        ) {
          throw invalidContent("A Mass of the Missal is malformed.");
        }
        sections.set(
          Number(row[0]),
          (references as [number, number][]).map(([textID, scoreID]) => ({
            text: textID,
            score: scoreID === 0 ? null : scoreID,
          })),
        );
      }
    }
    const kyrialeParts = new Set<OrdinaryPart>();
    if (this.hasKyriale()) {
      for (const row of this.database.rows(
        "SELECT DISTINCT part FROM kyriale_settings",
      )) {
        const part = OrdinaryParts.fromRawValue(text(row[0]) ?? "");
        if (part !== null) kyrialeParts.add(part);
      }
    }
    this.partIndex = new MassPartIndex(texts, sections, kyrialeParts);
    return this.partIndex;
  }

  /** The stored ranges that hold a range of served days, as `usageSegments(for:)` has them. */
  private segments(usageRange: DayRange | null): MissalSegment[] {
    const plan = this.plan;
    if (plan === null) {
      return [
        {
          stored:
            usageRange === null
              ? null
              : {
                  from: LocalDays.description(usageRange.lowerBound),
                  to: LocalDays.description(usageRange.upperBound),
                },
          servedYear: null,
        },
      ];
    }
    if (usageRange !== null) {
      return storedRanges(
        plan,
        LocalDays.description(usageRange.lowerBound),
        LocalDays.description(usageRange.upperBound),
      ).map((range) => ({
        stored: { from: range.from, to: range.to },
        servedYear: range.servedYear,
      }));
    }
    return plan.years
      .flatMap((stored): MissalSegment[] => {
        const servedYear = firstServedYear(plan, stored);
        const year = String(stored).padStart(4, "0");
        return servedYear === null
          ? []
          : [
              {
                stored: { from: `${year}-01-01`, to: `${year}-12-31` },
                servedYear,
              },
            ];
      })
      .sort((left, right) => (left.servedYear ?? 0) - (right.servedYear ?? 0));
  }

  private titles(id: number): StoredMassTitles {
    const cached = this.titleCache.get(id);
    if (cached !== undefined) return cached;
    const rows = this.database.rows(
      "SELECT payload FROM missal_masses WHERE id = ?",
      [id],
    );
    const payload = rows.length === 0 ? null : text(rows[0][0]);
    if (payload === null) throw invalidContent(`The Missal has no Mass ${id}.`);
    const value = parsed(payload, `The Mass ${id} is malformed.`) as Record<
      string,
      unknown
    > | null;
    const titleLatin = optionalString(value?.titleLatin);
    if (titleLatin === null) {
      throw invalidContent(`The Mass ${id} has no title.`);
    }
    const titles: StoredMassTitles = {
      titleLatin,
      titleEnglish: optionalString(value?.titleEnglish),
      label: optionalString(value?.label),
      labelEnglish: optionalString(value?.labelEnglish),
    };
    this.titleCache.set(id, titles);
    return titles;
  }
}

/**
 * `AppModel.searchMassTitles`: the Masses found by their own titles, and
 * those of the days whose Office at Terce the query finds.
 */
export function searchMassTitles(
  repository: SearchRepository,
  missal: MissalSearch | null,
  query: string,
  language: LiturgicalSearchLanguage,
  usageRange: DayRange | null,
  limit = 50,
): MassUsageContext[] {
  if (missal === null) return [];
  const officeDays = repository.officeTitleDays(
    query,
    language,
    massDayHour,
    usageRange,
  );
  return missal.searchMassTitles(
    query,
    language,
    usageRange,
    officeDays,
    limit,
  );
}
