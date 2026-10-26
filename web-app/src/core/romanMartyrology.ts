// The Martyrology's proclamation of the date and the Moon's age at Prime,
// parallel to `HoursCore/RomanMartyrologyCalendar.swift`.

import { LocalDays, type LocalDay, type OfficeDocument } from "./models.ts";

const latinLunarOrdinals = [
  "prima",
  "secúnda",
  "tértia",
  "quarta",
  "quinta",
  "sexta",
  "séptima",
  "octáva",
  "nona",
  "décima",
  "undécima",
  "duodécima",
  "tértia décima",
  "quarta décima",
  "quinta décima",
  "sexta décima",
  "décima séptima",
  "duodevicésima",
  "undevicésima",
  "vicésima",
  "vicésima prima",
  "vicésima secúnda",
  "vicésima tértia",
  "vicésima quarta",
  "vicésima quinta",
  "vicésima sexta",
  "vicésima séptima",
  "vicésima octáva",
  "vicésima nona",
  "tricésima",
];

const englishLunarOrdinals = [
  "first",
  "second",
  "third",
  "fourth",
  "fifth",
  "sixth",
  "seventh",
  "eighth",
  "ninth",
  "tenth",
  "eleventh",
  "twelfth",
  "thirteenth",
  "fourteenth",
  "fifteenth",
  "sixteenth",
  "seventeenth",
  "eighteenth",
  "nineteenth",
  "twentieth",
  "twenty-first",
  "twenty-second",
  "twenty-third",
  "twenty-fourth",
  "twenty-fifth",
  "twenty-sixth",
  "twenty-seventh",
  "twenty-eighth",
  "twenty-ninth",
  "thirtieth",
];

const englishMonths = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];

const millisecondsPerDay = 86_400_000;

function utc(day: LocalDay): number {
  return Date.UTC(day.year, day.month - 1, day.day);
}

function isLeapYear(year: number): boolean {
  return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
}

/** The day's ordinal within its year, counting January 1 as one. */
function ordinalDay(day: LocalDay): number {
  return (
    Math.round((utc(day) - Date.UTC(day.year, 0, 1)) / millisecondsPerDay) + 1
  );
}

function ordinalSuffix(value: number): string {
  const lastTwo = value % 100;
  if (lastTwo >= 11 && lastTwo <= 13) return "th";
  switch (value % 10) {
    case 1:
      return "st";
    case 2:
      return "nd";
    case 3:
      return "rd";
    default:
      return "th";
  }
}

function gregorianTableLunarDay(input: LocalDay): number {
  const epacts = [
    29, 10, 21, 2, 13, 24, 5, 16, 27, 8, 19, 30, 11, 22, 3, 14, 25, 6, 17,
  ];
  const goldenNumber = input.year % 19;
  const lunarMonths = [30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, 100];
  lunarMonths[12] = goldenNumber === 18 ? 29 : 30;
  if (isLeapYear(input.year) && input.month > 2) {
    lunarMonths[1] = 30;
  }
  if (goldenNumber === 0 || goldenNumber === 8 || goldenNumber === 11) {
    lunarMonths.unshift(30);
  }

  // The bissextile day is counted with February 24, so the Moon's age
  // is repeated on the 25th and the later days of February follow it.
  let calculationDay = input.day;
  if (isLeapYear(input.year) && input.month === 2 && input.day >= 25) {
    calculationDay = input.day - 1;
  }
  const calculationDate = LocalDays.make(
    input.year,
    input.month,
    calculationDay,
  );
  // Zero-based, as the pinned source computes it from Perl localtime
  // between 1970 and 2037. Its one-based fallback outside that interval
  // proclaims every day one day too old, so it is not reproduced.
  const sourceOrdinal = ordinalDay(calculationDate) - 1;
  // After the saltus lunae the last lunation of the nineteenth year has
  // 29 days, so January 1 of the following first year is its 29th day,
  // not the 30th which the source's table yields (for example, 2033).
  if (goldenNumber === 0 && sourceOrdinal === 0) {
    return 29;
  }

  let boundary = -epacts[goldenNumber] - 1;
  let index = 0;
  while (boundary < sourceOrdinal) {
    boundary += lunarMonths[index];
    index += 1;
  }
  boundary -= lunarMonths[index - 1];
  return sourceOrdinal - boundary;
}

/** The epact of a Gregorian year, the epact * being written 30. */
function gregorianEpact(year: number): number {
  const golden = year % 19;
  const century = Math.floor(year / 100);
  const value =
    (11 * golden +
      8 -
      century +
      Math.floor(century / 4) +
      Math.floor((8 * century + 13) / 25)) %
    30;
  const epact = (value + 30) % 30;
  return epact === 0 ? 30 : epact;
}

// Where the calendar of epacts begins each run of its labels (* xxix … i),
// as days of a common year counted from 1 January as zero: 1 and 31 January,
// 1 and 31 March, 29 April, 29 May, 27 June, 27 July, 25 August, 24
// September, 23 October, 22 November and 21 December. The runs are
// alternately of thirty days and of twenty-nine.
const epactCycleStarts = [
  0, 30, 59, 89, 118, 148, 177, 207, 236, 266, 295, 325, 354,
];

/** The days of a common year on which the calendar sets a year's epact, and so its new Moons. */
function newMoons(year: number): number[] {
  const epact = gregorianEpact(year);
  // With a golden number above eleven the epact 25 is the calendar's "25",
  // which stands a day earlier in the runs of twenty-nine days.
  const isArabic25 = epact === 25 && (year % 19) + 1 > 11;
  const moons: number[] = [];
  epactCycleStarts.forEach((start, cycle) => {
    let offset: number;
    if (cycle % 2 === 0) {
      offset = 30 - epact;
    } else if (isArabic25) {
      offset = 4;
    } else if (epact >= 26) {
      offset = 30 - epact;
    } else if (epact === 25) {
      // xxv and xxiv share a day.
      offset = 5;
    } else {
      offset = 29 - epact;
    }
    if (start + offset <= 364) moons.push(start + offset);
  });
  return moons;
}

/**
 * Whether a year's epact follows the preceding year's by the ordinary eleven
 * (or, after the nineteenth year of the cycle, twelve), with no solar or
 * lunar equation between them.
 */
function epactContinues(year: number): boolean {
  const step = (year - 1) % 19 === 18 ? 12 : 11;
  return (
    ((gregorianEpact(year - 1) + step - 1) % 30) + 1 === gregorianEpact(year)
  );
}

function epactCalendarLunarDay(input: LocalDay): number {
  // The bissextile day is counted with February 24, so it has no place of
  // its own in the calendar, and later days stand one place earlier.
  let position = ordinalDay(input) - 1;
  if (
    isLeapYear(input.year) &&
    (input.month > 2 || (input.month === 2 && input.day >= 25))
  ) {
    position -= 1;
  }
  const moons = newMoons(input.year);
  const elapsed = moons.filter((moon) => moon <= position);
  if (elapsed.length > 0) return position - elapsed[elapsed.length - 1] + 1;
  const first = moons[0];
  const earlier = newMoons(input.year - 1);
  const previous = earlier[earlier.length - 1];
  if (first === undefined || previous === undefined) return 0;
  // Before the year's first new Moon the count runs on from the last of the
  // preceding year, which also shortens the last lunation of a nineteenth
  // year. Where an equation has moved the epacts between the two years it
  // is counted back from the new Moon instead.
  return epactContinues(input.year)
    ? position + (365 - previous) + 1
    : 30 - (first - position) + 1;
}

function continuousLunarDay(day: LocalDay): number {
  const elapsed = Math.round(
    (utc(day) - Date.UTC(2008, 0, 1)) / millisecondsPerDay,
  );
  const position = elapsed + 23;
  const lunarMonth = 29.53059;
  const multiple = Math.floor(position / lunarMonth);
  let distance = Math.floor(position - multiple * lunarMonth - 0.25);
  if (distance <= 0) distance += 30;
  return distance;
}

export const RomanMartyrologyCalendar = {
  latinProclamationToken: "{{hours:prime-martyrology-latin-proclamation}}",
  englishProclamationToken: "{{hours:prime-martyrology-english-proclamation}}",
  /**
   * The Moon and the year in words, as the approved exceptional readings
   * give them: "The sixteenth day of the Moon. In the year of our Lord 2026."
   */
  englishFormalProclamationToken:
    "{{hours:prime-martyrology-english-formal-proclamation}}",

  /**
   * The ecclesiastical age of the Moon proclaimed in the Martyrology: from
   * the epact table of 1900 through 2199 as reviewed, and in other years
   * from the Gregorian calendar of epacts, whose table changes with the
   * solar equation of 2200.
   */
  lunarDay(day: LocalDay): number {
    if (day.year >= 1900 && day.year < 2200) {
      return gregorianTableLunarDay(day);
    }
    const age = epactCalendarLunarDay(day);
    // The calendar of epacts has exceptions this does not model (a golden
    // number of 19 with the epact xix). None falls before 2300; an age it
    // cannot give is taken from the mean Moon instead.
    return age >= 1 && age <= 30 ? age : continuousLunarDay(day);
  },

  /** The age the calendar of epacts gives, in any year. */
  epactCalendarLunarDay,
  gregorianEpact,

  latinProclamation(day: LocalDay): string {
    const lunarDay = RomanMartyrologyCalendar.lunarDay(day);
    return `Luna ${latinLunarOrdinals[lunarDay - 1]} Anno Dómini ${day.year}`;
  },

  englishProclamation(day: LocalDay): string {
    const lunarDay = RomanMartyrologyCalendar.lunarDay(day);
    return (
      `${englishMonths[day.month - 1]} ${day.day}${ordinalSuffix(day.day)} ` +
      `${day.year}, the ${lunarDay}${ordinalSuffix(lunarDay)} day of the Moon,`
    );
  },

  englishFormalProclamation(day: LocalDay): string {
    const lunarDay = RomanMartyrologyCalendar.lunarDay(day);
    return (
      `The ${englishLunarOrdinals[lunarDay - 1]} day of the Moon. ` +
      `In the year of our Lord ${day.year}.`
    );
  },

  /** Whether a stored text leaves the Moon and the year to be named. */
  awaitsProclamation(text: string): boolean {
    return text.includes("{{hours:prime-martyrology-");
  },

  /**
   * A stored text naming the Moon and the year of `day`, as it is read at
   * Prime of the day before.
   */
  proclaiming(text: string, day: LocalDay): string {
    if (!RomanMartyrologyCalendar.awaitsProclamation(text)) return text;
    return text
      .replaceAll(
        RomanMartyrologyCalendar.latinProclamationToken,
        RomanMartyrologyCalendar.latinProclamation(day),
      )
      .replaceAll(
        RomanMartyrologyCalendar.englishProclamationToken,
        RomanMartyrologyCalendar.englishProclamation(day),
      )
      .replaceAll(
        RomanMartyrologyCalendar.englishFormalProclamationToken,
        RomanMartyrologyCalendar.englishFormalProclamation(day),
      );
  },

  /**
   * A stored text where no day is in view, as among the results of a search:
   * the Moon and the year are left unsaid, and a line that held nothing else
   * is omitted.
   */
  withoutProclamation(text: string): string {
    if (!RomanMartyrologyCalendar.awaitsProclamation(text)) return text;
    const lines: string[] = [];
    let omittedLine = false;
    for (const line of text.split("\n")) {
      // The blank line that set an omitted line apart goes with it.
      if (omittedLine && line === "") {
        omittedLine = false;
        continue;
      }
      omittedLine = false;
      if (!RomanMartyrologyCalendar.awaitsProclamation(line)) {
        lines.push(line);
        continue;
      }
      const rest = line
        .replaceAll(RomanMartyrologyCalendar.latinProclamationToken, "")
        .replaceAll(RomanMartyrologyCalendar.englishProclamationToken, "")
        .replaceAll(RomanMartyrologyCalendar.englishFormalProclamationToken, "")
        // `CharacterSet.whitespaces`: the space separators and the tab.
        .replace(/^[\p{Zs}\t]+|[\p{Zs}\t]+$/gu, "");
      if (/[\p{L}\p{N}]/u.test(rest)) {
        lines.push(rest);
      } else {
        omittedLine = true;
      }
    }
    return lines.join("\n");
  },

  /** Prime announces the following day; its stored text holds a token for the date. */
  materialize(office: OfficeDocument): OfficeDocument {
    if (office.hour !== "prime") return office;
    const followingDay = LocalDays.adding(office.date, 1);
    return {
      ...office,
      sections: office.sections.map((section) => ({
        ...section,
        latin: RomanMartyrologyCalendar.proclaiming(
          section.latin,
          followingDay,
        ),
        english:
          section.english == null
            ? section.english
            : RomanMartyrologyCalendar.proclaiming(
                section.english,
                followingDay,
              ),
      })),
    };
  },
};
