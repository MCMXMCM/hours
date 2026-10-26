// The pure types of the search screen, parallel to `PrayerSearchCategory`,
// `PrayerSearchDetailPresentation`, `PrayerSearchChantSetting`,
// `PrayerSearchUsageGroup`, the text of `PrayerSearchUsageRow`, and
// `SearchResultPresentation` in `HoursApp/PrayerSearchView.swift`.
//
// A Swift enum with raw values is the union of them, with its cases'
// properties as functions in the namespace named for its plural; a struct is
// plain data, with its initializer as `make` and its computed properties as
// functions in the namespace named for its plural. The views themselves, the
// search bar, the running of a search, and the recent searches are not here.

import {
  LocalDays,
  ObservanceTitle,
  OfficeHours,
  type ChantScore,
  type OfficeHour,
  type OfficeSectionKind,
} from "@/core/models.ts";
import {
  GregorianScoreParser,
  GregorianScoreParserError,
  GregorianScores,
} from "@/core/notation/index.ts";
import * as SwiftString from "@/core/swiftString.ts";
import * as FoundationStrings from "@/reader/presentation/strings.ts";
import {
  LiturgicalSearchResults,
  LiturgicalUsageContexts,
  MassPartFilters,
  MassPartSearch,
  type LiturgicalSearchHit,
  type LiturgicalSearchResult,
  type LiturgicalUsageContext,
  type MassPartFilter,
  type MassUsageContext,
} from "./models.ts";
import * as Strings from "./strings.ts";

export type PrayerSearchCategory =
  | "all"
  | "titles"
  | "mass"
  | "readings"
  | "hymns"
  | "chants"
  | "psalms"
  | "antiphons"
  | "responsories"
  | "collects";

const prayerSearchCategoryAllCases: readonly PrayerSearchCategory[] = [
  "all",
  "titles",
  "mass",
  "readings",
  "hymns",
  "chants",
  "psalms",
  "antiphons",
  "responsories",
  "collects",
];

export const PrayerSearchCategories = {
  allCases: prayerSearchCategoryAllCases,

  /** `PrayerSearchCategory(rawValue:)`. */
  fromRawValue(rawValue: string): PrayerSearchCategory | null {
    return (
      prayerSearchCategoryAllCases.find((category) => category === rawValue) ??
      null
    );
  },

  id(category: PrayerSearchCategory): PrayerSearchCategory {
    return category;
  },

  title(category: PrayerSearchCategory): string {
    switch (category) {
      case "all":
        return "All";
      case "titles":
        return "Titles";
      case "mass":
        return "Mass";
      case "readings":
        return "Readings";
      case "hymns":
        return "Hymns";
      case "chants":
        return "Chants";
      case "psalms":
        return "Psalms";
      case "antiphons":
        return "Antiphons";
      case "responsories":
        return "Responsories";
      case "collects":
        return "Collects";
    }
  },

  kind(category: PrayerSearchCategory): OfficeSectionKind | null {
    switch (category) {
      case "all":
      case "titles":
      case "mass":
      case "chants":
        return null;
      case "readings":
        return "reading";
      case "hymns":
        return "hymn";
      case "psalms":
        return "psalm";
      case "antiphons":
        return "antiphon";
      case "responsories":
        return "responsory";
      case "collects":
        return "collect";
    }
  },

  requiresScore(category: PrayerSearchCategory): boolean {
    return category === "chants";
  },

  /** `searchesOffice`: whether the Office's texts are searched, all but the Mass's own. */
  searchesOffice(category: PrayerSearchCategory): boolean {
    return category !== "mass";
  },

  /**
   * `massFilter(part:)`: the parts of the Mass searched beside the Office's
   * texts, as the category names them among the Mass's; none for titles.
   */
  massFilter(
    category: PrayerSearchCategory,
    part: MassPartChoice,
  ): MassPartFilter | null {
    switch (category) {
      case "all":
        return MassPartFilters.everyPart;
      case "titles":
        return null;
      case "mass":
        return MassPartChoices.filter(part);
      case "readings":
        return MassPartFilters.make({
          kinds: ["epistle", "reading", "gospel", "lastGospel"],
        });
      case "hymns":
        return MassPartFilters.make({ kinds: ["hymn"] });
      case "chants":
        return MassPartFilters.make({ requiresScore: true });
      case "psalms":
        return MassPartFilters.make({ kinds: ["psalm"] });
      case "antiphons":
        return MassPartFilters.make({ kinds: ["antiphon"] });
      case "responsories":
        return MassPartFilters.make({ kinds: ["responsory"] });
      case "collects":
        return MassPartFilters.make({ kinds: ["collect"] });
    }
  },
};

/**
 * `MassPartChoice`: the parts of the Mass the Mass category may be narrowed
 * to, the Ordinary, the propers, or one part, in the order of the Mass.
 */
export type MassPartChoice =
  | "any"
  | "ordinary"
  | "propers"
  | "introit"
  | "kyrie"
  | "gloria"
  | "collect"
  | "epistle"
  | "gradual"
  | "alleluia"
  | "tract"
  | "sequence"
  | "gospel"
  | "credo"
  | "offertory"
  | "secret"
  | "preface"
  | "sanctus"
  | "canon"
  | "agnusDei"
  | "communion"
  | "postcommunion"
  | "dismissal";

const massPartChoiceTitles: Record<MassPartChoice, string> = {
  any: "Any Part",
  ordinary: "Ordinary",
  propers: "Propers",
  introit: "Introit",
  kyrie: "Kyrie",
  gloria: "Gloria",
  collect: "Collect",
  epistle: "Epistle",
  gradual: "Gradual",
  alleluia: "Alleluia",
  tract: "Tract",
  sequence: "Sequence",
  gospel: "Gospel",
  credo: "Credo",
  offertory: "Offertory",
  secret: "Secret",
  preface: "Preface",
  sanctus: "Sanctus",
  canon: "Canon",
  agnusDei: "Agnus Dei",
  communion: "Communion",
  postcommunion: "Postcommunion",
  dismissal: "Dismissal",
};

export const MassPartChoices = {
  allCases: Object.keys(massPartChoiceTitles) as readonly MassPartChoice[],

  fromRawValue(rawValue: string): MassPartChoice | null {
    return (
      MassPartChoices.allCases.find((choice) => choice === rawValue) ?? null
    );
  },

  title(choice: MassPartChoice): string {
    return massPartChoiceTitles[choice];
  },

  filter(choice: MassPartChoice): MassPartFilter {
    switch (choice) {
      case "any":
        return MassPartFilters.everyPart;
      case "ordinary":
        return MassPartFilters.make({ ordinary: true });
      case "propers":
        return MassPartFilters.make({ ordinary: false });
      // The lessons read before it on some days with it.
      case "epistle":
        return MassPartFilters.make({ kinds: ["epistle", "reading"] });
      default:
        return MassPartFilters.make({ kinds: [choice] });
    }
  },
};

export interface PrayerSearchChantSetting {
  readonly score: ChantScore;
  readonly variantIndex: number;
  readonly variantCount: number;
  /** The Mass of the Kyriale it belongs to, or its trope. */
  readonly note?: string | null;
  /** Whether settings of one mode are told apart by their number. */
  readonly isNumbered?: boolean;
}

/** A score's mode as the key of a `Map`: Swift keys these dictionaries by `String?`. */
function modeKey(score: ChantScore): string | null {
  return score.mode == null ? null : Strings.canonical(score.mode);
}

export const PrayerSearchChantSettings = {
  id(setting: PrayerSearchChantSetting): string {
    return setting.score.id;
  },

  label(setting: PrayerSearchChantSetting): string {
    if (setting.isNumbered === false) {
      return [
        setting.note ?? null,
        setting.score.mode == null ? null : `Mode ${setting.score.mode}`,
      ]
        .filter((part): part is string => part !== null)
        .join(" · ");
    }
    const mode =
      setting.score.mode == null
        ? "Mode unspecified"
        : `Mode ${setting.score.mode}`;
    if (!(setting.variantCount > 1)) return mode;
    return `${mode} · Setting ${setting.variantIndex} of ${setting.variantCount}`;
  },

  /** `PrayerSearchChantSetting.settings(from:notes:numbered:)`. */
  settings(
    scores: readonly ChantScore[],
    notes: Readonly<Record<string, string>> = {},
    numbered = true,
  ): PrayerSearchChantSetting[] {
    const counts = new Map<string | null, number>();
    for (const score of scores) {
      const key = modeKey(score);
      counts.set(key, (counts.get(key) ?? 0) + 1);
    }
    const indices = new Map<string | null, number>();
    return scores.map((score) => {
      const key = modeKey(score);
      const index = (indices.get(key) ?? 0) + 1;
      indices.set(key, index);
      return {
        score,
        variantIndex: index,
        variantCount: counts.get(key) ?? 1,
        note: notes[score.id] ?? null,
        isNumbered: numbered,
      };
    });
  },
};

export interface PrayerSearchUsageGroup {
  readonly hour: OfficeHour;
  readonly contexts: readonly LiturgicalUsageContext[];
}

export const PrayerSearchUsageGroups = {
  id(group: PrayerSearchUsageGroup): OfficeHour {
    return group.hour;
  },
};

export interface PrayerSearchDetailPresentation {
  readonly result: LiturgicalSearchResult;
  readonly chantSettings: readonly PrayerSearchChantSetting[];
  readonly usageGroups: readonly PrayerSearchUsageGroup[];
  readonly latinText: string;
  /**
   * Whether the settings stand before the words: a part of the Mass's
   * Ordinary, whose words do not change.
   */
  readonly leadsWithSettings: boolean;
}

export const PrayerSearchDetailPresentations = {
  /** `PrayerSearchDetailPresentation.init(result:)`. */
  make(result: LiturgicalSearchResult): PrayerSearchDetailPresentation {
    const isOfTheMass = result.id.startsWith(MassPartSearch.idPrefix);
    const chantSettings = PrayerSearchChantSettings.settings(
      result.scoredRealizations,
      result.settingNotes,
      // The Kyriale numbers its settings itself ("Kyrie IV").
      !isOfTheMass,
    );

    const contextsByHour = new Map<OfficeHour, LiturgicalUsageContext[]>();
    for (const context of result.contexts) {
      const contexts = contextsByHour.get(context.hour);
      if (contexts === undefined) {
        contextsByHour.set(context.hour, [context]);
      } else {
        contexts.push(context);
      }
    }
    const usageGroups: PrayerSearchUsageGroup[] = [];
    for (const hour of OfficeHours.allCases) {
      const contexts = contextsByHour.get(hour);
      if (contexts === undefined) continue;
      usageGroups.push({
        hour,
        contexts: [...contexts].sort((left, right) =>
          LocalDays.compare(
            LiturgicalUsageContexts.date(left),
            LiturgicalUsageContexts.date(right),
          ),
        ),
      });
    }

    // The Missal prints every word its chants sing; an Office's text may
    // print only "V/" where its words are sung.
    const lyricTexts: string[] = [];
    for (const score of isOfTheMass ? [] : result.scoredRealizations) {
      // `try?`: a score that does not parse offers no text.
      try {
        lyricTexts.push(
          GregorianScores.lyricText(
            GregorianScoreParser.parse(score.gabc, score.timeline),
          ),
        );
      } catch (error) {
        if (!(error instanceof GregorianScoreParserError)) throw error;
      }
    }
    const scoredLatin = FoundationStrings.maxBy(
      lyricTexts,
      (left, right) =>
        Strings.characterCount(left) < Strings.characterCount(right),
    );
    const latinText =
      scoredLatin !== null &&
      Strings.characterCount(scoredLatin) > Strings.characterCount(result.latin)
        ? scoredLatin
        : result.latin;

    return {
      result,
      chantSettings,
      usageGroups,
      latinText,
      leadsWithSettings: result.id.startsWith(MassPartSearch.ordinaryIDPrefix),
    };
  },
};

/**
 * The text of a `PrayerSearchUsageRow`: one office in which a result is
 * used, as the detail screen lists it.
 */
export const PrayerSearchUsageRows = {
  /** The row's first line. */
  titleLatin(context: LiturgicalUsageContext): string {
    return ObservanceTitle.latin(
      LiturgicalUsageContexts.dayTitleLatin(context),
    );
  },

  /** The row's second line, which is omitted when it would repeat the first. */
  titleEnglish(context: LiturgicalUsageContext): string | null {
    const english = LiturgicalUsageContexts.dayTitleEnglish(context);
    if (
      english === null ||
      Strings.canonical(english) ===
        Strings.canonical(LiturgicalUsageContexts.dayTitleLatin(context))
    ) {
      return null;
    }
    return ObservanceTitle.english(english);
  },

  settingSummary(context: LiturgicalUsageContext): string {
    if (context.settingModes.length === 0) {
      return "No chant setting";
    }
    return context.settingModes.map((mode) => `Mode ${mode}`).join(" · ");
  },

  accessibilityHint(context: LiturgicalUsageContext): string {
    return `Opens ${OfficeHours.englishTitle(context.hour)} for this church-calendar day`;
  },
};

/**
 * The text of a `PrayerSearchMassUsageRow`: a Mass that says a part of the
 * Mass that search found.
 */
export const PrayerSearchMassUsageRows = {
  /** Its day, the name that tells it from the day's other Masses, and the settings it sings. */
  summary(mass: MassUsageContext, formattedDate: string | null): string {
    return [
      formattedDate,
      mass.labelEnglish ?? mass.label ?? null,
      ...(mass.settings ?? []),
    ]
      .filter((part): part is string => part !== null)
      .join(" · ");
  },
};

/** A part of the Mass, named as the Missal names its parts. */
function massPartTitle(result: LiturgicalSearchResult): string {
  switch (result.kind) {
    case "introit":
      return "Introit";
    case "kyrie":
      return "Kyrie";
    case "gloria":
      return "Gloria";
    case "collect":
      return "Collect";
    case "epistle":
      return "Epistle";
    case "reading":
      return "Lesson";
    case "gradual":
      return "Gradual";
    case "alleluia":
      return "Alleluia";
    case "tract":
      return "Tract";
    case "sequence":
      return "Sequence";
    case "gospel":
      return "Gospel";
    case "credo":
      return "Credo";
    case "offertory":
      return "Offertory";
    case "secret":
      return "Secret";
    case "preface":
      return "Preface";
    case "sanctus":
      return "Sanctus";
    case "canon":
      return "Canon";
    case "paterNoster":
      return "Pater Noster";
    case "agnusDei":
      return "Agnus Dei";
    case "communion":
      return "Communion";
    case "postcommunion":
      return "Postcommunion";
    case "dismissal":
      return "Dismissal";
    case "lastGospel":
      return "Last Gospel";
    case "psalm":
      return "Psalm";
    case "antiphon":
      return "Antiphon";
    case "responsory":
      return "Responsory";
    case "hymn":
      return "Hymn";
    case "versicle":
      return "Versicle";
    case "blessing":
      return "Blessing";
    case "rubric":
      return "Rubric";
    default:
      return "Prayer";
  }
}

function normalized(value: string): string {
  // Swift folds in the Latin locale, which has no casing rules of its own.
  return Strings.canonical(
    SwiftString.trimmingWhitespaceAndNewlines(
      SwiftString.folding(value, {
        caseInsensitive: true,
        diacriticInsensitive: true,
      }),
    ),
  );
}

/** `Set(result.contexts.map(\.hour))`, in the order the hours are first met. */
function hours(result: LiturgicalSearchResult): OfficeHour[] {
  return [...new Set(result.contexts.map((context) => context.hour))];
}

function readingTitle(result: LiturgicalSearchResult): string {
  const found = hours(result);
  if (found.length !== 1) {
    return "Reading";
  }
  return `${OfficeHours.englishTitle(found[0])} Reading`;
}

function isLikelyMatinsReading(result: LiturgicalSearchResult): boolean {
  const found = hours(result);
  if (!(found.length === 1 && found[0] === "matins")) {
    return false;
  }
  if (result.kind === "reading") {
    return true;
  }
  const title = normalized(result.titleLatin);
  if (
    result.kind === "blessing" &&
    FoundationStrings.contains(title, "lectio")
  ) {
    return true;
  }
  if (!(result.kind === "prayer" && title === "pater")) {
    return false;
  }
  const latin = normalized(result.latin);
  return (
    !Strings.hasPrefix(latin, "pater noster") &&
    !Strings.hasPrefix(latin, "confiteor deo")
  );
}

function isSearchHit(
  value: LiturgicalSearchHit | LiturgicalSearchResult,
): value is LiturgicalSearchHit {
  return "snippet" in value;
}

export const SearchResultPresentation = {
  /**
   * Both of Swift's `title(for:)`: the one for a hit titles the result that
   * the hit's own fields make, which is used in no office.
   */
  title(value: LiturgicalSearchHit | LiturgicalSearchResult): string {
    if (isSearchHit(value)) {
      const hit = value;
      return SearchResultPresentation.title(
        LiturgicalSearchResults.make({
          id: hit.id,
          kind: hit.kind,
          titleLatin: hit.titleLatin,
          titleEnglish: hit.titleEnglish,
          latin: hit.snippetLanguage === "latin" ? hit.snippet : "",
          english: hit.snippetLanguage === "english" ? hit.snippet : null,
        }),
      );
    }
    const result = value;
    if (result.id.startsWith(MassPartSearch.idPrefix)) {
      return massPartTitle(result);
    }
    if (isLikelyMatinsReading(result)) {
      return readingTitle(result);
    }
    switch (result.kind) {
      case "opening":
        return normalized(result.titleLatin) === "incipit"
          ? "Incipit"
          : "Opening";
      case "invitatory":
        return "Invitatory";
      case "prayer": {
        const latin = normalized(result.latin);
        if (Strings.hasPrefix(latin, "confiteor deo")) return "Confiteor";
        if (Strings.hasPrefix(latin, "pater noster")) return "Our Father";
        return "Prayer";
      }
      case "rubric":
        return "Rubric";
      case "reading":
        return readingTitle(result);
      case "absolution":
        return "Absolution";
      case "blessing":
        return "Blessing";
      case "psalm":
        return Strings.hasPrefix(normalized(result.titleLatin), "psalm")
          ? result.titleLatin
          : "Psalm";
      case "antiphon":
        return FoundationStrings.contains(
          normalized(result.titleLatin),
          "antiphona finalis",
        )
          ? "Marian Antiphon"
          : "Antiphon";
      case "chapter":
        return "Chapter";
      case "responsory":
        return "Responsory";
      case "hymn":
        return "Hymn";
      case "versicle":
        return "Versicle";
      case "canticle":
        return Strings.hasPrefix(normalized(result.titleLatin), "canticum")
          ? result.titleLatin
          : "Canticle";
      case "collect":
        return "Collect";
      case "preces":
        return "Preces";
      case "conclusion":
        return "Conclusion";
      case "marianAntiphon":
        return "Marian Antiphon";
      default:
        return "Office Text";
    }
  },
};
