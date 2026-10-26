// The Office's domain model, kept parallel to `HoursCore/Models.swift`.
// Values are plain immutable data; the behaviour Swift attaches to a type is
// exported beside it as a namespace of functions bearing the same names.

export interface LocalDay {
  readonly year: number;
  readonly month: number;
  readonly day: number;
}

function pad(value: number, width: number): string {
  return String(value).padStart(width, "0");
}

export const LocalDays = {
  make(year: number, month: number, day: number): LocalDay {
    return { year, month, day };
  },

  /** The civil date of an instant in the reader's own time zone. */
  fromDate(date: Date): LocalDay {
    return {
      year: date.getFullYear(),
      month: date.getMonth() + 1,
      day: date.getDate(),
    };
  },

  fromISO(iso8601: string): LocalDay | null {
    const parts = iso8601.split("-");
    if (parts.length !== 3) return null;
    const [year, month, day] = parts.map((part) =>
      /^[+-]?\d+$/.test(part) ? Number.parseInt(part, 10) : Number.NaN,
    );
    if ([year, month, day].some((value) => Number.isNaN(value))) return null;
    return { year, month, day };
  },

  /** `YYYY-MM-DD`, the form in which the corpus names a civil date. */
  description(day: LocalDay): string {
    return `${pad(day.year, 4)}-${pad(day.month, 2)}-${pad(day.day, 2)}`;
  },

  /** Local midnight of the civil date. */
  date(day: LocalDay): Date {
    return new Date(day.year, day.month - 1, day.day);
  },

  compare(lhs: LocalDay, rhs: LocalDay): number {
    return lhs.year - rhs.year || lhs.month - rhs.month || lhs.day - rhs.day;
  },

  equals(lhs: LocalDay, rhs: LocalDay): boolean {
    return LocalDays.compare(lhs, rhs) === 0;
  },

  isBefore(lhs: LocalDay, rhs: LocalDay): boolean {
    return LocalDays.compare(lhs, rhs) < 0;
  },

  adding(day: LocalDay, days: number): LocalDay {
    return LocalDays.fromDate(
      new Date(day.year, day.month - 1, day.day + days),
    );
  },

  /**
   * The date Hours selects while following the current canonical hour.
   *
   * Matins opens the liturgical day, so the automatic Office date is the
   * civil date: Matins said after midnight is that of the new day. The
   * following day's First Vespers and Compline are already stored under the
   * evening's civil date.
   */
  currentOfficeDay(at: Date = new Date()): LocalDay {
    return LocalDays.fromDate(at);
  },

  firstSundayOfAdvent(year: number): LocalDay {
    const november27 = new Date(year, 10, 27);
    const daysUntilSunday = (7 - november27.getDay()) % 7;
    return LocalDays.fromDate(new Date(year, 10, 27 + daysUntilSunday));
  },

  /**
   * The church-calendar year containing this day, from the First Sunday of
   * Advent through the day before the following First Sunday of Advent.
   */
  liturgicalYearRange(day: LocalDay): { start: LocalDay; end: LocalDay } {
    const adventThisCivilYear = LocalDays.firstSundayOfAdvent(day.year);
    const startYear = LocalDays.isBefore(day, adventThisCivilYear)
      ? day.year - 1
      : day.year;
    const start = LocalDays.firstSundayOfAdvent(startYear);
    const nextStart = LocalDays.firstSundayOfAdvent(startYear + 1);
    return { start, end: LocalDays.adding(nextStart, -1) };
  },

  /**
   * The days searched for the Offices to come: from this day through the end
   * of the church-calendar year after the one containing it. Whatever a
   * church year holds lies within them, so the first occurrence found of an
   * Office is its next. A span of twelve months would not serve: the days
   * that follow Easter fall later in some years than in the year before, and
   * those just past would lie beyond it.
   */
  upcomingOfficesRange(day: LocalDay): { start: LocalDay; end: LocalDay } {
    const thisYear = LocalDays.liturgicalYearRange(day);
    const nextYear = LocalDays.liturgicalYearRange(
      LocalDays.adding(thisYear.end, 1),
    );
    return { start: day, end: nextYear.end };
  },
};

export const officeHours = [
  "matins",
  "lauds",
  "prime",
  "terce",
  "sext",
  "none",
  "vespers",
  "compline",
] as const;
export type OfficeHour = (typeof officeHours)[number];

const latinTitles: Record<OfficeHour, string> = {
  matins: "Ad Matutinum",
  lauds: "Ad Laudes",
  prime: "Ad Primam",
  terce: "Ad Tertiam",
  sext: "Ad Sextam",
  none: "Ad Nonam",
  vespers: "Ad Vesperas",
  compline: "Ad Completorium",
};

const latinNames: Record<OfficeHour, string> = {
  matins: "Matutinum",
  lauds: "Laudes",
  prime: "Prima",
  terce: "Tertia",
  sext: "Sexta",
  none: "Nona",
  vespers: "Vesperae",
  compline: "Completorium",
};

const englishTitles: Record<OfficeHour, string> = {
  matins: "Matins",
  lauds: "Lauds",
  prime: "Prime",
  terce: "Terce",
  sext: "Sext",
  none: "None",
  vespers: "Vespers",
  compline: "Compline",
};

const customaryMinuteRanges: Record<OfficeHour, readonly [number, number]> = {
  matins: [0, 4 * 60],
  lauds: [4 * 60, 6 * 60],
  prime: [6 * 60, 8 * 60],
  terce: [8 * 60, 10 * 60],
  sext: [10 * 60, 13 * 60],
  none: [13 * 60, 16 * 60],
  vespers: [16 * 60, 20 * 60],
  compline: [20 * 60, 24 * 60],
};

function timeLabel(minuteOfDay: number): string {
  const normalizedMinute = minuteOfDay % (24 * 60);
  const hour24 = Math.floor(normalizedMinute / 60);
  const minute = normalizedMinute % 60;
  const hour12 = hour24 % 12 === 0 ? 12 : hour24 % 12;
  const suffix = hour24 < 12 ? "am" : "pm";
  return minute === 0
    ? `${hour12}${suffix}`
    : `${hour12}:${pad(minute, 2)}${suffix}`;
}

export const OfficeHours = {
  allCases: officeHours,

  isOfficeHour(value: unknown): value is OfficeHour {
    return (
      typeof value === "string" &&
      (officeHours as readonly string[]).includes(value)
    );
  },

  latinTitle(hour: OfficeHour): string {
    return latinTitles[hour];
  },

  latinName(hour: OfficeHour): string {
    return latinNames[hour];
  },

  englishTitle(hour: OfficeHour): string {
    return englishTitles[hour];
  },

  /** Minutes after local midnight at which the hour customarily begins and ends. */
  customaryMinuteRange(hour: OfficeHour): { start: number; end: number } {
    const [start, end] = customaryMinuteRanges[hour];
    return { start, end };
  },

  customaryTimeRange(hour: OfficeHour): string {
    const { start, end } = OfficeHours.customaryMinuteRange(hour);
    return `${timeLabel(start)} – ${timeLabel(end)}`;
  },

  /** The canonical hour whose customary time contains the local clock time. */
  current(at: Date = new Date()): OfficeHour {
    const minuteOfDay = at.getHours() * 60 + at.getMinutes();
    return (
      officeHours.find((hour) => {
        const { start, end } = OfficeHours.customaryMinuteRange(hour);
        return start < end
          ? start <= minuteOfDay && minuteOfDay < end
          : minuteOfDay >= start || minuteOfDay < end;
      }) ?? "matins"
    );
  },
};

export type LiturgicalRank =
  "firstClass" | "secondClass" | "thirdClass" | "fourthClass";

const rankDisplayNames: Record<LiturgicalRank, string> = {
  firstClass: "I. classis",
  secondClass: "II. classis",
  thirdClass: "III. classis",
  fourthClass: "IV. classis",
};

export const LiturgicalRanks = {
  displayName(rank: LiturgicalRank): string {
    return rankDisplayNames[rank];
  },

  englishDisplayName(rank: LiturgicalRank): string {
    return rankDisplayNames[rank].replaceAll("classis", "Class");
  },
};

export type LiturgicalColor =
  "white" | "red" | "green" | "violet" | "rose" | "black";

export type EveningContext = "firstVespers" | "secondVespers" | "ferialVespers";

export const EveningContexts = {
  displayName(context: EveningContext): string {
    switch (context) {
      case "firstVespers":
        return "First Vespers";
      case "secondVespers":
        return "Second Vespers";
      case "ferialVespers":
        return "Vespers";
    }
  },
};

export interface Commemoration {
  readonly id: string;
  readonly titleLatin: string;
  readonly titleEnglish?: string | null;
}

export interface LiturgicalDay {
  readonly date: LocalDay;
  readonly observanceID: string;
  readonly titleLatin: string;
  readonly titleEnglish?: string | null;
  readonly rank?: LiturgicalRank | null;
  readonly sourceRank?: string | null;
  readonly color?: LiturgicalColor | null;
  readonly season: string;
  readonly eveningContext?: EveningContext | null;
  readonly commemorations: readonly Commemoration[];
  readonly sourceVersion: string;
}

interface Ranked {
  readonly rank?: LiturgicalRank | null;
  readonly sourceRank?: string | null;
}

export const Ranks = {
  rankDisplayName(value: Ranked): string | null {
    return (
      value.sourceRank ??
      (value.rank ? LiturgicalRanks.displayName(value.rank) : null)
    );
  },

  /**
   * The rank as shown to readers: the 1960 class in English, otherwise the
   * source's own rite (for example, "Duplex II. classis").
   */
  rankLabel(value: Ranked): string | null {
    return (
      (value.rank ? LiturgicalRanks.englishDisplayName(value.rank) : null) ??
      value.sourceRank ??
      null
    );
  },
};

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
  // The parts of the Mass, beside the Office's own.
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
  "lastGospel",
] as const;
export type OfficeSectionKind = (typeof officeSectionKinds)[number];

const pieceKinds: ReadonlySet<OfficeSectionKind> = new Set([
  "invitatory",
  "antiphon",
  "responsory",
  "hymn",
  "marianAntiphon",
  "introit",
  "kyrie",
  "gloria",
  "gradual",
  "alleluia",
  "tract",
  "sequence",
  "credo",
  "offertory",
  "sanctus",
  "agnusDei",
  "communion",
]);

export const OfficeSectionKinds = {
  /**
   * Whether a chant in a section of this kind is a piece the chant books
   * open with an initial: an antiphon, a hymn, a responsory, or a sung part
   * of the Mass. A psalm or canticle, a versicle, and the tones of prayers
   * and readings take none.
   */
  opensPiece(kind: OfficeSectionKind): boolean {
    return pieceKinds.has(kind);
  },
};

export type ChantReviewStatus =
  | "exactMatch"
  | "humanReviewed"
  | "generatedFormula"
  | "sourceTranscription"
  | "ambiguous"
  | "missing";

export type ChantNotationModifier =
  | "mora"
  | "episema"
  | "quilisma"
  | "liquescent"
  | "flat"
  | "natural"
  | "sharp"
  | "phraseBoundary";

export interface ChantClef {
  readonly kind: "c" | "f";
  readonly line: number;
  readonly flattensB: boolean;
}

export interface ChantEvent {
  readonly id: string;
  readonly phraseID: string;
  readonly syllableID: string;
  readonly syllable: string;
  readonly relativePitch: number;
  readonly durationWeight: number;
  readonly modifiers: readonly ChantNotationModifier[];
  readonly clef?: ChantClef | null;
}

export interface ChantTimeline {
  readonly events: readonly ChantEvent[];
}

export const ChantTimelines = {
  phraseIDs(timeline: ChantTimeline): string[] {
    const result: string[] = [];
    for (const event of timeline.events) {
      if (result[result.length - 1] !== event.phraseID) {
        result.push(event.phraseID);
      }
    }
    return result;
  },

  totalDurationWeight(timeline: ChantTimeline): number {
    return timeline.events.reduce(
      (total, event) => total + event.durationWeight,
      0,
    );
  },
};

export interface ChantProvenance {
  readonly collection: string;
  readonly sourceBook: string;
  readonly sourceURL?: string | null;
  readonly license: string;
  readonly snapshot: string;
  readonly sourceRevision?: string | null;
  readonly notice?: string | null;
  readonly modifications?: string | null;
  readonly correspondingSource?: string | null;
}

/**
 * A complete, indivisible pairing of GABC lyrics, neumes, and event identity.
 * Hours never applies the notation to a separately syllabified text.
 */
export interface ChantScore {
  readonly id: string;
  readonly incipit: string;
  readonly gabc: string;
  readonly mode?: string | null;
  readonly reviewStatus: ChantReviewStatus;
  readonly provenance: ChantProvenance;
  readonly timeline: ChantTimeline;
}

export interface OfficeSection {
  readonly id: string;
  readonly kind: OfficeSectionKind;
  readonly title: string;
  readonly titleEnglish?: string | null;
  readonly rubric?: string | null;
  readonly rubricEnglish?: string | null;
  readonly latin: string;
  readonly english?: string | null;
  readonly chant?: ChantScore | null;
  /** In a Mass, whether the section is of the Ordinary rather than proper
   * to the day, as the Missal's compiler marks it. */
  readonly ordinary?: boolean;
  /**
   * Whether these are words that all say, whoever is present, though a
   * priest or deacon says otherwise where they stand elsewhere: the
   * versicle Dómine, exáudi before the direction to omit the second
   * greeting. The reader marks such a section as it arranges an Hour; no
   * edition stores the mark.
   */
  readonly isSaidByAll?: boolean;
}

export const OfficeSections = {
  /** A rubric that merely repeats the chant's own collection is not shown. */
  userFacingRubric(section: OfficeSection): string | null {
    const rubric = section.rubric ?? null;
    const collection = section.chant?.provenance.collection;
    if (rubric === null || collection === undefined) return rubric;
    if (rubric === collection || rubric.startsWith(`${collection} · `)) {
      return null;
    }
    return rubric;
  },
};

export type OfficeDocumentFormat =
  | "authoritativeOrdered"
  /** Faithful ordered source import, awaiting independent liturgical review. */
  | "sourceOrdered"
  | "legacyReconstructed"
  | "contentUnavailable"
  /** A Mass of the Missal, in the order of its source. */
  | "missal";

export interface OfficeObservance {
  readonly observanceID: string;
  readonly titleLatin: string;
  readonly titleEnglish?: string | null;
  readonly rank?: LiturgicalRank | null;
  readonly sourceRank?: string | null;
  readonly color?: LiturgicalColor | null;
  readonly season?: string | null;
  readonly eveningContext?: EveningContext | null;
  readonly commemorations: readonly Commemoration[];
}

export interface OfficeDocument {
  readonly id: string;
  readonly date: LocalDay;
  readonly hour: OfficeHour;
  readonly titleLatin: string;
  readonly titleEnglish?: string | null;
  readonly contextLabel: string;
  readonly sourceVersion: string;
  readonly format?: OfficeDocumentFormat | null;
  readonly visibleContentDigest?: string | null;
  readonly observance?: OfficeObservance | null;
  readonly sections: readonly OfficeSection[];
}

export const OfficeDocuments = {
  preservesSourceOrder(
    format: OfficeDocumentFormat | null | undefined,
  ): boolean {
    return (
      format === "authoritativeOrdered" ||
      format === "sourceOrdered" ||
      format === "missal"
    );
  },

  /** Whether a document is a Mass of the Missal rather than an Hour. */
  isMass(office: OfficeDocument): boolean {
    return office.format === "missal";
  },

  /**
   * The document's name in English, as a print job or a heading names it:
   * the Hour's, or Holy Mass. A Mass is stored at Terce, after which it is
   * sung, but is not named for it.
   */
  englishName(office: OfficeDocument): string {
    return OfficeDocuments.isMass(office)
      ? "Holy Mass"
      : OfficeHours.englishTitle(office.hour);
  },

  playableScores(office: OfficeDocument): ChantScore[] {
    return office.sections
      .map((section) => section.chant)
      .filter(
        (chant): chant is ChantScore =>
          chant != null && chant.timeline.events.length > 0,
      );
  },
};

const months =
  "Januarii|Februarii|Martii|Aprilis|Maii|Iunii|Junii|Iulii|Julii|Augusti|Septembris|Octobris|Novembris|Decembris";

/**
 * How an observance title is shown, wherever it appears.
 *
 * Source titles may carry the week-of-month marker that selects the week's
 * Scripture ("Dominica XIX Post Pentecosten I. Octobris"), or its ordinal
 * alone once the month was removed ("… Post Pentecosten I."); neither is part
 * of the title. English titles are stored for use after "of" ("the First
 * Sunday of Advent") and begin with a capital when they stand alone.
 */
export const ObservanceTitle = {
  latin(title: string): string {
    return title
      .replace(new RegExp(`\\s+[IVX]+\\.\\s+(?:${months})\\s*$`, "i"), "")
      .replace(
        /(\b(?:Post Pentecosten|post Octavam Pentecostes))\s+[IVXLCDM]+\.\s*$/i,
        "$1",
      );
  },

  english(title: string): string {
    const value = title.replace(
      /(\b(?:Sunday after Pentecost|Week after the Octave of Pentecost)),\s*(?:the\s+)?(?:First|Second|Third|Fourth|Fifth)\s*$/i,
      "$1",
    );
    const first = value.charAt(0);
    if (first === "" || first === first.toUpperCase()) return value;
    return first.toUpperCase() + value.slice(1);
  },
};
