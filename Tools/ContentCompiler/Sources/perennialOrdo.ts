import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { resolve } from "node:path";
import { officeHours, type OfficeHour } from "./types.ts";

export interface PerennialOrdoDay {
  date: string;
  titleLatin: string;
  rankLatin: string;
  occurrenceDetailLatin: string;
  concurrenceDetailLatin: string;
  weekdayLatin: string;
}

export interface PerennialOrdoSchedule {
  sourceRevision: string;
  rubrics: "Rubrics 1960 - 1960";
  from: string;
  to: string;
  days: PerennialOrdoDay[];
}

export interface PerennialOrdoRange {
  from: string;
  to: string;
}

export function perennialOrdoRange(
  schedule: PerennialOrdoSchedule,
  range?: PerennialOrdoRange
): PerennialOrdoRange {
  const selected = range ?? { from: schedule.from, to: schedule.to };
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(selected.from)
    || !/^\d{4}-\d{2}-\d{2}$/.test(selected.to)
    || selected.from > selected.to
    || selected.from < schedule.from
    || selected.to > schedule.to
  ) {
    throw new Error(
      `Perennial window ${selected.from} through ${selected.to} is outside `
      + `${schedule.from} through ${schedule.to}`
    );
  }
  return selected;
}

const namedEntities: Record<string, string> = {
  amp: "&",
  apos: "'",
  gt: ">",
  lt: "<",
  nbsp: " ",
  ensp: " ",
  quot: "\""
};

function decodeEntities(value: string): string {
  return value.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (match, entity: string) => {
    if (entity.startsWith("#x")) {
      return String.fromCodePoint(Number.parseInt(entity.slice(2), 16));
    }
    if (entity.startsWith("#")) {
      return String.fromCodePoint(Number.parseInt(entity.slice(1), 10));
    }
    return namedEntities[entity.toLowerCase()] ?? match;
  });
}

function textFromHTML(value: string): string {
  return decodeEntities(
    value
      .replace(/<br\s*\/?>/gi, "\n")
      .replace(/<[^>]+>/g, " ")
  )
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n[ \t]+/g, "\n")
    .replace(/[ \t]{2,}/g, " ")
    .trim();
}

export function parsePerennialOrdoYear(html: string, expectedYear: number): PerennialOrdoDay[] {
  const days: PerennialOrdoDay[] = [];
  for (const row of html.matchAll(/<TR>([\s\S]*?)<\/TR>/gi)) {
    const date = row[1].match(/callbrevi\('(\d{2})-(\d{2})-(\d{4})'\)/);
    if (!date || Number(date[3]) !== expectedYear) continue;
    const cells = [...row[1].matchAll(/<TD[^>]*>([\s\S]*?)<\/TD>/gi)]
      .map(match => match[1]);
    if (cells.length < 5) {
      throw new Error(`Ordo row ${date[0]} does not contain five columns`);
    }
    const officeCells = cells.slice(1, 3);
    const winnerCell = officeCells.find(cell => /<B>/i.test(cell));
    if (!winnerCell) {
      throw new Error(`Ordo row ${date[0]} has no winning observance`);
    }
    const titleMatch = winnerCell.match(/<B>([\s\S]*?)<\/B>/i);
    const titleLatin = textFromHTML(titleMatch?.[1] ?? winnerCell);
    const rankLatin = textFromHTML(winnerCell.replace(/<B>[\s\S]*?<\/B>/i, ""));
    const occurrenceDetailLatin = textFromHTML(
      officeCells.filter(cell => cell !== winnerCell).join("\n")
    );
    days.push({
      date: `${date[3]}-${date[1]}-${date[2]}`,
      titleLatin,
      rankLatin,
      occurrenceDetailLatin,
      concurrenceDetailLatin: textFromHTML(cells[3]),
      weekdayLatin: textFromHTML(cells[4])
    });
  }
  const expectedDays = (
    Date.UTC(expectedYear + 1, 0, 1) - Date.UTC(expectedYear, 0, 1)
  ) / 86_400_000;
  if (days.length !== expectedDays) {
    throw new Error(`Ordo ${expectedYear} contains ${days.length} days; expected ${expectedDays}`);
  }
  return days;
}

export function generatePerennialOrdo(options: {
  sourceRoot: string;
  sourceRevision: string;
  fromYear: number;
  toYear: number;
}): PerennialOrdoSchedule {
  if (options.fromYear > options.toYear || options.fromYear < 1583) {
    throw new Error("Invalid perennial ordo year range");
  }
  const sourceRoot = resolve(options.sourceRoot);
  const actualRevision = execFileSync("git", ["rev-parse", "HEAD"], {
    cwd: sourceRoot,
    encoding: "utf8"
  }).trim();
  if (actualRevision !== options.sourceRevision) {
    throw new Error(
      `Divinum Officium checkout is ${actualRevision}; expected ${options.sourceRevision}`
    );
  }
  const script = `${sourceRoot}/web/cgi-bin/horas/kalendar.pl`;
  const days: PerennialOrdoDay[] = [];
  for (let year = options.fromYear; year <= options.toYear; year += 1) {
    const query = new URLSearchParams({
      kyear: String(year),
      kmonth: "14",
      version: "Rubrics 1960 - 1960",
      lang1: "Latin",
      lang2: "English"
    }).toString();
    const html = execFileSync("perl", [script], {
      cwd: sourceRoot,
      encoding: "utf8",
      env: {
        ...process.env,
        REQUEST_METHOD: "GET",
        QUERY_STRING: query
      },
      maxBuffer: 8 * 1_024 * 1_024
    });
    days.push(...parsePerennialOrdoYear(html, year));
  }
  return {
    sourceRevision: options.sourceRevision,
    rubrics: "Rubrics 1960 - 1960",
    from: `${options.fromYear}-01-01`,
    to: `${options.toYear}-12-31`,
    days
  };
}

function stableKey(parts: string[]): string {
  return createHash("sha256").update(parts.join("\u001f")).digest("hex");
}

function followingMonthDay(date: string): string {
  const value = new Date(`${date}T12:00:00Z`);
  value.setUTCDate(value.getUTCDate() + 1);
  return value.toISOString().slice(5, 10);
}

export function officeConfigurationKey(
  day: PerennialOrdoDay,
  hour: OfficeHour,
  followingDay?: PerennialOrdoDay
): string {
  const common = [
    day.titleLatin,
    day.rankLatin,
    day.occurrenceDetailLatin,
    day.weekdayLatin,
    hour
  ];
  if (hour === "vespers" || hour === "compline") {
    common.push(day.concurrenceDetailLatin);
    // A generic "Vespera de sequenti" rubric does not name the following
    // observance. Include its identity so First Vespers of different feasts
    // can never collapse onto one recipe merely because the current daytime
    // office is otherwise identical.
    if (/de sequenti/i.test(day.concurrenceDetailLatin)) {
      common.push(
        followingDay?.titleLatin ?? "",
        followingDay?.rankLatin ?? ""
      );
    }
  }
  if (hour === "prime") common.push(followingMonthDay(day.date));
  return stableKey(common);
}

export function uniqueOfficeConfigurations(schedule: PerennialOrdoSchedule): Map<string, {
  representativeDate: string;
  hour: OfficeHour;
}>;
export function uniqueOfficeConfigurations(
  schedule: PerennialOrdoSchedule,
  range: PerennialOrdoRange | undefined
): Map<string, { representativeDate: string; hour: OfficeHour }>;
export function uniqueOfficeConfigurations(
  schedule: PerennialOrdoSchedule,
  range?: PerennialOrdoRange
): Map<string, { representativeDate: string; hour: OfficeHour }> {
  const selected = perennialOrdoRange(schedule, range);
  const result = new Map<string, { representativeDate: string; hour: OfficeHour }>();
  for (const [index, day] of schedule.days.entries()) {
    if (day.date < selected.from || day.date > selected.to) continue;
    const followingDay = schedule.days[index + 1];
    for (const hour of officeHours) {
      const key = officeConfigurationKey(day, hour, followingDay);
      if (!result.has(key)) {
        result.set(key, { representativeDate: day.date, hour });
      }
    }
  }
  return result;
}
