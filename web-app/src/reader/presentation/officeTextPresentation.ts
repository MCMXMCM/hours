import type { OfficeSection } from "@/core/models.ts";
import {
  characterCount,
  equalsIgnoringCase,
  escapedPattern,
  folding,
  hasPrefix,
  hasSuffix,
  icuDigit,
  trimmingWhitespace,
  trimmingWhitespaceAndNewlines,
} from "@/core/swiftString.ts";
import { makeOfficeSection } from "./officeSection.ts";
import {
  componentsSeparatedBy,
  contains,
  firstMatch,
  icuLineEnd,
  icuLineStart,
  icuWhitespace,
  replacingOccurrences,
  swiftDigit,
} from "./strings.ts";

const layLatinGreeting =
  "℣. Dómine, exáudi oratiónem meam.\n\n℟. Et clamor meus ad te véniat.";
const clericalLatinGreeting = "℣. Dóminus vobíscum.\n\n℟. Et cum spíritu tuo.";
const layEnglishGreeting =
  "℣. O Lord, hear my prayer.\n\n℟. And let my cry come unto thee.";
const clericalEnglishGreeting =
  "℣. The Lord be with you.\n\n℟. And with thy spirit.";

/**
 * The direction to omit the second lay greeting, as each edition prints
 * it.
 */
const omittedLatinGreetings = [
  "secunda Domine, exaudi omittitur",
  "secunda 'Domine, exaudi' omittitur",
];
const omittedEnglishGreetings = [
  "skip second O Lord, hear my prayer",
  "The second \u{2018}O Lord, hear my prayer\u{2019} is omitted.",
];
/**
 * The request for a blessing as one who recites the Office alone makes
 * it, of the Lord. A reader makes it of the priest who presides: Jube,
 * domne, benedícere. A rubric that quotes the words has no versicle
 * mark before them and is left as it is.
 */
const layLatinRequest = new RegExp(
  `(℣\\.[${icuWhitespace}]*[IJ]ube,?[${icuWhitespace}]+)Dómine(,?[${icuWhitespace}]+benedícere)`,
  "gu",
);
/** The lay greeting as a text may hold it, on lines or in paragraphs. */
const layLatinVersicle = `℣\\. Dómine, exáudi oratiónem meam\\.[${icuWhitespace}]+℟\\. Et clamor meus ad te véniat\\.`;
const layLatinVersicleAnywhere = new RegExp(layLatinVersicle, "u");
const layLatinVersicleAtTheEnd = new RegExp(`${layLatinVersicle}$`, "u");
const layGreetingWords = [
  "domine",
  "exaudi",
  "orationem",
  "meam",
  "et",
  "clamor",
  "meus",
  "ad",
  "te",
  "veniat",
];
const layRequestWords = ["iube", "domine", "benedicere"];

function adjusted(source: string, isPriestOrDeaconPresent: boolean): string {
  if (!isPriestOrDeaconPresent) return source;
  const text = source.replace(layLatinRequest, "$1domne$2");

  // The Office of the Dead retains Domine exaudi as a versicle;
  // clergy add their greeting where the second lay greeting is omitted.
  for (const direction of omittedLatinGreetings) {
    if (contains(text, direction)) {
      return replacingOccurrences(text, direction, clericalLatinGreeting);
    }
  }
  for (const direction of omittedEnglishGreetings) {
    if (contains(text, direction)) {
      return replacingOccurrences(text, direction, clericalEnglishGreeting);
    }
  }
  return replacingGreeting(
    replacingGreeting(text, layLatinGreeting, clericalLatinGreeting),
    layEnglishGreeting,
    clericalEnglishGreeting,
  );
}

/**
 * Older source packs store the required versicle and the omitted
 * second greeting separately. Keep that distinction when presenting
 * them, including while another tradition still uses its older pack.
 */
function groupingDeadOfficeGreeting(
  sections: readonly OfficeSection[],
): OfficeSection[] {
  const result: OfficeSection[] = [];
  for (const section of sections) {
    const previous = result.length > 0 ? result[result.length - 1] : null;
    if (
      trimmingWhitespaceAndNewlines(section.latin) ===
        "secunda Domine, exaudi omittitur" &&
      previous !== null &&
      contains(previous.latin, "Et clamor meus ad te véniat.")
    ) {
      // Where neither part is translated the greeting has no English.
      const english = [previous.english, section.english].filter(
        (value): value is string => value != null,
      );
      result.pop();
      result.push(
        makeOfficeSection({
          id: previous.id,
          kind: previous.kind,
          title: previous.title,
          titleEnglish: previous.titleEnglish,
          rubric: previous.rubric,
          rubricEnglish: previous.rubricEnglish,
          latin: previous.latin + "\n" + section.latin,
          english: english.length === 0 ? null : english.join("\n"),
          chant: null,
        }),
      );
    } else {
      result.push(section);
    }
  }
  return result;
}

function requiresTextFallback(
  latin: string,
  isPriestOrDeaconPresent: boolean,
): boolean {
  return adjusted(latin, isPriestOrDeaconPresent) !== latin;
}

/**
 * A section may print only its versicle mark where its words are sung,
 * as the Roman 1960 edition's greeting and request for a blessing do.
 * Such a section is given those words for its Latin, so that they give
 * place to what is said where a priest or deacon is present. The
 * versicle that stands before the direction to omit the second greeting
 * is said by all, and is left as it is.
 */
function writingOutSungLayForms(
  sections: readonly OfficeSection[],
): OfficeSection[] {
  return sections.map((section, index) => {
    if (
      section.chant == null ||
      !["V/", "V/.", "℣", "℣."].includes(
        trimmingWhitespaceAndNewlines(section.latin),
      )
    ) {
      return section;
    }
    const sung = sungText(section.chant.gabc);
    const words = sungWords(sung);
    let latin: string;
    if (sameWords(words, layGreetingWords)) {
      const following =
        index + 1 < sections.length
          ? trimmingWhitespaceAndNewlines(sections[index + 1].latin)
          : "";
      if (
        omittedLatinGreetings.some((direction) =>
          contains(following, direction),
        )
      ) {
        return section;
      }
      latin = layLatinGreeting;
    } else if (sameWords(words, layRequestWords)) {
      // The first letter is the edition's own, as it is sung.
      latin = contains(sung, "Iube")
        ? "℣. Iube, Dómine, benedícere."
        : "℣. Jube, Dómine, benedícere.";
    } else {
      return section;
    }
    return makeOfficeSection({
      id: section.id,
      kind: section.kind,
      title: section.title,
      titleEnglish: section.titleEnglish,
      rubric: section.rubric,
      rubricEnglish: section.rubricEnglish,
      latin,
      english: section.english,
      chant: section.chant,
    });
  });
}

/**
 * A text of a section, as it is said by those present: what all say is
 * left as it stands.
 */
function adjustedIn(
  text: string,
  section: OfficeSection,
  isPriestOrDeaconPresent: boolean,
): string {
  return section.isSaidByAll === true
    ? text
    : adjusted(text, isPriestOrDeaconPresent);
}

/** Whether a section's words are set as text in place of its score. */
function requiresTextFallbackFor(
  section: OfficeSection,
  isPriestOrDeaconPresent: boolean,
): boolean {
  return (
    section.isSaidByAll !== true &&
    requiresTextFallback(section.latin, isPriestOrDeaconPresent)
  );
}

/**
 * The lay greeting's words are also a versicle: the last of the ferial
 * preces, and in the Office of the Dead. There all say them, and the
 * direction that follows (the second greeting is omitted) is what a
 * priest's greeting replaces. A section that ends with those words and
 * stands before that direction is marked as said by all. (A section that
 * holds the direction with its own versicle needs no mark: the rule keeps
 * the one and replaces the other.)
 */
function markingWhatAllSay(
  sections: readonly OfficeSection[],
): OfficeSection[] {
  return sections.map((section, index) => {
    if (
      index + 1 >= sections.length ||
      !omittedLatinGreetings.some((direction) =>
        contains(sections[index + 1].latin, direction),
      ) ||
      layLatinVersicleAnywhere.test(sections[index + 1].latin) ||
      omittedLatinGreetings.some((direction) =>
        contains(section.latin, direction),
      )
    ) {
      return section;
    }
    const endsWithTheVersicle = layLatinVersicleAtTheEnd.test(
      trimmingWhitespaceAndNewlines(section.latin),
    );
    const singsTheVersicle =
      section.chant != null &&
      sameWords(sungWords(sungText(section.chant.gabc)), layGreetingWords);
    if (!endsWithTheVersicle && !singsTheVersicle) return section;
    return { ...section, isSaidByAll: true };
  });
}

/** The words of a score, without its notes, tags and header. */
function sungText(gabc: string): string {
  const parts = componentsSeparatedBy(gabc, "%%");
  const body = parts.slice(1).join("%%");
  return (body.length === 0 ? gabc : body)
    .replace(/\([^)]*\)/gu, "")
    .replace(/<[^>]+>/gu, "");
}

/**
 * Sung words without accents or case, a `j` read as `i`. The versicle
 * marks, being single letters, are no words.
 */
function sungWords(sung: string): string[] {
  return folding(sung, { caseInsensitive: true, diacriticInsensitive: true })
    .toLowerCase()
    .replaceAll("j", "i")
    .split(/[^\p{L}\p{M}]+/u)
    .filter((word) => characterCount(word) > 1);
}

function sameWords(left: readonly string[], right: readonly string[]): boolean {
  return (
    left.length === right.length &&
    left.every((word, index) => word === right[index])
  );
}

function replacingGreeting(
  text: string,
  greeting: string,
  replacement: string,
): string {
  const lines = componentsSeparatedBy(greeting, "\n\n");
  const pattern = lines.map(escapedPattern).join(`([${icuWhitespace}]+)`);
  const replacementLines = componentsSeparatedBy(replacement, "\n\n");
  // Preserve the source's line spacing, including single-newline imports.
  return text.replace(new RegExp(pattern, "gu"), replacementLines.join("$1"));
}

export const OfficePrayerText = {
  adjusted,
  adjustedIn,
  groupingDeadOfficeGreeting,
  markingWhatAllSay,
  requiresTextFallback,
  requiresTextFallbackFor,
  writingOutSungLayForms,
};

function distinctEnglish(
  english: string | null | undefined,
  latin: string,
): string | null {
  if (english == null) return null;
  const englishComparison = trimmingWhitespaceAndNewlines(english);
  if (englishComparison.length === 0) return null;
  const latinComparison = trimmingWhitespaceAndNewlines(latin);
  if (equalsIgnoringCase(englishComparison, latinComparison)) {
    return null;
  }
  return english;
}

export const OfficeBilingualText = {
  distinctEnglish,
};

// These are ICU patterns: Foundation replaces with NSRegularExpression.
const doxologyTrace = new RegExp(
  `[${icuWhitespace}]*\\{Doxology: (?:Special|Pasch|Corp|Epi|Nat|Asc|Pent|Heart)\\}`,
  "gu",
);
const laudsPsalterSelector = /\{Laudes:[12] /gu;
const sourceSelectionRubric =
  /\{((?:(?:Antiphon(?:a|æ|s)?|Psalmi|Psalms|ex|from) [^{}\n]+)|anticipatur|anticipated|Per Annum|Throughout the Year|paschale|for Easter time|habentur|included|specialis|special|per annum)\}/gu;
const psalmodyOrdinal = new RegExp(
  `${icuLineStart}((?:Psalmus|Psalm) [${icuDigit}]+(?:\\([0-9a-b,\\u{2013}\\-]+\\))?|(?:Canticum|Canticle) [^\\n\\[\\]]+) \\[[${icuDigit}]+\\]${icuLineEnd}`,
  "gu",
);

function text(source: string): string {
  let value = source;
  // These are source-engine trace labels; the selected doxology is
  // already written out in the hymn (specials/hymni.pl).
  value = value.replace(doxologyTrace, "");
  value = replacingOccurrences(value, "{default}", "");
  // Four witnessed typographical errors in English source readings.
  for (const annotation of [
    "Here ends St Bernard.",
    "Comm. on Matth. xxv.",
    "Bk. x, Chap. xvi, on Job xii.",
    "Here, if necessary, the Lesson is divided.",
  ]) {
    value = replacingOccurrences(
      value,
      "{" + annotation + ")",
      "(" + annotation + ")",
    );
  }
  // The braces mark source-selection rubrics, not spoken prayer text.
  // Keep their words; hide only the internal Lauds-psalter selector.
  value = value.replace(laudsPsalterSelector, "{");
  value = value.replace(sourceSelectionRubric, "($1)");
  // Bracketed ordinal numbers are the position within this hour's
  // psalmody, not verses or footnotes. Anchor to a complete heading.
  value = value.replace(psalmodyOrdinal, "$1");
  return trimmingWhitespaceAndNewlines(value);
}

// These are Swift Regex patterns: Foundation finds a range with the native
// engine, by Character and with `$` at the end of the string alone.
const versePattern = new RegExp(
  `^[${swiftDigit}]+:[${swiftDigit}]+[a-z]? `,
  "u",
);
const latinPsalmodyName = new RegExp(
  `^(?:Psalmus [${swiftDigit}]+|Canticum )`,
  "u",
);
const englishPsalmodyName = new RegExp(
  `^(?:Psalm [${swiftDigit}]+|Canticle )`,
  "u",
);
const bracedAnnotation = /^\{[^{}\n]+\}$/u;
const latinPsalmHeading = new RegExp(
  `^Psalmus [${swiftDigit}]+(?:\\([0-9a-b,\\u{2013}\\-]+\\))?$`,
  "u",
);
const englishPsalmHeading = new RegExp(
  `^Psalm [${swiftDigit}]+(?:\\([0-9a-b,\\u{2013}\\-]+\\))?$`,
  "u",
);

/**
 * Unscored psalmody in the source edition prints one verse per line,
 * under the psalm's name. The reader pairs Latin and English by verse
 * paragraph, so each verse becomes a paragraph and the name becomes the
 * heading — only where the two languages have the same lines, so that no
 * verse is ever paired with the wrong translation.
 */
function versedPsalmody(
  latin: string,
  english: string | null | undefined,
  title: string,
  titleEnglish: string | null | undefined,
): {
  latin: string;
  english: string | null;
  title: string;
  titleEnglish: string | null;
} | null {
  if (
    contains(latin, "\n\n") ||
    (english != null && contains(english, "\n\n"))
  ) {
    return null;
  }
  function lines(value: string): string[] {
    return componentsSeparatedBy(value, "\n").filter(
      (line) => trimmingWhitespace(line).length > 0,
    );
  }
  const latinLines = lines(latin);
  const englishLines = english == null ? null : lines(english);
  if (
    latinLines.filter((line) => firstMatch(versePattern, line) !== null)
      .length < 2
  ) {
    return null;
  }
  let heading = title;
  let headingEnglish = titleEnglish ?? null;
  if (
    heading.length === 0 &&
    latinLines.length > 0 &&
    firstMatch(latinPsalmodyName, latinLines[0]) !== null
  ) {
    heading = latinLines[0];
    latinLines.shift();
    if (
      englishLines !== null &&
      englishLines.length > 0 &&
      firstMatch(englishPsalmodyName, englishLines[0]) !== null
    ) {
      headingEnglish = englishLines[0];
      englishLines.shift();
    }
  }
  if (!(englishLines === null || englishLines.length === latinLines.length)) {
    return null;
  }
  return {
    latin: latinLines.join("\n\n"),
    english: englishLines === null ? null : englishLines.join("\n\n"),
    title: heading,
    titleEnglish: headingEnglish,
  };
}

function sections(source: readonly OfficeSection[]): OfficeSection[] {
  const displayed: OfficeSection[] = [];
  for (const section of source) {
    const latin = text(section.latin);
    const english =
      section.english != null
        ? text(section.english)
        : section.latin ===
            "Extra Chorum, quando ab uno tantum recitatur Officium dicitur: Jube, Dómine, benedícere; et subjungitur congruens Benedictio."
          ? "Outside choir, when the Office is recited by one person alone, Jube, Dómine, benedícere is said; the appropriate blessing follows."
          : null;
    // "Psalmi" is the source table's inherited part label, not the
    // title of each antiphon, psalm and doxology in that table.
    const isPsalmGroup = section.title === "Psalmi";
    const title = isPsalmGroup ? "" : text(section.title);
    const titleEnglish = isPsalmGroup
      ? null
      : section.titleEnglish != null
        ? text(section.titleEnglish)
        : null;
    if (!(
      latin.length > 0 ||
      (english ?? "").length > 0 ||
      title.length > 0 ||
      (titleEnglish ?? "").length > 0 ||
      section.chant != null
    )) {
      continue;
    }
    const annotationOnly =
      section.chant == null &&
      section.rubric == null &&
      hasPrefix(latin, "(") &&
      hasSuffix(latin, ")") &&
      firstMatch(
        bracedAnnotation,
        trimmingWhitespaceAndNewlines(section.latin),
      ) !== null;
    // Every standalone source rubric needs rubric typography, including
    // unbraced directions such as Gloria omittitur and Extra Chorum.
    const directionOnly =
      annotationOnly ||
      (section.kind === "rubric" &&
        section.chant == null &&
        section.rubric == null);
    const rubric = section.rubric != null ? text(section.rubric) : null;
    const rubricEnglish =
      section.rubricEnglish != null ? text(section.rubricEnglish) : null;
    if (section.chant == null && !directionOnly) {
      const psalmody = versedPsalmody(latin, english, title, titleEnglish);
      if (psalmody !== null) {
        displayed.push(
          makeOfficeSection({
            id: section.id,
            kind: "psalm",
            title: psalmody.title,
            titleEnglish: psalmody.titleEnglish,
            rubric,
            rubricEnglish,
            latin: psalmody.latin,
            english: psalmody.english,
          }),
        );
        continue;
      }
    }
    if (
      section.kind === "psalm" &&
      section.chant == null &&
      firstMatch(latinPsalmHeading, latin) !== null &&
      (english === null || firstMatch(englishPsalmHeading, english) !== null)
    ) {
      displayed.push(
        makeOfficeSection({
          id: section.id,
          kind: "psalm",
          title: latin,
          titleEnglish: english,
          rubric,
          rubricEnglish,
          latin: "",
          english: null,
        }),
      );
      continue;
    }
    displayed.push(
      makeOfficeSection({
        id: section.id,
        kind: directionOnly ? "rubric" : section.kind,
        title,
        titleEnglish,
        rubric: directionOnly ? latin : rubric,
        rubricEnglish: directionOnly ? english : rubricEnglish,
        latin: directionOnly ? "" : latin,
        english: directionOnly ? null : english,
        chant: section.chant,
      }),
    );
  }
  // Keep a standalone heading with its content. This also joins a
  // hymn's title to its score when a hidden doxology trace occupied
  // the source's first text block.
  const result: OfficeSection[] = [];
  for (const section of displayed) {
    const heading = result.length > 0 ? result[result.length - 1] : null;
    if (
      heading !== null &&
      heading.title.length > 0 &&
      heading.latin.length === 0 &&
      (heading.english == null || heading.english.length === 0) &&
      heading.chant == null &&
      heading.rubric == null &&
      heading.rubricEnglish == null &&
      section.kind === heading.kind &&
      section.title.length === 0
    ) {
      result.pop();
      result.push(
        makeOfficeSection({
          id: section.id,
          kind: section.kind,
          title: heading.title,
          titleEnglish: heading.titleEnglish,
          rubric: section.rubric,
          rubricEnglish: section.rubricEnglish,
          latin: section.latin,
          english: section.english,
          chant: section.chant,
        }),
      );
    } else {
      result.push(section);
    }
  }
  return result;
}

/**
 * Presentation of source-edition annotations, after the stored digest has been
 * checked. Prayer words, psalm divisions and all score/timeline data stay intact.
 */
export const SourceOfficeTextPresentation = {
  text,
  versedPsalmody,
  sections,
};
