// The search model, parallel to `LiturgicalSearchLanguage`,
// `LiturgicalSearchHit`, `LiturgicalUsageContext`, and
// `LiturgicalSearchResult` in `HoursCore/Models.swift`.
//
// Values are plain immutable data, as in `@/core/models.ts`. An optional
// Swift property may be absent or `null`; the search repository always writes
// `null`. A Swift initializer with default arguments is `make` in the
// namespace named for the plural of its type, and a computed property is a
// function there of the same name.

import {
  OfficeHours,
  type ChantScore,
  type LocalDay,
  type OfficeHour,
  type OfficeSectionKind,
} from "@/core/models.ts";

export type LiturgicalSearchLanguage = "all" | "latin" | "english";

const liturgicalSearchLanguageAllCases: readonly LiturgicalSearchLanguage[] = [
  "all",
  "latin",
  "english",
];

export const LiturgicalSearchLanguages = {
  /**
   * The cases in the order Swift declares them. (The Swift enum is not
   * `CaseIterable`; the search screen names its three choices itself.)
   */
  allCases: liturgicalSearchLanguageAllCases,

  /** `LiturgicalSearchLanguage(rawValue:)`. */
  fromRawValue(rawValue: string): LiturgicalSearchLanguage | null {
    return (
      liturgicalSearchLanguageAllCases.find(
        (language) => language === rawValue,
      ) ?? null
    );
  },
};

export interface LiturgicalSearchHit {
  readonly id: string;
  readonly kind: OfficeSectionKind;
  readonly titleLatin: string;
  readonly titleEnglish?: string | null;
  readonly snippet: string;
  readonly snippetLanguage: LiturgicalSearchLanguage;
  readonly hasScoredRealizations: boolean;
  /**
   * How nearly it answers the query as a phrase (`searchPhraseRank`), by
   * which the Mass's results are merged with the Office's; absent for a hit
   * recorded before it was kept.
   */
  readonly rank?: number | null;
}

/** `MassPartSearch`: how a part of the Mass that search finds is told apart. */
export const MassPartSearch = {
  /** The beginning of the identifier of every part of the Mass a search finds. */
  idPrefix: "missa:",
  /** That of a part of the Ordinary the Kyriale sets, which offers each of its settings. */
  ordinaryIDPrefix: "missa:ordinary:",
} as const;

export const LiturgicalSearchHits = {
  /** `LiturgicalSearchHit.init`, with the defaults of its Swift parameters. */
  make(init: {
    readonly id: string;
    readonly kind: OfficeSectionKind;
    readonly titleLatin: string;
    readonly titleEnglish?: string | null;
    readonly snippet: string;
    readonly snippetLanguage: LiturgicalSearchLanguage;
    readonly hasScoredRealizations?: boolean;
    readonly rank?: number | null;
  }): LiturgicalSearchHit {
    return {
      id: init.id,
      kind: init.kind,
      titleLatin: init.titleLatin,
      titleEnglish: init.titleEnglish ?? null,
      snippet: init.snippet,
      snippetLanguage: init.snippetLanguage,
      hasScoredRealizations: init.hasScoredRealizations ?? false,
      rank: init.rank ?? null,
    };
  },

  /** `isOfTheMass`: whether it is a part of the Mass, found in the Missal. */
  isOfTheMass(hit: LiturgicalSearchHit): boolean {
    return hit.id.startsWith(MassPartSearch.idPrefix);
  },

  /**
   * `merged(office:mass:limit:)`: the Office's results and the Mass's, as one
   * list: by how nearly each answers the query, and, among those that answer
   * it alike, the Office's and the Mass's in turn, each in its own order.
   */
  merged(
    office: readonly LiturgicalSearchHit[],
    mass: readonly LiturgicalSearchHit[],
    limit = 50,
  ): LiturgicalSearchHit[] {
    const rankOf = (hit: LiturgicalSearchHit) =>
      hit.rank ?? Number.MAX_SAFE_INTEGER;
    const ranks = [...new Set([...office, ...mass].map(rankOf))].sort(
      (left, right) => left - right,
    );
    const merged: LiturgicalSearchHit[] = [];
    for (const rank of ranks) {
      const left = office.filter((hit) => rankOf(hit) === rank);
      const right = mass.filter((hit) => rankOf(hit) === rank);
      for (
        let index = 0;
        index < Math.max(left.length, right.length);
        index += 1
      ) {
        if (index < left.length) merged.push(left[index]);
        if (index < right.length) merged.push(right[index]);
      }
    }
    return merged.slice(0, Math.max(0, limit));
  },
};

/**
 * `OrdinaryPart`: a part of the Ordinary as the Kyriale sets it, by the words
 * it sings.
 */
export type OrdinaryPart =
  | "kyrie"
  | "gloria"
  | "credo"
  | "sanctus"
  | "agnusDei"
  | "agnusDeiDefunctorum"
  | "ite"
  | "benedicamus"
  | "requiescant";

export const OrdinaryParts = {
  allCases: [
    "kyrie",
    "gloria",
    "credo",
    "sanctus",
    "agnusDei",
    "agnusDeiDefunctorum",
    "ite",
    "benedicamus",
    "requiescant",
  ] as readonly OrdinaryPart[],

  fromRawValue(rawValue: string): OrdinaryPart | null {
    return OrdinaryParts.allCases.find((part) => part === rawValue) ?? null;
  },
};

/** `MassPartFilter`: the parts of the Mass a search looks among. */
export interface MassPartFilter {
  /** The kinds of section; null for every kind. */
  readonly kinds: readonly OfficeSectionKind[] | null;
  /** Of the Ordinary, or proper to the day; null for either. */
  readonly ordinary: boolean | null;
  /** Only the parts that are sung. */
  readonly requiresScore: boolean;
}

export const MassPartFilters = {
  /** `MassPartFilter.init`, with the defaults of its Swift parameters. */
  make(
    init: {
      readonly kinds?: readonly OfficeSectionKind[] | null;
      readonly ordinary?: boolean | null;
      readonly requiresScore?: boolean;
    } = {},
  ): MassPartFilter {
    return {
      kinds: init.kinds ?? null,
      ordinary: init.ordinary ?? null,
      requiresScore: init.requiresScore ?? false,
    };
  },

  everyPart: {
    kinds: null,
    ordinary: null,
    requiresScore: false,
  } as MassPartFilter,
};

export interface LiturgicalUsageContext {
  readonly observanceID?: string | null;
  readonly firstDate: LocalDay;
  readonly lastDate: LocalDay;
  readonly hour: OfficeHour;
  readonly observanceTitleLatin: string;
  readonly observanceTitleEnglish?: string | null;
  readonly occurrenceCount: number;
  readonly settingModes: readonly string[];
}

export const LiturgicalUsageContexts = {
  /**
   * `LiturgicalUsageContext.init(observanceID:firstDate:lastDate:hour:
   * observanceTitleLatin:observanceTitleEnglish:occurrenceCount:settingModes:)`,
   * with the defaults of its Swift parameters.
   */
  make(init: {
    readonly observanceID?: string | null;
    readonly firstDate: LocalDay;
    readonly lastDate: LocalDay;
    readonly hour: OfficeHour;
    readonly observanceTitleLatin: string;
    readonly observanceTitleEnglish?: string | null;
    readonly occurrenceCount?: number;
    readonly settingModes?: readonly string[];
  }): LiturgicalUsageContext {
    return {
      observanceID: init.observanceID ?? null,
      firstDate: init.firstDate,
      lastDate: init.lastDate,
      hour: init.hour,
      observanceTitleLatin: init.observanceTitleLatin,
      observanceTitleEnglish: init.observanceTitleEnglish ?? null,
      occurrenceCount: init.occurrenceCount ?? 1,
      settingModes: init.settingModes ?? [],
    };
  },

  /**
   * `LiturgicalUsageContext.init(date:hour:dayTitleLatin:dayTitleEnglish:
   * settingModes:)`: a single occurrence, on one day.
   */
  makeForDay(
    date: LocalDay,
    hour: OfficeHour,
    dayTitleLatin: string,
    dayTitleEnglish: string | null = null,
    settingModes: readonly string[] = [],
  ): LiturgicalUsageContext {
    return LiturgicalUsageContexts.make({
      firstDate: date,
      lastDate: date,
      hour,
      observanceTitleLatin: dayTitleLatin,
      observanceTitleEnglish: dayTitleEnglish,
      settingModes,
    });
  },

  date(context: LiturgicalUsageContext): LocalDay {
    return context.firstDate;
  },

  dayTitleLatin(context: LiturgicalUsageContext): string {
    return context.observanceTitleLatin;
  },

  dayTitleEnglish(context: LiturgicalUsageContext): string | null {
    return context.observanceTitleEnglish ?? null;
  },
};

export interface LiturgicalSearchResult {
  readonly id: string;
  readonly kind: OfficeSectionKind;
  readonly titleLatin: string;
  readonly titleEnglish?: string | null;
  readonly rubricLatin?: string | null;
  readonly rubricEnglish?: string | null;
  readonly latin: string;
  readonly english?: string | null;
  /** Swift's `[ScoredChantRealization]`, which names `ChantScore`. */
  readonly scoredRealizations: readonly ChantScore[];
  readonly contexts: readonly LiturgicalUsageContext[];
  /** The Masses a part of the Mass is said in; the Office's results have none. */
  readonly massContexts: readonly MassUsageContext[];
  /** What names a setting beyond its incipit and mode, by its score's identifier. */
  readonly settingNotes: Readonly<Record<string, string>>;
}

export const LiturgicalSearchResults = {
  /** `LiturgicalSearchResult.init`, with the defaults of its Swift parameters. */
  make(init: {
    readonly id: string;
    readonly kind: OfficeSectionKind;
    readonly titleLatin: string;
    readonly titleEnglish?: string | null;
    readonly rubricLatin?: string | null;
    readonly rubricEnglish?: string | null;
    readonly latin: string;
    readonly english?: string | null;
    readonly scoredRealizations?: readonly ChantScore[];
    readonly contexts?: readonly LiturgicalUsageContext[];
    readonly massContexts?: readonly MassUsageContext[];
    readonly settingNotes?: Readonly<Record<string, string>>;
  }): LiturgicalSearchResult {
    return {
      id: init.id,
      kind: init.kind,
      titleLatin: init.titleLatin,
      titleEnglish: init.titleEnglish ?? null,
      rubricLatin: init.rubricLatin ?? null,
      rubricEnglish: init.rubricEnglish ?? null,
      latin: init.latin,
      english: init.english ?? null,
      scoredRealizations: init.scoredRealizations ?? [],
      contexts: init.contexts ?? [],
      massContexts: init.massContexts ?? [],
      settingNotes: init.settingNotes ?? {},
    };
  },
};

/**
 * `MassUsageContext` (`HoursCore/MissalRepository.swift`): a Mass found by
 * its title, or one that says a part of the Mass that search found, at its
 * next occurrence, which the Mass reader opens.
 */
export interface MassUsageContext {
  readonly firstDate: LocalDay;
  readonly lastDate: LocalDay;
  /** Its place among the Masses of its first day, from zero. */
  readonly index: number;
  readonly titleLatin: string;
  readonly titleEnglish?: string | null;
  /** The name that tells a day's Masses apart ("Ad Missam in nocte"). */
  readonly label?: string | null;
  readonly labelEnglish?: string | null;
  readonly occurrenceCount: number;
  /**
   * For a part of the Ordinary, the settings this Mass sings it to ("Kyrie
   * XI"); absent or empty otherwise.
   */
  readonly settings?: readonly string[];
}

/**
 * `LiturgicalTitleResult`: what a search of titles finds, an Office at one
 * of its Hours or a Mass.
 */
export type LiturgicalTitleResult =
  | { readonly type: "office"; readonly context: LiturgicalUsageContext }
  | { readonly type: "mass"; readonly mass: MassUsageContext };

const massFollowsHour: OfficeHour = "terce";

export const LiturgicalTitleResults = {
  /**
   * `LiturgicalTitleResult.merged(offices:masses:)`: the Offices in the order
   * found, which is the order of the Hours, with the Masses set after Terce,
   * as the Mass of the day is sung.
   */
  merged(
    offices: readonly LiturgicalUsageContext[],
    masses: readonly MassUsageContext[],
  ): LiturgicalTitleResult[] {
    const hours = OfficeHours.allCases;
    const after = hours.indexOf(massFollowsHour);
    const place = offices.findIndex(
      (context) => hours.indexOf(context.hour) > after,
    );
    const split = place < 0 ? offices.length : place;
    return [
      ...offices
        .slice(0, split)
        .map((context) => ({ type: "office", context }) as const),
      ...masses.map((mass) => ({ type: "mass", mass }) as const),
      ...offices
        .slice(split)
        .map((context) => ({ type: "office", context }) as const),
    ];
  },
};
