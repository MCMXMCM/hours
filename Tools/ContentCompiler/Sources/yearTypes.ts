// Under fixed rubrics the Office of a civil year follows from two facts only:
// the date of Easter and whether the year is a leap year. Thirty-five Easter
// dates and two lengths of year make seventy "year types", and every year of
// one type has, date for date, the same Office (the Martyrology's Moon and
// year excepted, which the reader computes). An edition therefore stores one
// civil year of each type it serves and reads any other year from the stored
// year of its type.
//
// This module is shared by the compiler and the web app, so it must remain
// free of Node-only imports.

export interface CivilMonthDay {
  month: number;
  day: number;
}

/** Easter in the Gregorian calendar (the anonymous Gregorian computus). */
export function gregorianEaster(year: number): CivilMonthDay {
  if (!Number.isInteger(year) || year < 1583 || year > 4099) {
    throw new Error(`Gregorian computus year ${year} is unsupported`);
  }
  const a = year % 19;
  const b = Math.floor(year / 100);
  const c = year % 100;
  const d = Math.floor(b / 4);
  const e = b % 4;
  const f = Math.floor((b + 8) / 25);
  const g = Math.floor((b - f + 1) / 3);
  const h = (19 * a + b - d - g + 15) % 30;
  const i = Math.floor(c / 4);
  const k = c % 4;
  const l = (32 + 2 * e + 2 * i - h - k) % 7;
  const m = Math.floor((a + 11 * h + 22 * l) / 451);
  return {
    month: Math.floor((h + l - 7 * m + 114) / 31),
    day: ((h + l - 7 * m + 114) % 31) + 1
  };
}

export function isLeapYear(year: number): boolean {
  return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
}

/** A year's type, as `MM-DD` of Easter followed by `L` (leap) or `C` (common). */
export function yearType(year: number): string {
  const easter = gregorianEaster(year);
  return `${String(easter.month).padStart(2, "0")}-${String(easter.day).padStart(2, "0")}`
    + (isLeapYear(year) ? "L" : "C");
}

/**
 * The first version of the app that reads a perennial edition. An earlier
 * version would take the stored years for the dates served, so every such
 * edition declares this as its minimum app version.
 */
export const perennialMinimumAppVersion = "1.1.1";

/**
 * The civil years an edition stores, and the years it thereby serves.
 * `years` lists the stored years in order; `representative` gives, for each
 * year type served, the stored year of that type.
 */
export interface PerennialYearPlan {
  /** The first and last civil years served, inclusive. */
  from: number;
  to: number;
  years: number[];
  representative: Record<string, number>;
}

/**
 * Chooses the stored years. Every year from `from` onward is served for as
 * long as its type has a year the source can render (`renderFrom` through
 * `renderTo`); the plan ends before the first year whose type has none. A
 * type is stored as its first year on or after `from`, so that the years
 * first prayed are stored as themselves; a type that does not recur within
 * the renderable years is stored as its latest earlier year.
 */
export function planPerennialYears(options: {
  from: number;
  renderFrom: number;
  renderTo: number;
  /** Serve no year after this one, where the plan would reach further. */
  to?: number;
}): PerennialYearPlan {
  const { from, renderFrom, renderTo } = options;
  if (![from, renderFrom, renderTo].every(Number.isInteger) || renderFrom > renderTo
    || from < renderFrom || from > renderTo) {
    throw new Error("Invalid perennial year plan");
  }
  const renderable = new Map<string, number>();
  for (let year = from - 1; year >= renderFrom; year -= 1) {
    if (!renderable.has(yearType(year))) renderable.set(yearType(year), year);
  }
  // A later pass, so that a year on or after `from` displaces an earlier one.
  const upcoming = new Map<string, number>();
  for (let year = from; year <= renderTo; year += 1) {
    if (!upcoming.has(yearType(year))) upcoming.set(yearType(year), year);
  }
  const representative: Record<string, number> = {};
  const limit = Math.min(options.to ?? 4099, 4099);
  let to = from - 1;
  for (let year = from; year <= limit; year += 1) {
    const type = yearType(year);
    if (representative[type] === undefined) {
      const stored = upcoming.get(type) ?? renderable.get(type);
      if (stored === undefined) break;
      representative[type] = stored;
    }
    to = year;
  }
  if (to < from) throw new Error(`No renderable year has the type of ${from}`);
  return {
    from,
    to,
    years: Object.values(representative).sort((left, right) => left - right),
    representative
  };
}

/**
 * The plan of an edition that serves `from` through `to` from these stored
 * years. Each stored year stands for its own type, so no two may share one.
 */
export function perennialYearPlan(from: number, to: number, years: readonly number[]): PerennialYearPlan {
  const representative: Record<string, number> = {};
  for (const year of years) {
    const type = yearType(year);
    if (representative[type] !== undefined) {
      throw new Error(`Stored years ${representative[type]} and ${year} have the same year type ${type}`);
    }
    representative[type] = year;
  }
  const plan = { from, to, years: [...years], representative };
  validatePerennialYearPlan(plan);
  return plan;
}

/** Rejects a plan that does not hold one stored year of its own type per type. */
export function validatePerennialYearPlan(plan: PerennialYearPlan): void {
  const entries = Object.entries(plan.representative);
  if (!Number.isInteger(plan.from) || !Number.isInteger(plan.to) || plan.from > plan.to) {
    throw new Error("A perennial year plan must serve at least one year");
  }
  if (entries.length === 0 || entries.some(([type, year]) => yearType(year) !== type)) {
    throw new Error("A perennial year plan stores a year under a type that is not its own");
  }
  const stored = entries.map(([, year]) => year).sort((left, right) => left - right);
  if (stored.length !== plan.years.length || stored.some((year, index) => year !== plan.years[index])) {
    throw new Error("A perennial year plan must list its stored years once each, in order");
  }
  for (let year = plan.from; year <= plan.to; year += 1) {
    if (plan.representative[yearType(year)] === undefined) {
      throw new Error(`A perennial year plan serves ${year} but stores no year of its type`);
    }
  }
}

/** The stored year from which `year` is read; null when the plan does not serve it. */
export function storedYear(plan: PerennialYearPlan, year: number): number | null {
  if (!Number.isInteger(year) || year < plan.from || year > plan.to) return null;
  return plan.representative[yearType(year)] ?? null;
}

/** The stored civil date (`YYYY-MM-DD`) from which a served date is read. */
export function storedDate(plan: PerennialYearPlan, isoDate: string): string | null {
  const year = storedYear(plan, Number(isoDate.slice(0, 4)));
  return year === null ? null : `${String(year).padStart(4, "0")}${isoDate.slice(4)}`;
}

/**
 * The first served year read from a stored year; null for a year the plan
 * does not store, or stores for no year it serves.
 */
export function firstServedYear(plan: PerennialYearPlan, stored: number): number | null {
  const type = yearType(stored);
  if (plan.representative[type] !== stored) return null;
  for (let year = plan.from; year <= plan.to; year += 1) {
    if (yearType(year) === type) return year;
  }
  return null;
}

/**
 * A range of served dates (`YYYY-MM-DD`, inclusive) as the stored ranges
 * that hold it, one for each civil year it touches, in order. Dates outside
 * the served years are left out.
 */
export function storedRanges(
  plan: PerennialYearPlan,
  from: string,
  to: string
): Array<{ servedYear: number; from: string; to: string }> {
  const first = `${String(plan.from).padStart(4, "0")}-01-01`;
  const last = `${String(plan.to).padStart(4, "0")}-12-31`;
  if (from > last || to < first || from > to) return [];
  const lower = from < first ? first : from;
  const upper = to > last ? last : to;
  const ranges: Array<{ servedYear: number; from: string; to: string }> = [];
  for (let year = Number(lower.slice(0, 4)); year <= Number(upper.slice(0, 4)); year += 1) {
    const stored = storedYear(plan, year);
    if (stored === null) continue;
    const prefix = String(year).padStart(4, "0");
    const start = lower.slice(0, 4) === prefix ? lower.slice(4) : "-01-01";
    const end = upper.slice(0, 4) === prefix ? upper.slice(4) : "-12-31";
    const storedPrefix = String(stored).padStart(4, "0");
    ranges.push({ servedYear: year, from: storedPrefix + start, to: storedPrefix + end });
  }
  return ranges;
}

/** Every civil date (`YYYY-MM-DD`) of a year, in order. */
export function civilDatesOfYear(year: number): string[] {
  const lengths = [31, isLeapYear(year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  const dates: string[] = [];
  for (const [index, length] of lengths.entries()) {
    for (let day = 1; day <= length; day += 1) {
      dates.push(
        `${String(year).padStart(4, "0")}-${String(index + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}`
      );
    }
  }
  return dates;
}
