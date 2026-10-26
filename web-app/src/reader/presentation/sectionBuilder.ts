import type {
  ChantScore,
  ChantTimeline,
  OfficeDocumentFormat,
  OfficeSection,
} from "@/core/models.ts";
import {
  GregorianScoreParser,
  GregorianScores,
  type GregorianLyricStyle,
  type GregorianNotationElement,
  type GregorianScore,
} from "@/core/notation";
import {
  characterCount,
  dropFirst,
  dropLast,
  equalsIgnoringCase,
  folding,
  hasPrefix,
  hasSuffix,
  icuDigit,
  isUppercase,
  isWhitespace,
  splitOmittingEmpty,
  trimmingWhitespaceAndNewlines,
} from "@/core/swiftString.ts";
import { makeOfficeSection } from "./officeSection.ts";
import {
  OfficePrayerText,
  SourceOfficeTextPresentation,
} from "./officeTextPresentation.ts";
import { PsalmTextFormatter } from "./psalmTextFormatter.ts";
import {
  componentsSeparatedBy,
  componentsSeparatedByNonAlphanumerics,
  contains,
  firstCharacter,
  firstMatch,
  icuEnd,
  icuWhitespace,
  lastCharacter,
  maxBy,
  minBy,
  rangeOf,
  replacingLiteralOccurrences,
  replacingOccurrences,
  swiftDigit,
  swiftInt,
  swiftWhitespace,
} from "./strings.ts";

/** The end of the identifier of the rest of a psalm that compact psalmody
 * sets after the verse sung from its score. */
const compactContinuationSuffix = "-compact-continuation";

/** The sections as the reader shows them. A Mass shows its Ordinary
 * unless `showsOrdinary` is false, when it shows the propers alone. Where
 * the chant is not shown (`showsScores`), the words its scores alone hold
 * are written out (writingOutSungWords). */
function displaySections(
  source: readonly OfficeSection[],
  format: OfficeDocumentFormat | null | undefined,
  usesCompactPsalmody = false,
  showsOrdinary = true,
  showsScores = true,
): OfficeSection[] {
  if (format === "missal") {
    // A Mass is set out by its compiler in the Missal's order and words;
    // none of the Office's arrangements applies to it.
    return showingCrossSigns(
      showsOrdinary
        ? source
        : source.filter((section) => section.ordinary !== true),
    );
  }
  const arranged = arrangedSections(
    source,
    format,
    usesCompactPsalmody && showsScores,
  );
  // Last of all, so that the words a chant alone holds are read by
  // nothing that arranges the sections, and a mark is lost in no
  // rearrangement.
  const sections = settingEnglishOfSungParts(
    OfficePrayerText.markingWhatAllSay(
      OfficePrayerText.writingOutSungLayForms(arranged),
    ),
  );
  return showsScores ? sections : writingOutSungWords(sections);
}

function arrangedSections(
  source: readonly OfficeSection[],
  format: OfficeDocumentFormat | null | undefined,
  usesCompactPsalmody: boolean,
): OfficeSection[] {
  if (format === "sourceOrdered") {
    // Source imports are already in liturgical order. Never run the
    // Roman reconstruction/correction heuristics over a source-ordered office:
    // its antiphons, including those repeated between the strophes of a
    // psalm, are printed in both languages and none is spurious.
    const sourceSections = suppressingRepeatedHeadings(
      SourceOfficeTextPresentation.sections(
        OfficePrayerText.groupingDeadOfficeGreeting(source),
      ),
    );
    return showingDirectionsAsRubrics(
      showingCrossSigns(
        usesCompactPsalmody
          ? compactingPsalmody(sourceSections, true)
          : sourceSections,
      ),
    );
  }
  const presentationSource =
    format === "authoritativeOrdered" ? correctedSource(source, true) : source;
  const correctedSections = withCorrectedHeadings(
    withoutPrintedHeadings(
      correctingNumberedLessonTranslations(presentationSource),
    ),
  );
  let displayed: OfficeSection[];
  if (format === "authoritativeOrdered") {
    // The authoritative corpus repeats a part's title on each atomic
    // prayer or score across every hour. Preserve its order, fold
    // prose that is actually covered by a score into that score, and
    // present one heading for the whole office part.
    displayed = suppressingRepeatedHeadings(
      interleavingTextWithNonPsalmChants(correctedSections, false),
    );
  } else {
    displayed = sections(correctedSections);
  }
  const restored = restoringPsalmodyEnglish(displayed);
  if (!usesCompactPsalmody) {
    return showingDirectionsAsRubrics(showingCrossSigns(restored));
  }
  return showingDirectionsAsRubrics(
    showingCrossSigns(compactingPsalmody(restored)),
  );
}

// An ICU pattern: Foundation replaces with NSRegularExpression.
const psalmDivisionCounter = new RegExp(
  `[${icuWhitespace}]*\\[[${icuDigit}]+\\]${icuEnd}`,
  "gu",
);

/**
 * The ordered corpus repeats a part's heading, with its source note, as
 * the first line of the part's text ("Oratio {ex Proprio Sanctorum}").
 * The heading and the note are shown already, so that line is omitted; a
 * psalm-division counter ("Canticum Isaiæ [4]") is not part of a heading.
 */
function withoutPrintedHeadings(
  sections: readonly OfficeSection[],
): OfficeSection[] {
  function withoutHeading(
    value: string | null | undefined,
    heading: string | null | undefined,
    note: string | null | undefined,
  ): string | null {
    if (value == null) return null;
    if (heading == null || heading.length === 0) return value;
    const parts = componentsSeparatedBy(value, "\n\n");
    const first = trimmingWhitespaceAndNewlines(parts[0]);
    const printed = [heading].concat(
      note != null ? [`${heading} {${note}}`, `${heading} (${note})`] : [],
    );
    if (!printed.includes(first)) return value;
    parts.shift();
    return parts.join("\n\n");
  }
  return sections.map((section) => {
    const title = section.title.replace(psalmDivisionCounter, "");
    const latin =
      withoutHeading(section.latin, section.title, section.rubric) ??
      section.latin;
    const english = withoutHeading(
      section.english,
      section.titleEnglish,
      section.rubricEnglish,
    );
    if (!(
      title !== section.title ||
      latin !== section.latin ||
      english !== (section.english ?? null)
    )) {
      return section;
    }
    // An unchanged title is not replaced: replacing an empty one
    // would remove its translation with it.
    return replacingPresentation(section, {
      title: title === section.title ? undefined : title,
      latin,
      english,
    });
  });
}

// Swift Regex patterns: Foundation finds a range with the native engine.
const numberedSectionTitle = new RegExp(`^Section [${swiftDigit}]+$`, "u");

/**
 * Headings the source supplies mechanically: a numbered "Section" where it
 * has none, "Capitulum Responsorium Versus" over a chapter that no short
 * responsory follows (Lauds and Vespers, where the hymn comes next), and
 * "Start" as the English of a short lesson or an opening.
 */
function withCorrectedHeadings(
  sections: readonly OfficeSection[],
): OfficeSection[] {
  // The chapter, its short responsory and versicle are consecutive parts
  // under one heading; a run without the responsory's versicle is a
  // chapter alone.
  const combined = "Capitulum Responsorium Versus";
  const chapterOnly = new Set<number>();
  let start = 0;
  while (start < sections.length) {
    if (sections[start].title !== combined) {
      start += 1;
      continue;
    }
    let end = start;
    while (end < sections.length && sections[end].title === combined) {
      end += 1;
    }
    const hasVersicle = sections
      .slice(start, end)
      .some(
        (section) =>
          hasPrefix(trimmingWhitespaceAndNewlines(section.latin), "V/") ||
          contains(section.latin, "℣."),
      );
    if (!hasVersicle) {
      for (let index = start; index < end; index += 1) chapterOnly.add(index);
    }
    start = end;
  }
  return sections.map((section, index) => {
    if (firstMatch(numberedSectionTitle, section.title) !== null) {
      return replacingPresentation(section, { title: "", titleEnglish: null });
    }
    if (chapterOnly.has(index)) {
      return replacingPresentation(section, {
        title: "Capitulum",
        titleEnglish: "Chapter",
      });
    }
    if (section.titleEnglish === "Start") {
      switch (section.title) {
        case "Lectio brevis":
          return replacingPresentation(section, {
            titleEnglish: "Short reading",
          });
        case "Incipit":
          return replacingPresentation(section, { titleEnglish: "Beginning" });
        default:
          break;
      }
    }
    return section;
  });
}

// Matched without regard to case, so the pattern is in lowercase.
const direction =
  /^(?:secreto|flexis genibus|sequens stropha dicitur flexis genibus\.|et recto tono dicitur benedictio:|deinde dicitur secreto|deinde dicitur tantum pater noster secreto, nisi sequatur alia hora\.)$/u;

/**
 * Directions printed in the source as a part of their own ("secreto",
 * "Sequens stropha dicitur flexis genibus.") govern the part that follows,
 * so they are shown as its rubric rather than as words to be said.
 */
function showingDirectionsAsRubrics(
  sections: readonly OfficeSection[],
): OfficeSection[] {
  const result: OfficeSection[] = [];
  let pending: OfficeSection | null = null;
  for (const section of sections) {
    if (pending !== null) {
      const held: OfficeSection = pending;
      pending = null;
      if (section.rubric == null) {
        const inheritsHeading =
          section.title.length === 0 && held.title.length > 0;
        result.push(
          replacingPresentation(section, {
            title: inheritsHeading ? held.title : undefined,
            titleEnglish: inheritsHeading
              ? (held.titleEnglish ?? null)
              : undefined,
            rubric: trimmingWhitespaceAndNewlines(held.latin),
            rubricEnglish:
              held.english != null
                ? trimmingWhitespaceAndNewlines(held.english)
                : null,
          }),
        );
        continue;
      }
      result.push(held);
    }
    if (
      section.chant == null &&
      section.kind !== "rubric" &&
      firstMatch(
        direction,
        trimmingWhitespaceAndNewlines(section.latin),
        true,
      ) !== null
    ) {
      pending = section;
    } else {
      result.push(section);
    }
  }
  if (pending !== null) result.push(pending);
  return result;
}

/**
 * Some sources print the sign of the cross as a plus sign held in text
 * presentation ("lábia \u{FE0E}+\u{FE0E} mea"); show it as the cross it stands for.
 */
function showingCrossSigns(
  sections: readonly OfficeSection[],
): OfficeSection[] {
  const plus = "\u{FE0E}+\u{FE0E}";
  function crossed(value: string): string {
    return replacingLiteralOccurrences(value, plus, "✠");
  }
  return sections.map((section) => {
    const latin = crossed(section.latin);
    const english = section.english != null ? crossed(section.english) : null;
    if (!(latin !== section.latin || english !== (section.english ?? null))) {
      return section;
    }
    return replacingPresentation(section, { latin, english });
  });
}

function restoringPsalmodyEnglish(
  source: readonly OfficeSection[],
): OfficeSection[] {
  return source.map((section) => {
    if (!(
      (section.kind === "psalm" || section.kind === "canticle") &&
      section.english != null
    )) {
      return section;
    }
    const english = section.english;
    const restored = removingEmbeddedAntiphonParagraphs(english);
    if (restored === english) return section;
    return replacingPresentation(section, { english: restored });
  });
}

function removingEmbeddedAntiphonParagraphs(english: string): string {
  const values = paragraphs(english);
  if (!(values.length > 2)) return english;
  const retained: string[] = [];
  values.forEach((paragraph, index) => {
    if (
      isAntiphonParagraph(paragraph) &&
      index > 0 &&
      index < values.length - 1
    ) {
      const previous = scriptureReference(values[index - 1]);
      const next = scriptureReference(values[index + 1]);
      if (
        previous !== null &&
        next !== null &&
        previous.psalm === next.psalm &&
        next.verse === previous.verse + 1
      ) {
        return;
      }
    }
    retained.push(paragraph);
  });
  return sameElements(retained, values) ? english : retained.join("\n\n");
}

function correctingNumberedLessonTranslations(
  source: readonly OfficeSection[],
): OfficeSection[] {
  return source.map((section) => {
    const latinParts = splitOmittingEmpty(
      trimmingWhitespaceAndNewlines(section.latin),
      isWhitespace,
    );
    if (!(
      latinParts.length === 2 && equalsIgnoringCase(latinParts[0], "Lectio")
    )) {
      return section;
    }
    const ordinal = swiftInt(latinParts[1]);
    if (!(ordinal !== null && ordinal > 0)) {
      return section;
    }

    function corrected(value: string | null | undefined): string | null {
      if (value == null) return null;
      const parts = splitOmittingEmpty(
        trimmingWhitespaceAndNewlines(value),
        isWhitespace,
      );
      if (!(
        parts.length === 2 &&
        equalsIgnoringCase(parts[0], "Reading") &&
        swiftInt(parts[1]) !== null
      )) {
        return value;
      }
      return `Reading ${ordinal}`;
    }

    return makeOfficeSection({
      id: section.id,
      kind: section.kind,
      title: section.title,
      titleEnglish: corrected(section.titleEnglish),
      rubric: section.rubric,
      rubricEnglish: section.rubricEnglish,
      latin: section.latin,
      english: corrected(section.english),
      chant: section.chant,
    });
  });
}

function sections(source: readonly OfficeSection[]): OfficeSection[] {
  const interleaved = interleavingTextWithNonPsalmChants(
    interleavingCompactPsalmody(correctedSource(source)),
  );
  return suppressingRepeatedHeadings(interleaved);
}

function compactingPsalmody(
  sections: readonly OfficeSection[],
  usesSourceLineBreaks = false,
): OfficeSection[] {
  return sections.flatMap(
    (section) =>
      compactPsalmodySection(section, usesSourceLineBreaks) ?? [section],
  );
}

function compactPsalmodySection(
  section: OfficeSection,
  usesSourceLineBreaks: boolean,
): OfficeSection[] | null {
  if (!(section.kind === "psalm" || section.kind === "canticle")) return null;
  const score = section.chant;
  if (score == null) return null;
  const parsed = parsingScore(score.gabc, score.timeline);
  if (parsed === null) {
    return null;
  }

  const verseElements = scoredVerseElements(parsed);
  if (!(verseElements.length > 1)) return null;
  const compactGABC = firstVerseGABC(score.gabc);
  if (compactGABC === null) {
    return null;
  }
  const rawPointedVerseTexts = verseElements.map((elements) =>
    trimmingWhitespaceAndNewlines(pointedLyricText(elements)),
  );
  const pointedVerseTexts =
    normalizingTrailingVerseOrdinals(rawPointedVerseTexts);
  const verseTexts = pointedVerseTexts.map((verse) =>
    PsalmTextFormatter.removingEmphasisMarkers(verse),
  );
  if (!verseTexts.every((verse) => verse.length > 0)) return null;

  let englishAlignment: PsalmodyEnglishAlignment | null;
  if (section.english != null) {
    const english = section.english;
    const alignment = aligningPsalmodyEnglish(
      usesSourceLineBreaks
        ? componentsSeparatedBy(english, "\n")
            .map(trimmingWhitespaceAndNewlines)
            .filter((line) => line.length > 0)
        : paragraphs(english),
      verseTexts,
    );
    if (alignment === null) {
      // Preserve the complete bilingual section when alignment is
      // uncertain; compacting must never discard its translation.
      return null;
    }
    englishAlignment = alignment;
  } else {
    englishAlignment = null;
  }

  const firstVerse = GregorianScores.make(verseElements[0]);
  const firstVerseEventIDs = GregorianScores.eventIDs(firstVerse);
  const firstEventIDs = new Set(firstVerseEventIDs);
  const firstEvents = score.timeline.events.filter((event) =>
    firstEventIDs.has(event.id),
  );
  if (
    !sameElements(
      firstEvents.map((event) => event.id),
      firstVerseEventIDs,
    )
  ) {
    return null;
  }
  const compactTimeline: ChantTimeline = { events: firstEvents };
  const validatedCompactScore = parsingScore(compactGABC, compactTimeline);
  if (!(
    validatedCompactScore !== null &&
    sameElements(
      GregorianScores.eventIDs(validatedCompactScore),
      firstVerseEventIDs,
    )
  )) {
    return null;
  }

  const firstLatin = PsalmTextFormatter.strippingVersePrefix(verseTexts[0]);
  const compactScore: ChantScore = {
    id: `${score.id}-compact-${section.id}`,
    incipit: firstLatin,
    gabc: compactGABC,
    mode: score.mode ?? null,
    reviewStatus: score.reviewStatus,
    provenance: score.provenance,
    timeline: compactTimeline,
  };
  const firstEnglish =
    englishAlignment !== null ? englishAlignment.verses[0] : null;
  const firstSection = makeOfficeSection({
    id: section.id,
    kind: section.kind,
    title: section.title,
    titleEnglish: section.titleEnglish,
    rubric: section.rubric,
    rubricEnglish: section.rubricEnglish,
    latin: firstLatin,
    english:
      firstEnglish !== null
        ? PsalmTextFormatter.strippingVersePrefix(firstEnglish)
        : null,
    chant: compactScore,
  });
  const continuation = makeOfficeSection({
    id: section.id + compactContinuationSuffix,
    kind: section.kind,
    title: "",
    latin: pointedVerseTexts.slice(1).join("\n\n"),
    english:
      englishAlignment !== null
        ? serializedPsalmodyEnglish(
            englishAlignment.verses.slice(1),
            englishAlignment.trailing,
          )
        : null,
  });
  return [firstSection, continuation];
}

/** Swift's `try? GregorianScoreParser.parse(gabc:timeline:)`. */
function parsingScore(
  gabc: string,
  timeline: ChantTimeline,
): GregorianScore | null {
  try {
    return GregorianScoreParser.parse(gabc, timeline);
  } catch {
    return null;
  }
}

interface PsalmodyEnglishAlignment {
  readonly verses: readonly (string | null)[];
  readonly trailing: readonly string[];
}

function aligningPsalmodyEnglish(
  english: readonly string[],
  latin: readonly string[],
): PsalmodyEnglishAlignment | null {
  if (latin.length === 0) return null;
  if (english.length === latin.length) {
    return {
      verses: english.slice(),
      trailing: [],
    };
  }

  let latinDoxologyCount = 0;
  while (
    latinDoxologyCount < latin.length &&
    isDoxologyParagraph(latin[latin.length - 1 - latinDoxologyCount])
  ) {
    latinDoxologyCount += 1;
  }
  if (!(latinDoxologyCount > 0)) return null;

  const latinPsalmCount = latin.length - latinDoxologyCount;
  let trailingCount = 0;
  while (
    trailingCount < english.length &&
    isSafePsalmodyPostlude(english[english.length - 1 - trailingCount])
  ) {
    trailingCount += 1;
  }
  const doxologyEnd = english.length - trailingCount;
  if (!(doxologyEnd >= latinDoxologyCount)) return null;
  const doxologyStart = doxologyEnd - latinDoxologyCount;
  const psalmEnglish = english.slice(0, doxologyStart);
  const doxologyEnglish = english.slice(doxologyStart, doxologyEnd);
  const trailing = trailingCount > 0 ? english.slice(-trailingCount) : [];
  if (!doxologyEnglish.every(isDoxologyParagraph)) {
    return null;
  }
  const filteredPsalmEnglish = psalmEnglish.filter(
    (paragraph) => !isSafePsalmodyInterlude(paragraph),
  );
  const alignedPsalmEnglish =
    aligningNumberedPsalmodyEnglish(psalmEnglish, latinPsalmCount) ??
    aligningNumberedPsalmodyEnglish(filteredPsalmEnglish, latinPsalmCount);
  if (alignedPsalmEnglish === null) {
    return null;
  }

  return {
    verses: alignedPsalmEnglish.concat(doxologyEnglish),
    trailing,
  };
}

function aligningNumberedPsalmodyEnglish(
  english: readonly string[],
  count: number,
): (string | null)[] | null {
  // Biblical verse gaps do not locate missing chant lines. If the
  // paragraph count cannot be verified, retain the full bilingual score.
  if (english.length !== count) return null;
  return english.slice();
}

function serializedPsalmodyEnglish(
  verses: readonly (string | null)[],
  trailing: readonly string[],
): string {
  const paragraphs = verses.map(
    (verse) => verse ?? PsalmTextFormatter.missingTranslationPlaceholder,
  );
  if (trailing.length > 0 && paragraphs.length > 0) {
    paragraphs[paragraphs.length - 1] += "\n" + trailing.join("\n");
  }
  return paragraphs.join("\n\n");
}

function isDoxologyParagraph(paragraph: string): boolean {
  const value = folding(PsalmTextFormatter.strippingVersePrefix(paragraph), {
    caseInsensitive: true,
    diacriticInsensitive: true,
  });
  return (
    hasPrefix(value, "gloria patri") ||
    hasPrefix(value, "sicut erat") ||
    hasPrefix(value, "glory be to the father") ||
    hasPrefix(value, "as it was in the beginning")
  );
}

function isSafePsalmodyPostlude(paragraph: string): boolean {
  const value = trimmingWhitespaceAndNewlines(paragraph);
  return (
    hasPrefix(value, "℟.") ||
    hasPrefix(value, "℣.") ||
    equalsIgnoringCase(value, "Amen.")
  );
}

function isSafePsalmodyInterlude(paragraph: string): boolean {
  const value = trimmingWhitespaceAndNewlines(paragraph).toLowerCase();
  return (
    value === "ant." ||
    hasPrefix(value, "ant. ") ||
    hasPrefix(value, "℟.br. ") ||
    hasPrefix(value, "℣.br. ")
  );
}

function scoredVerseElements(
  score: GregorianScore,
): GregorianNotationElement[][] {
  const verses: GregorianNotationElement[][] = [];
  let current: GregorianNotationElement[] = [];

  for (const element of score.elements) {
    current.push(element);
    if (element.type === "division" && element.division === "final") {
      if (GregorianScores.lyricText(GregorianScores.make(current)).length > 0) {
        verses.push(current);
      }
      current = [];
    }
  }
  if (GregorianScores.lyricText(GregorianScores.make(current)).length > 0) {
    verses.push(current);
  }
  return verses;
}

function pointedLyricText(
  elements: readonly GregorianNotationElement[],
): string {
  let result = "";
  let separatesFollowingLyric = false;

  function append(
    text: string,
    style: GregorianLyricStyle,
    startsWord: boolean,
    isLyricMark: boolean,
  ): void {
    if (text.length === 0) return;
    const last = lastCharacter(result);
    if (
      result.length > 0 &&
      (startsWord || separatesFollowingLyric) &&
      !(last !== null && isWhitespace(last))
    ) {
      result += " ";
    }
    if (style === "accented") {
      result += PsalmTextFormatter.emphasisStartMarker;
    }
    result += text;
    if (style === "accented") {
      result += PsalmTextFormatter.emphasisEndMarker;
    }
    separatesFollowingLyric = isLyricMark;
  }

  for (const element of elements) {
    switch (element.type) {
      case "neume":
        append(
          element.neume.lyric,
          element.neume.lyricStyle,
          element.neume.startsWord,
          false,
        );
        break;
      case "lyricMark":
        append(
          element.lyricMark.text,
          element.lyricMark.style,
          element.lyricMark.startsWord,
          true,
        );
        break;
      case "clef":
      case "accidental":
      case "division":
      case "forcedBreak":
        continue;
      default:
        continue;
    }
  }
  return result;
}

// Swift Regex patterns: Foundation finds a range with the native engine.
const finalDivision = new RegExp(
  `\\([${swiftWhitespace}]*::[${swiftWhitespace}]*\\)`,
  "u",
);
const trailingSecondOrdinal = new RegExp(
  `[${swiftWhitespace}]+2\\.[${swiftWhitespace}]*(?=\\([${swiftWhitespace}]*::[${swiftWhitespace}]*\\)[${swiftWhitespace}]*$)`,
  "u",
);

function firstVerseGABC(gabc: string): string | null {
  const bodyMarker = rangeOf(gabc, "%%");
  if (bodyMarker === null) return null;
  const body = gabc.slice(bodyMarker.upperBound);
  const verseEnd = firstMatch(finalDivision, body);
  if (verseEnd === null) {
    return null;
  }
  let firstVerse = gabc.slice(0, bodyMarker.upperBound + verseEnd.upperBound);
  const trailingNextOrdinal = firstMatch(trailingSecondOrdinal, firstVerse);
  if (trailingNextOrdinal !== null) {
    firstVerse =
      firstVerse.slice(0, trailingNextOrdinal.lowerBound) +
      firstVerse.slice(trailingNextOrdinal.upperBound);
  }
  return firstVerse;
}

function normalizingTrailingVerseOrdinals(verses: readonly string[]): string[] {
  if (!(verses.length > 1)) return verses.slice();
  const result = verses.slice();

  for (let index = 0; index < result.length - 1; index += 1) {
    const words = splitOmittingEmpty(result[index], isWhitespace);
    if (words.length === 0) continue;
    const last = words[words.length - 1];
    if (!(hasSuffix(last, ".") && swiftInt(dropLast(last)) === index + 2)) {
      continue;
    }
    result[index] = words.slice(0, -1).join(" ");
    const ordinal = `${index + 2}.`;
    if (!hasPrefix(result[index + 1], `${ordinal} `)) {
      result[index + 1] = `${ordinal} ${result[index + 1]}`;
    }
  }
  return result;
}

function interleavingTextWithNonPsalmChants(
  source: readonly OfficeSection[],
  allowsTitleFallback = true,
): OfficeSection[] {
  // A heading names an office part; it does not prove that every prayer
  // under that heading is present in a score. Associate chants by Latin
  // content and remove only paragraphs that the GABC actually covers.
  const textIndices: number[] = [];
  for (let index = 0; index < source.length; index += 1) {
    if (source[index].chant == null && source[index].kind !== "psalm") {
      textIndices.push(index);
    }
  }
  const chantIndicesByTextIndex = new Map<number, number[]>();

  for (let chantIndex = 0; chantIndex < source.length; chantIndex += 1) {
    if (!(
      source[chantIndex].chant != null && source[chantIndex].kind !== "psalm"
    )) {
      continue;
    }
    const chant = source[chantIndex];
    const contentMatch = bestTextIndex(chant, chantIndex, source, textIndices);
    const title = normalizedTitle(chant.title);
    const titleMatch = minBy(
      textIndices.filter(
        (index) =>
          normalizedTitle(source[index].title) === title && title.length > 0,
      ),
      (lhs, rhs) => Math.abs(lhs - chantIndex) < Math.abs(rhs - chantIndex),
    );

    const textIndex = contentMatch ?? (allowsTitleFallback ? titleMatch : null);
    if (textIndex !== null) {
      const chantIndices = chantIndicesByTextIndex.get(textIndex);
      if (chantIndices === undefined) {
        chantIndicesByTextIndex.set(textIndex, [chantIndex]);
      } else {
        chantIndices.push(chantIndex);
      }
    }
  }

  if (!allowsTitleFallback) {
    // An ordered office already places every score. Fold a score into
    // a text only where it replaces paragraphs which that text prints,
    // with no other prayer between them, and give each paragraph to
    // its nearest score. Otherwise a versicle repeating the opening of
    // a chapter, an antiphon quoted in a lesson, or the Tu autem of
    // one lesson would be moved to another place in the Hour.
    for (const [textIndex, chantIndices] of Array.from(
      chantIndicesByTextIndex,
    )) {
      const textParagraphs = paragraphs(source[textIndex].latin);
      // Some imported offices print a conclusion again after the
      // blessing. Such a text only repeats what the scores sing, so
      // it may be folded into them wherever it stands.
      const repeatsScores = textOnlyRepeats(
        source[textIndex],
        chantIndices.map((index) => source[index]),
      );
      const claimed = new Set<number>();
      const claimedWords = new Set<string>();
      const retained = chantIndices
        .slice()
        .sort(
          (lhs, rhs) => Math.abs(lhs - textIndex) - Math.abs(rhs - textIndex),
        )
        .filter((chantIndex) => {
          if (!(
            repeatsScores || !isSeparatedByPrayer(chantIndex, textIndex, source)
          )) {
            return false;
          }
          const covered: number[] = [];
          for (let index = 0; index < textParagraphs.length; index += 1) {
            if (
              !claimed.has(index) &&
              scoreCoversParagraph(source[chantIndex], textParagraphs[index])
            ) {
              covered.push(index);
            }
          }
          // A repeated antiphon may print the same words twice;
          // each occurrence remains available to its own score.
          let newlyClaimed = false;
          for (const paragraph of covered) {
            const words = wordsKey(
              normalizedLatinWords(textParagraphs[paragraph]),
            );
            if (claimedWords.has(words)) continue;
            claimedWords.add(words);
            claimed.add(paragraph);
            newlyClaimed = true;
          }
          return newlyClaimed;
        });
      if (retained.length === 0) {
        chantIndicesByTextIndex.delete(textIndex);
      } else {
        chantIndicesByTextIndex.set(textIndex, sortedAscending(retained));
      }
    }
  }

  const groupsByAnchor = new Map<
    number,
    { readonly textIndex: number; readonly chantIndices: readonly number[] }
  >();
  const groupedIndices = new Set<number>();
  for (const [textIndex, chantIndices] of chantIndicesByTextIndex) {
    const anchor = Math.min(textIndex, ...chantIndices);
    groupsByAnchor.set(anchor, {
      textIndex,
      chantIndices: sortedAscending(chantIndices),
    });
    groupedIndices.add(textIndex);
    for (const chantIndex of chantIndices) groupedIndices.add(chantIndex);
  }

  const result: OfficeSection[] = [];
  for (let index = 0; index < source.length; index += 1) {
    const group = groupsByAnchor.get(index);
    if (group !== undefined) {
      result.push(
        ...presentationSections(
          source[group.textIndex],
          group.chantIndices.map((chantIndex) => source[chantIndex]),
        ),
      );
    } else if (!groupedIndices.has(index)) {
      result.push(source[index]);
    }
  }
  return result;
}

/**
 * Whether a text opens with words the score sings, as Compline's
 * Deus in adiutórium does after the confession. A Glória Patri at the end
 * of a canticle does not make the opening score belong there.
 */
function textOpensWith(text: OfficeSection, chant: OfficeSection): boolean {
  const heading = normalizedTitle(text.title);
  const first = paragraphs(text.latin).find(
    (paragraph) => normalizedTitle(paragraph) !== heading,
  );
  if (first === undefined) return false;
  return scoreCoversParagraph(chant, first);
}

/**
 * Whether every paragraph of a text is sung by these scores, and every
 * score is contained in the text: the text then adds nothing to them.
 */
function textOnlyRepeats(
  text: OfficeSection,
  chants: readonly OfficeSection[],
): boolean {
  const heading = normalizedTitle(text.title);
  const textParagraphs = paragraphs(text.latin).filter(
    (paragraph) => normalizedTitle(paragraph) !== heading,
  );
  const textWords = normalizedLatinWords(text.latin);
  if (!(textParagraphs.length > 0 && chants.length > 0)) return false;
  return (
    textParagraphs.every((paragraph) =>
      chants.some((chant) => scoreCoversParagraph(chant, paragraph)),
    ) &&
    chants.every((chant) => {
      const words = scoredWords(chant);
      return (
        words.length > 0 &&
        longestSharedRun(words, textWords) * 10 >= words.length * 7
      );
    })
  );
}

/**
 * Whether another printed prayer stands between a score and a text.
 * Rubrics and other scores do not separate them.
 */
function isSeparatedByPrayer(
  chantIndex: number,
  textIndex: number,
  source: readonly OfficeSection[],
): boolean {
  const lower = Math.min(chantIndex, textIndex) + 1;
  const upper = Math.max(chantIndex, textIndex);
  if (!(lower < upper)) return false;
  return source
    .slice(lower, upper)
    .some(
      (section) =>
        section.chant == null &&
        section.kind !== "rubric" &&
        trimmingWhitespaceAndNewlines(section.latin).length > 0,
    );
}

function bestTextIndex(
  chant: OfficeSection,
  chantIndex: number,
  source: readonly OfficeSection[],
  candidates: readonly number[],
): number | null {
  const scoreWords = scoredWords(chant);
  if (!(scoreWords.length >= 4)) return null;

  const matches: { readonly index: number; readonly run: number }[] = [];
  for (const index of candidates) {
    const run = substantialSharedRun(
      scoreWords,
      normalizedLatinWords(source[index].latin),
    );
    if (run !== null) matches.push({ index, run });
  }
  const best = maxBy(matches, (lhs, rhs) => {
    if (lhs.run === rhs.run) {
      return (
        Math.abs(lhs.index - chantIndex) > Math.abs(rhs.index - chantIndex)
      );
    }
    return lhs.run < rhs.run;
  });
  return best === null ? null : best.index;
}

// A Swift Regex pattern: Foundation finds a range with the native engine.
const numberedSectionHeading = /^section [0-9]+$/u;

function presentationSections(
  text: OfficeSection,
  chants: readonly OfficeSection[],
): OfficeSection[] {
  const latinParagraphs = paragraphs(text.latin);
  const englishParagraphs =
    text.english != null ? paragraphs(text.english) : null;
  const translationsAlign =
    englishParagraphs !== null &&
    englishParagraphs.length === latinParagraphs.length;
  const textTitle = normalizedTitle(text.title);
  const presentationTitle =
    firstMatch(numberedSectionHeading, textTitle) !== null
      ? (chants
          .map((chant) => chant.title)
          .find((title) => normalizedTitle(title).length > 0) ?? text.title)
      : text.title;
  const headingIndices = new Set<number>();
  for (let index = 0; index < latinParagraphs.length; index += 1) {
    const paragraph = normalizedTitle(latinParagraphs[index]);
    if (
      paragraph === textTitle ||
      paragraph === normalizedTitle(presentationTitle)
    ) {
      headingIndices.add(index);
    }
  }
  const coveredIndices = new Set(headingIndices);
  const chantsByParagraph = new Map<number, OfficeSection[]>();
  const matchedParagraphs = chants.map((chant) => {
    const matches: number[] = [];
    for (let index = 0; index < latinParagraphs.length; index += 1) {
      if (
        !headingIndices.has(index) &&
        scoreCoversParagraph(chant, latinParagraphs[index])
      ) {
        matches.push(index);
      }
    }
    return matches;
  });
  const chantsCoveringText = new Set<string>();
  chants.forEach((chant, chantIndex) => {
    if (matchedParagraphs[chantIndex].length > 0) {
      chantsCoveringText.add(chant.id);
    }
  });

  chants.forEach((chant, chantIndex) => {
    const matches = matchedParagraphs[chantIndex];
    if (matches.length > 0) {
      for (const match of matches) coveredIndices.add(match);
    }
    let previousAnchor: number | null = null;
    for (let index = chantIndex - 1; index >= 0; index -= 1) {
      const earlier = matchedParagraphs[index];
      if (earlier.length > 0) {
        previousAnchor = earlier[earlier.length - 1];
        break;
      }
    }
    let nextAnchor: number | null = null;
    for (
      let index = chantIndex + 1;
      index < matchedParagraphs.length;
      index += 1
    ) {
      const later = matchedParagraphs[index];
      if (later.length > 0) {
        nextAnchor = later[0];
        break;
      }
    }
    let firstParagraphOutsideHeading: number | null = null;
    for (let index = 0; index < latinParagraphs.length; index += 1) {
      if (!headingIndices.has(index)) {
        firstParagraphOutsideHeading = index;
        break;
      }
    }
    const anchor =
      presentationAnchor(matches, latinParagraphs) ??
      previousAnchor ??
      nextAnchor ??
      firstParagraphOutsideHeading ??
      0;
    const anchored = chantsByParagraph.get(anchor);
    if (anchored === undefined) {
      chantsByParagraph.set(anchor, [chant]);
    } else {
      anchored.push(chant);
    }
  });

  const result: OfficeSection[] = [];
  let residualIndices: number[] = [];

  function appendResidual(): void {
    if (residualIndices.length === 0) return;
    const suffix = result.length === 0 ? "" : `-continuation-${result.length}`;
    result.push(
      replacingPresentation(text, {
        id: `${text.id}${suffix}`,
        title: result.length === 0 ? presentationTitle : "",
        rubric: result.length === 0 ? (text.rubric ?? null) : null,
        rubricEnglish:
          result.length === 0 ? (text.rubricEnglish ?? null) : null,
        latin: residualIndices
          .map((index) => latinParagraphs[index])
          .join("\n\n"),
        english:
          translationsAlign && englishParagraphs !== null
            ? residualIndices
                .map((index) => englishParagraphs[index])
                .join("\n\n")
            : (text.english ?? null),
      }),
    );
    residualIndices = [];
  }

  function appendChants(
    sections: readonly OfficeSection[],
    paragraphIndex: number | null,
  ): void {
    appendResidual();
    for (const chant of sections) {
      let english: string | null;
      if (
        translationsAlign &&
        paragraphIndex !== null &&
        englishParagraphs !== null &&
        chantsCoveringText.has(chant.id)
      ) {
        english = presentationTranslation(englishParagraphs[paragraphIndex]);
      } else {
        english = chant.english ?? null;
      }
      result.push(
        replacingPresentation(chant, {
          title: result.length === 0 ? presentationTitle : "",
          titleEnglish:
            result.length === 0 ? (text.titleEnglish ?? null) : null,
          rubric: result.length === 0 ? (text.rubric ?? null) : null,
          rubricEnglish:
            result.length === 0 ? (text.rubricEnglish ?? null) : null,
          english,
        }),
      );
    }
  }

  for (
    let paragraphIndex = 0;
    paragraphIndex < latinParagraphs.length;
    paragraphIndex += 1
  ) {
    const paragraphChants = chantsByParagraph.get(paragraphIndex);
    if (paragraphChants !== undefined) {
      appendChants(paragraphChants, paragraphIndex);
    }
    if (!coveredIndices.has(paragraphIndex)) {
      residualIndices.push(paragraphIndex);
    }
  }
  appendResidual();
  if (latinParagraphs.length === 0) {
    // A text left without words still gives its heading to its scores.
    appendChants(chants, null);
  }
  return result;
}

function presentationAnchor(
  matches: readonly number[],
  paragraphs: readonly string[],
): number | null {
  if (!(matches.length > 1)) return matches.length > 0 ? matches[0] : null;

  // Compact office books print a repeated antiphon's full score after
  // the psalm or canticle, while omitting its prose announcement.
  if (matches.every((match) => isAntiphonParagraph(paragraphs[match]))) {
    return matches[matches.length - 1];
  }
  return matches[0];
}

function suppressingRepeatedHeadings(
  sections: readonly OfficeSection[],
): OfficeSection[] {
  let lastVisibleHeading: string | null = null;
  return sections.map((section) => {
    const heading = normalizedTitle(section.title);
    if (heading.length === 0) {
      return section;
    }
    const repeatsHeading = heading === lastVisibleHeading;
    lastVisibleHeading = heading;
    if (!repeatsHeading) {
      return section;
    }
    return replacingPresentation(section, { title: "" });
  });
}

function interleavingCompactPsalmody(
  source: readonly OfficeSection[],
): OfficeSection[] {
  const result: OfficeSection[] = [];
  let index = 0;

  while (index < source.length) {
    if (source[index].kind !== "psalm") {
      result.push(source[index]);
      index += 1;
      continue;
    }

    const blockStart = index;
    while (index < source.length && source[index].kind === "psalm") {
      index += 1;
    }
    const block = source.slice(blockStart, index);
    result.push(...interleavingCompactPsalmBlock(block));
  }

  return result;
}

function interleavingCompactPsalmBlock(
  block: readonly OfficeSection[],
): OfficeSection[] {
  const enumerated = block.map((element, offset) => ({ offset, element }));
  const chants = enumerated.filter(({ element }) => element.chant != null);
  const texts = enumerated.filter(({ element }) => element.chant == null);
  if (!(
    texts.length > 0 &&
    chants.length > 0 &&
    chants[chants.length - 1].offset < texts[0].offset
  )) {
    return block.slice();
  }

  const chantsByTextID = new Map<string, OfficeSection[]>();
  const unmatchedChants: OfficeSection[] = [];
  for (const { element: chant } of chants) {
    const targetID = psalmContentTargetID(
      chant,
      texts.map(({ element }) => element),
    );
    if (targetID === null) {
      unmatchedChants.push(chant);
      continue;
    }
    const matched = chantsByTextID.get(targetID);
    if (matched === undefined) {
      chantsByTextID.set(targetID, [chant]);
    } else {
      matched.push(chant);
    }
  }

  const reordered = unmatchedChants.slice();
  for (const { element: text } of texts) {
    const matchingChants = chantsByTextID.get(text.id) ?? [];
    chantsByTextID.delete(text.id);
    const coveringIndex = maxBy(
      matchingChants.map((_, index) => index),
      (lhs, rhs) =>
        scoredWordCount(matchingChants[lhs]) <
        scoredWordCount(matchingChants[rhs]),
    );
    if (
      coveringIndex !== null &&
      scoreCovers(matchingChants[coveringIndex], text)
    ) {
      matchingChants[coveringIndex] = mergingTextMetadata(
        matchingChants[coveringIndex],
        text,
      );
      reordered.push(...matchingChants);
    } else {
      reordered.push(
        ...compactPsalmPresentation(
          matchingChants,
          text,
          chants.map(({ element }) => element),
        ),
      );
    }
  }
  for (const remaining of chantsByTextID.values()) {
    reordered.push(...remaining);
  }
  return reordered;
}

function compactPsalmPresentation(
  chants: readonly OfficeSection[],
  text: OfficeSection,
  reusableChants: readonly OfficeSection[],
): OfficeSection[] {
  const latinParagraphs = paragraphs(text.latin);
  const englishParagraphs =
    text.english != null ? paragraphs(text.english) : null;
  const translationsAlign =
    englishParagraphs !== null &&
    englishParagraphs.length === latinParagraphs.length;
  const consumedIndices = new Set<number>();
  for (let index = 0; index < latinParagraphs.length; index += 1) {
    if (isPsalmHeading(latinParagraphs[index])) consumedIndices.add(index);
  }
  const preparedChants: OfficeSection[] = [];

  chants.forEach((chant, chantIndex) => {
    const paragraphIndex = bestParagraphIndex(
      chant.latin,
      latinParagraphs,
      consumedIndices,
    );
    if (paragraphIndex !== null) {
      consumedIndices.add(paragraphIndex);
    }
    let english: string | null;
    if (
      translationsAlign &&
      paragraphIndex !== null &&
      englishParagraphs !== null
    ) {
      english = presentationTranslation(englishParagraphs[paragraphIndex]);
    } else {
      english = chant.english ?? null;
    }
    const title =
      chantIndex > 0 &&
      normalizedTitle(chants[chantIndex - 1].title) ===
        normalizedTitle(chant.title)
        ? ""
        : chant.title;
    preparedChants.push(
      replacingPresentation(chant, {
        title,
        rubric: null,
        english,
      }),
    );
  });

  const repeatedAntiphons: OfficeSection[] = [];
  for (
    let paragraphIndex = 0;
    paragraphIndex < latinParagraphs.length;
    paragraphIndex += 1
  ) {
    if (!(
      !consumedIndices.has(paragraphIndex) &&
      isAntiphonParagraph(latinParagraphs[paragraphIndex])
    )) {
      continue;
    }
    const chant = maxBy(
      reusableChants,
      (lhs, rhs) =>
        longestSharedRun(
          normalizedLatinWords(lhs.latin),
          normalizedLatinWords(latinParagraphs[paragraphIndex]),
        ) <
        longestSharedRun(
          normalizedLatinWords(rhs.latin),
          normalizedLatinWords(latinParagraphs[paragraphIndex]),
        ),
    );
    if (!(
      chant !== null &&
      longestSharedRun(
        normalizedLatinWords(chant.latin),
        normalizedLatinWords(latinParagraphs[paragraphIndex]),
      ) >= 4
    )) {
      continue;
    }
    consumedIndices.add(paragraphIndex);
    let english: string | null;
    if (translationsAlign && englishParagraphs !== null) {
      english = presentationTranslation(englishParagraphs[paragraphIndex]);
    } else {
      english = null;
    }
    repeatedAntiphons.push(
      replacingPresentation(chant, {
        id: `${chant.id}-repeat-${text.id}-${paragraphIndex}`,
        title: "",
        rubric: null,
        english,
      }),
    );
  }

  const remainingIndices: number[] = [];
  for (let index = 0; index < latinParagraphs.length; index += 1) {
    if (!consumedIndices.has(index)) remainingIndices.push(index);
  }
  const result = preparedChants.slice();
  if (remainingIndices.length > 0) {
    result.push(
      replacingPresentation(text, {
        title: "",
        rubric: null,
        latin: remainingIndices
          .map((index) => latinParagraphs[index])
          .join("\n\n"),
        english:
          translationsAlign && englishParagraphs !== null
            ? remainingIndices
                .map((index) => englishParagraphs[index])
                .join("\n\n")
            : (text.english ?? null),
      }),
    );
  }
  result.push(...repeatedAntiphons);
  return result;
}

function paragraphs(value: string): string[] {
  return componentsSeparatedBy(value, "\n\n")
    .map(trimmingWhitespaceAndNewlines)
    .filter((paragraph) => paragraph.length > 0);
}

function bestParagraphIndex(
  incipit: string,
  paragraphs: readonly string[],
  excludedIndices: ReadonlySet<number>,
): number | null {
  const incipitWords = normalizedLatinWords(incipit);
  if (!(incipitWords.length >= 4)) return null;
  const candidates: { readonly index: number; readonly run: number }[] = [];
  for (let index = 0; index < paragraphs.length; index += 1) {
    if (excludedIndices.has(index)) continue;
    const run = longestSharedRun(
      incipitWords,
      normalizedLatinWords(paragraphs[index]),
    );
    if (run >= 4) candidates.push({ index, run });
  }
  const best = maxBy(candidates, (lhs, rhs) => lhs.run < rhs.run);
  return best === null ? null : best.index;
}

function isPsalmHeading(paragraph: string): boolean {
  const value = normalizedTitle(paragraph);
  return (
    value === "psalmi" ||
    hasPrefix(value, "psalmi ") ||
    value === "psalms" ||
    hasPrefix(value, "psalms ") ||
    hasPrefix(value, "psalmus ") ||
    hasPrefix(value, "psalm ")
  );
}

function isAntiphonParagraph(paragraph: string): boolean {
  const value = trimmingWhitespaceAndNewlines(paragraph);
  return hasPrefix(value, "Ant.") || hasPrefix(value, "Ant ");
}

function presentationTranslation(paragraph: string): string {
  let value = PsalmTextFormatter.strippingScriptureReference(paragraph);
  if (hasPrefix(value, "Ant. ")) {
    value = dropFirst(value, characterCount("Ant. "));
  } else if (hasPrefix(value, "Ant ")) {
    value = dropFirst(value, characterCount("Ant "));
  }
  return value;
}

function psalmContentTargetID(
  chant: OfficeSection,
  sections: readonly OfficeSection[],
): string | null {
  const incipitWords = normalizedLatinWords(chant.latin);
  if (incipitWords.length >= 4) {
    let best: { readonly id: string; readonly run: number } | null = null;
    for (const section of sections) {
      const run = longestSharedRun(
        incipitWords,
        normalizedLatinWords(section.latin),
      );
      if (run >= 4 && run > (best === null ? 3 : best.run)) {
        best = { id: section.id, run };
      }
    }
    if (best !== null) {
      return best.id;
    }
  }
  return contentTargetID(chant, sections);
}

function correctedSource(
  source: readonly OfficeSection[],
  preservesUnnumberedAntiphons = false,
): OfficeSection[] {
  const standaloneAntiphonTranslations = new Set<string>();
  for (const section of source) {
    if (section.english == null) continue;
    const values = paragraphs(section.english);
    if (!(values.length === 1 && isAntiphonParagraph(values[0]))) {
      continue;
    }
    standaloneAntiphonTranslations.add(presentationTranslation(values[0]));
  }
  const corrected = source.map((section) => {
    if (!(
      section.kind === "psalm" &&
      section.chant != null &&
      section.english != null
    )) {
      return section;
    }
    const values = paragraphs(section.english);
    if (!(values.length > 1)) return section;
    const retained: string[] = [];
    values.forEach((paragraph, index) => {
      if (!(
        isAntiphonParagraph(paragraph) &&
        standaloneAntiphonTranslations.has(presentationTranslation(paragraph))
      )) {
        retained.push(paragraph);
        return;
      }
      if (index > 0 && index < values.length - 1) {
        const previous = scriptureReference(values[index - 1]);
        const next = scriptureReference(values[index + 1]);
        if (
          previous !== null &&
          next !== null &&
          previous.psalm === next.psalm
        ) {
          if (next.verse === previous.verse + 1) {
            return;
          }
          if (next.verse === previous.verse + 2) {
            retained.push(
              `${previous.psalm}:${previous.verse + 1} ` +
                presentationTranslation(paragraph),
            );
            return;
          }
        }
      }
      if (preservesUnnumberedAntiphons) retained.push(paragraph);
    });
    if (sameElements(retained, values)) return section;
    return replacingPresentation(section, {
      english: retained.join("\n\n"),
    });
  });

  const firstTextIndex = corrected.findIndex(
    (section) => section.chant == null,
  );
  if (
    firstTextIndex >= 0 &&
    normalizedTitle(corrected[firstTextIndex].title) === "incipit" &&
    startsWith(normalizedLatinWords(corrected[firstTextIndex].latin), [
      "incipit",
      "iube",
      "domine",
    ]) &&
    corrected.some(
      (section) => normalizedTitle(section.title) === "lectio brevis",
    )
  ) {
    const section = corrected[firstTextIndex];
    corrected[firstTextIndex] = makeOfficeSection({
      id: section.id,
      kind: section.kind,
      title: "Lectio brevis",
      titleEnglish: section.titleEnglish,
      rubric: section.rubric,
      rubricEnglish: section.rubricEnglish,
      latin: withoutLeadingParagraph(section.latin, ["Incipit"]),
      english:
        section.english != null
          ? withoutLeadingParagraph(section.english, ["Start", "Beginning"])
          : null,
      chant: null,
    });
  }

  if (corrected.length > 0) {
    const opening = corrected[0];
    if (opening.chant != null && normalizedTitle(opening.title) === "incipit") {
      const targetID = contentTargetID(opening, corrected);
      if (targetID !== null) {
        const targetIndexBeforeRemoval = corrected.findIndex(
          (section) => section.id === targetID,
        );
        if (
          targetIndexBeforeRemoval > 1 &&
          textOpensWith(corrected[targetIndexBeforeRemoval], opening)
        ) {
          corrected.shift();
          const targetIndex = corrected.findIndex(
            (section) => section.id === targetID,
          );
          if (targetIndex >= 0) {
            corrected.splice(targetIndex, 0, opening);
          }
        }
      }
    }
  }

  return corrected;
}

function scriptureReference(
  text: string,
): { readonly psalm: number; readonly verse: number } | null {
  const value = trimmingWhitespaceAndNewlines(text);
  const separator = firstCharacter(value, isWhitespace);
  if (separator === null) {
    return null;
  }
  // Empty pieces are kept, so that "76::15" is not read as "76:15". (A
  // separator of one Character divides as `components(separatedBy:)` does.)
  const parts = componentsSeparatedBy(value.slice(0, separator.offset), ":");
  if (parts.length !== 2) return null;
  const psalm = swiftInt(parts[0]);
  const verse = swiftInt(parts[1]);
  if (psalm === null || verse === null) {
    return null;
  }
  return { psalm, verse };
}

function contentTargetID(
  chant: OfficeSection,
  sections: readonly OfficeSection[],
): string | null {
  const gabc = chant.chant?.gabc;
  if (gabc == null) return null;
  const body = componentsSeparatedBy(gabc, "%%").slice(1).join("%%");
  const scoredWords = normalizedLatinWords(body.length === 0 ? gabc : body);
  if (!(scoredWords.length >= 4)) return null;

  let best: { readonly id: string; readonly run: number } | null = null;
  for (const section of sections) {
    if (section.chant != null) continue;
    const run = substantialSharedRun(
      scoredWords,
      normalizedLatinWords(section.latin),
    );
    if (!(run !== null && run > (best === null ? 0 : best.run))) continue;
    best = { id: section.id, run };
  }
  return best === null ? null : best.id;
}

function scoredWordCount(section: OfficeSection): number {
  return scoredWords(section).length;
}

function scoredWords(section: OfficeSection): string[] {
  const gabc = section.chant?.gabc;
  if (gabc == null) return [];
  const body = componentsSeparatedBy(gabc, "%%").slice(1).join("%%");
  return normalizedLatinWords(body.length === 0 ? gabc : body);
}

function scoreCovers(chant: OfficeSection, text: OfficeSection): boolean {
  const scoredCount = scoredWordCount(chant);
  const textCount = normalizedLatinWords(text.latin).length;
  if (!(textCount > 0)) return true;
  return scoredCount >= 8 && scoredCount / textCount >= 0.7;
}

function scoreCoversParagraph(
  chant: OfficeSection,
  paragraph: string,
): boolean {
  const scoreWords = scoredWords(chant);
  const paragraphWords = normalizedLatinWords(paragraph);
  if (!(scoreWords.length > 0 && paragraphWords.length > 0)) return false;
  const sharedRun = longestSharedRun(scoreWords, paragraphWords);

  if (paragraphWords.length <= 3) {
    return sharedRun === paragraphWords.length;
  }
  return sharedRun >= 4 && sharedRun / paragraphWords.length >= 0.7;
}

// An ICU pattern: Foundation replaces with NSRegularExpression.
const parenthesized = /\([^)]*\)/gu;

function normalizedLatinWords(value: string): string[] {
  let result = value.replace(parenthesized, "");
  // GABC emphasis may divide a single word, as in *tu*(k)um.
  // Remove its inline markers instead of treating them as word
  // boundaries, while the surrounding whitespace still separates
  // genuine flex/mediant markers in prose.
  result = replacingOccurrences(result, "*", "");
  result = replacingOccurrences(result, "_", "");
  result = folding(result, {
    caseInsensitive: true,
    diacriticInsensitive: true,
  }).toLowerCase();
  result = replacingOccurrences(result, "j", "i");
  result = replacingOccurrences(result, "v", "u");
  return componentsSeparatedByNonAlphanumerics(result).filter(
    hasSeveralCharacters,
  );
}

/** `count > 1`, for a word. */
function hasSeveralCharacters(word: string): boolean {
  if (word.length <= 1) return false;
  // Two scalars below the combining marks are two Characters.
  if (word.charCodeAt(0) < 0x300 && word.charCodeAt(1) < 0x300) return true;
  return characterCount(word) > 1;
}

/**
 * The shared word run between a score and a text, when it is long
 * enough to identify the one with the other: at least four words,
 * covering at least half of the score or of the text. A common formula
 * such as "in sǽcula sæculórum. Amen" or "Glória Patri" does not by
 * itself make a score part of another prayer.
 */
function substantialSharedRun(
  scoreWords: readonly string[],
  textWords: readonly string[],
): number | null {
  const run = longestSharedRun(scoreWords, textWords);
  if (!(
    run >= 4 &&
    (run * 2 >= scoreWords.length || run * 2 >= textWords.length)
  )) {
    return null;
  }
  return run;
}

function longestSharedRun(
  left: readonly string[],
  right: readonly string[],
): number {
  if (!(left.length > 0 && right.length > 0)) return 0;
  if (sameElements(left, right)) return left.length;
  const [scanned, indexed] =
    left.length >= right.length ? [left, right] : [right, left];
  const positions = new Map<string, number[]>();
  indexed.forEach((word, index) => {
    const indices = positions.get(word);
    if (indices === undefined) {
      positions.set(word, [index]);
    } else {
      indices.push(index);
    }
  });
  let previous = new Map<number, number>();
  let longest = 0;
  for (const word of scanned) {
    // Only equal words can extend a contiguous run. Each length
    // extends the preceding row and column, never the current row;
    // mismatches therefore break a run rather than joining gaps.
    const current = new Map<number, number>();
    for (const index of positions.get(word) ?? []) {
      const length = (previous.get(index - 1) ?? 0) + 1;
      current.set(index, length);
      longest = Math.max(longest, length);
    }
    if (longest === indexed.length) return longest;
    previous = current;
  }
  return longest;
}

function withoutLeadingParagraph(
  value: string,
  headings: readonly string[],
): string {
  const paragraphs = componentsSeparatedBy(value, "\n\n");
  if (!(
    paragraphs.length > 1 &&
    headings.some(
      (heading) =>
        folding(paragraphs[0], {
          caseInsensitive: true,
          diacriticInsensitive: true,
        }) ===
        folding(heading, {
          caseInsensitive: true,
          diacriticInsensitive: true,
        }),
    )
  )) {
    return value;
  }
  return paragraphs.slice(1).join("\n\n");
}

function normalizedTitle(value: string): string {
  return componentsSeparatedByNonAlphanumerics(
    folding(value, { caseInsensitive: true, diacriticInsensitive: true }),
  )
    .filter((word) => word.length > 0)
    .join(" ");
}

// Swift's private `OfficeSection` extension.

function mergingTextMetadata(
  section: OfficeSection,
  textSection: OfficeSection,
): OfficeSection {
  return makeOfficeSection({
    id: section.id,
    kind: section.kind,
    title: section.title,
    titleEnglish: textSection.titleEnglish ?? section.titleEnglish,
    rubric: textSection.rubric ?? section.rubric,
    rubricEnglish: textSection.rubricEnglish ?? section.rubricEnglish,
    latin: section.latin,
    english: textSection.english ?? section.english,
    chant: section.chant,
  });
}

/**
 * The arguments of `replacingPresentation`. A field left out (`undefined`)
 * keeps the section's own value; `null`, where a field allows it, is Swift's
 * `.some(nil)` and removes the value.
 */
interface PresentationReplacement {
  readonly id?: string;
  readonly title?: string;
  readonly titleEnglish?: string | null;
  readonly rubric?: string | null;
  readonly rubricEnglish?: string | null;
  readonly latin?: string;
  readonly english?: string | null;
}

/**
 * A copy with some of its presentation replaced. An omitted argument keeps
 * the section's own value; pass `.some(nil)` to remove a rubric.
 */
function replacingPresentation(
  section: OfficeSection,
  replacement: PresentationReplacement,
): OfficeSection {
  const { id, title, titleEnglish, rubric, rubricEnglish, latin, english } =
    replacement;
  return makeOfficeSection({
    id: id ?? section.id,
    kind: section.kind,
    title: title ?? section.title,
    titleEnglish:
      titleEnglish !== undefined
        ? titleEnglish
        : title === ""
          ? null
          : section.titleEnglish,
    rubric: rubric !== undefined ? rubric : section.rubric,
    rubricEnglish:
      rubricEnglish !== undefined
        ? rubricEnglish
        : rubric === null
          ? null
          : section.rubricEnglish,
    latin: latin ?? section.latin,
    english: english !== undefined ? english : section.english,
    chant: section.chant,
  });
}

// Array helpers Swift has in its standard library.

function sameElements(lhs: readonly string[], rhs: readonly string[]): boolean {
  return (
    lhs.length === rhs.length &&
    lhs.every((value, index) => value === rhs[index])
  );
}

function startsWith(
  values: readonly string[],
  prefix: readonly string[],
): boolean {
  return (
    values.length >= prefix.length &&
    prefix.every((value, index) => value === values[index])
  );
}

function sortedAscending(values: readonly number[]): number[] {
  return values.slice().sort((lhs, rhs) => lhs - rhs);
}

/** A hashable form of a word list, for Swift's `Set<[String]>`. */
function wordsKey(words: readonly string[]): string {
  return words.join(" ");
}

// MARK: Without the chant
//
// The Roman 1960 edition prints only the opening words of a psalm, canticle
// or hymn that it sings, and only the mark of a versicle or a response: the
// words are in the score. Where the chant is not shown, those words are
// written out from the score as the books set them: a psalm or canticle
// verse by verse, pointed as its tone points it; a hymn stanza by stanza,
// line by line; each versicle and response on its line. An antiphon is
// marked "Ant." as a breviary marks it. Kept parallel to
// `HoursApp/OfficeTextWithoutChant.swift`.

function writingOutSungWords(
  sections: readonly OfficeSection[],
): OfficeSection[] {
  return sections.map((section) => {
    const written = writtenOut(section);
    // A response follows its versicle on the next line, as a breviary sets
    // them; psalmody keeps its verses apart.
    if (
      !isAntiphon(written) &&
      (written.kind === "psalm" ||
        written.kind === "canticle" ||
        written.kind === "hymn")
    ) {
      return written;
    }
    const latin = tightened(written.latin);
    const english =
      written.english == null ? written.english : tightened(written.english);
    if (latin === written.latin && english === written.english) return written;
    return { ...written, latin, english };
  });
}

function tightened(text: string): string {
  return text.replace(/(?<=\S)[ \t]*\n[ \t]*\n\s*(?=℟)/gu, "\n");
}

/** Whether a section is an antiphon: one marked "Ant." in its Latin, or
 * whose English opens with the antiphon, so marked, and whose Latin is not
 * a psalm's numbered verses. */
function isAntiphon(section: OfficeSection): boolean {
  if (!(
    section.kind === "psalm" ||
    section.kind === "canticle" ||
    section.kind === "antiphon"
  )) {
    return false;
  }
  if (isAntiphonParagraph(section.latin)) return true;
  const first =
    section.english == null ? undefined : paragraphs(section.english)[0];
  if (first === undefined || !isAntiphonParagraph(first)) return false;
  return !/^\s*\d+[.:]/u.test(section.latin);
}

/** The English of the sung parts set as their Latin is set. A hymn's is
 * without a second copy of the hymn, or the versicle and response after
 * it, which have their own sections, and its lines are in the stanzas of
 * the Latin. An antiphon's is without the "Let us pray" that some print
 * after it, which its Latin does not say. */
function settingEnglishOfSungParts(
  sections: readonly OfficeSection[],
): OfficeSection[] {
  return sections.map((section, index) => {
    const english = section.english;
    if (english == null) return section;
    if (isAntiphon(section)) {
      const values = paragraphs(english);
      const latin = section.latin.normalize("NFC").toLowerCase();
      if (
        !(values.length > 1 && values[values.length - 1] === "Let us pray.") ||
        latin.includes("orémus") ||
        latin.includes("oremus")
      ) {
        return section;
      }
      return { ...section, english: values.slice(0, -1).join("\n\n") };
    }
    if (section.kind !== "hymn" || section.chant == null) return section;
    const score = parsingScore(section.chant.gabc, section.chant.timeline);
    if (score === null) return section;
    const following = sections
      .slice(index + 1, index + 4)
      .flatMap((next) => (next.english == null ? [] : [next.english]));
    const set = hymnEnglish(
      english,
      hymnStanzas(scoredVerseElements(score)).map((stanza) => stanza.length),
      following,
    );
    return set === english ? section : { ...section, english: set };
  });
}

function hymnEnglish(
  english: string,
  counts: readonly number[],
  following: readonly string[] = [],
): string {
  let values = paragraphs(english);
  // A second copy of the hymn, headed again.
  const heading = values.findIndex(
    (value, index) =>
      index > 0 &&
      ["hymn", "hymnus"].includes(
        value.toLowerCase().replace(/^\p{P}+|\p{P}+$/gu, ""),
      ),
  );
  if (
    heading > 0 &&
    heading + 1 < values.length &&
    values[heading + 1] === values[0]
  ) {
    values = values.slice(0, heading);
  }
  // The versicle and response that follow the hymn in sections of their own.
  const followingParagraphs = new Set(following.flatMap(paragraphs));
  while (values.length > 1) {
    const last = values[values.length - 1];
    if (
      !(last.startsWith("℣.") || last.startsWith("℟.")) ||
      !followingParagraphs.has(last)
    ) {
      break;
    }
    values = values.slice(0, -1);
  }
  let amen: string | null = null;
  if (
    values.length > 1 &&
    ["amen.", "amen"].includes(values[values.length - 1].toLowerCase())
  ) {
    amen = values[values.length - 1];
    values = values.slice(0, -1);
  }
  let stanzas: string[][];
  const total = counts.reduce((sum, count) => sum + count, 0);
  if (values.some((value) => value.includes("\n"))) {
    stanzas = values.map((value) => value.split("\n"));
  } else if (counts.length > 0 && total === values.length) {
    stanzas = [];
    let start = 0;
    for (const count of counts) {
      stanzas.push(values.slice(start, start + count));
      start += count;
    }
  } else if (counts.length > 1 && values.length % counts.length === 0) {
    const size = values.length / counts.length;
    stanzas = [];
    for (let start = 0; start < values.length; start += size) {
      stanzas.push(values.slice(start, start + size));
    }
  } else {
    stanzas = values.map((value) => [value]);
  }
  const lastStanza = stanzas[stanzas.length - 1];
  if (amen !== null && lastStanza !== undefined && lastStanza.length > 0) {
    lastStanza[lastStanza.length - 1] += ` ${amen}`;
  }
  const set = stanzas.map((stanza) => stanza.join("\n")).join("\n\n");
  return set === paragraphs(english).join("\n\n") ? english : set;
}

function writtenOut(section: OfficeSection): OfficeSection {
  const antiphon = isAntiphon(section);
  let latin = section.latin;
  let english = section.english ?? null;
  const chant = section.chant;
  const score = chant == null ? null : parsingScore(chant.gabc, chant.timeline);
  if (
    score !== null &&
    wordCount(GregorianScores.lyricText(score)) > wordCount(section.latin)
  ) {
    const verses = scoredVerseElements(score);
    if (section.kind === "hymn") {
      latin = hymnStanzas(verses)
        .map((stanza) => stanza.join("\n"))
        .join("\n\n");
    } else if (
      !antiphon &&
      (section.kind === "psalm" || section.kind === "canticle") &&
      verses.length > 1
    ) {
      const pointed = numberingFirstVerse(
        normalizingTrailingVerseOrdinals(
          verses.map((verse) =>
            trimmingWhitespaceAndNewlines(pointedLyricText(verse)),
          ),
        ),
      );
      latin = pointed.join("\n\n");
      if (english !== null) {
        const alignment = aligningPsalmodyEnglish(
          paragraphs(english),
          pointed.map((verse) =>
            PsalmTextFormatter.removingEmphasisMarkers(verse),
          ),
        );
        if (alignment !== null) {
          english = serializedPsalmodyEnglish(
            alignment.verses,
            alignment.trailing,
          );
        }
      }
    } else {
      const lines = sungLines(verses, !antiphon);
      latin = lines.join("\n");
      // The antiphon repeated after its psalm is printed without the mark
      // where the cantor's intonation ends.
      if (antiphon && !section.latin.includes("*")) {
        latin = latin.replaceAll(" * ", " ");
      }
      // The English set line by line, as the Latin is.
      if (english !== null && lines.length > 1) {
        english = paragraphs(english).join("\n");
      }
    }
    // A score's transcription may space a colon as French printing spaces it.
    latin = withPlainOpening(latin).replace(
      /[ \t\u00A0\u2009\u202F]+([:;?!])/gu,
      "$1",
    );
  }
  // A versicle and response marked in the edition's own letters.
  latin = latin
    .replace(/(^|\s)V\/\./gu, "$1℣.")
    .replace(/(^|\s)R\/\./gu, "$1℟.");
  if (antiphon) {
    if (/\p{L}$/u.test(latin)) latin += ".";
    if (!isAntiphonParagraph(latin)) latin = `Ant. ${latin}`;
  } else {
    const first = english === null ? undefined : paragraphs(english)[0];
    if (
      first !== undefined &&
      first.startsWith("℟.br.") &&
      !latin.startsWith("℟")
    ) {
      latin = `℟.br. ${latin}`;
    }
  }
  if (latin === section.latin && english === (section.english ?? null)) {
    return section;
  }
  return { ...section, latin, english };
}

/** The words of a text, versicles' and responses' marks apart. */
function wordCount(text: string): number {
  return text.split(/[^\p{L}\p{M}]+/u).filter((word) => [...word].length > 1)
    .length;
}

/** A psalm's first verse numbered as the rest are. */
function numberingFirstVerse(verses: readonly string[]): string[] {
  if (
    !(verses.length > 1) ||
    !verses[1].startsWith("2. ") ||
    /^\d+\.\s/u.test(verses[0])
  ) {
    return verses.slice();
  }
  return [`1. ${verses[0]}`, ...verses.slice(1)];
}

/** A line of sung words, spaced as a score's lyric is spaced. */
class SungLine {
  private text = "";
  private separatesFollowingLyric = false;

  append(value: string, startsWord: boolean, isMark: boolean): void {
    if (value.length === 0) return;
    const last = lastCharacter(this.text);
    if (
      this.text.length > 0 &&
      (startsWord || this.separatesFollowingLyric) &&
      !(last !== null && isWhitespace(last))
    ) {
      this.text += " ";
    }
    this.text += value;
    this.separatesFollowingLyric = isMark;
  }

  /** The line, if it holds any words; it is begun afresh. */
  finished(): string[] {
    const value = trimmingWhitespaceAndNewlines(this.text);
    this.text = "";
    this.separatesFollowingLyric = false;
    return value.length === 0 ? [] : [value];
  }
}

/** The words of a score's verses, a line to each verse and to each
 * versicle and response within one; the doxology and the Alleluia that
 * close an opening begin lines of their own. */
function sungLines(
  verses: readonly (readonly GregorianNotationElement[])[],
  breaksBeforeFormulas: boolean,
): string[] {
  const result: string[] = [];
  for (const verse of verses) {
    const line = new SungLine();
    for (const element of verse) {
      if (element.type === "neume") {
        line.append(element.neume.lyric, element.neume.startsWord, false);
      } else if (element.type === "lyricMark") {
        if (
          element.lyricMark.text === "℣." ||
          element.lyricMark.text === "℟."
        ) {
          result.push(...line.finished());
        }
        line.append(element.lyricMark.text, element.lyricMark.startsWord, true);
      }
    }
    result.push(...line.finished());
  }
  // A score may set the mark of the line that follows (℟., ℣., T.P.) at the
  // bar that ends the line before.
  const carried: string[] = [];
  let mark: string | null = null;
  for (const value of result) {
    let line = value;
    if (mark !== null) {
      line = `${mark} ${line}`;
      mark = null;
    }
    if (line === "℣." || line === "℟." || line === "T.P.") {
      mark = line;
      continue;
    }
    if (line.endsWith(" T.P.")) {
      line = line.slice(0, -" T.P.".length);
      mark = "T.P.";
    }
    carried.push(line);
  }
  if (mark !== null) carried.push(mark);
  if (!breaksBeforeFormulas) return carried;
  return carried.flatMap((line) =>
    line
      .replace(
        /(?<=\p{Ll}[.!?])\s+(?=(?:Gl[oó]ria Patri|Sicut erat|Allel[uú][ij]a))/gu,
        "\n",
      )
      .split("\n"),
  );
}

/** A hymn's stanzas, each a list of its lines. A line ends at a division
 * after which the words begin with a capital, as the books begin each line
 * of a hymn. The stanzas' numbers are left to the score; an Amen sung apart
 * closes the last stanza. */
function hymnStanzas(
  verses: readonly (readonly GregorianNotationElement[])[],
): string[][] {
  const stanzas: string[][] = [];
  for (const verse of verses) {
    let lines: string[] = [];
    const line = new SungLine();
    let divided = false;
    for (const element of verse) {
      if (element.type === "neume") {
        const firstLetter = [...element.neume.lyric].find((character) =>
          /\p{L}/u.test(character),
        );
        if (
          divided &&
          element.neume.startsWord &&
          firstLetter !== undefined &&
          isUppercase(firstLetter)
        ) {
          lines.push(...line.finished());
        }
        divided = false;
        line.append(element.neume.lyric, element.neume.startsWord, false);
      } else if (element.type === "lyricMark") {
        line.append(element.lyricMark.text, element.lyricMark.startsWord, true);
      } else if (element.type === "division") {
        divided = divided || element.division !== "final";
      }
    }
    lines.push(...line.finished());
    const lastIndex = lines.length - 1;
    lines = lines
      .map((value, index) => {
        let text = value;
        if (index === 0) text = text.replace(/^\d+\.\s*/u, "");
        if (index === lastIndex) text = text.replace(/\s*\d+\.$/u, "");
        return text;
      })
      .filter((text) => text.length > 0);
    if (lines.length === 0) continue;
    const previous = stanzas[stanzas.length - 1];
    if (
      lines.length === 1 &&
      ["amen.", "amen"].includes(lines[0].toLowerCase()) &&
      previous !== undefined
    ) {
      previous[previous.length - 1] += ` ${lines[0]}`;
    } else {
      stanzas.push(lines);
    }
  }
  return stanzas;
}

/** The first word as a book prints it in the text, its opening capitals (set
 * large in a score, beside its initial) in small letters again: "PAcíficus"
 * as "Pacíficus". A word set wholly in capitals is left. */
function withPlainOpening(text: string): string {
  const characters = [...text];
  const first = characters.findIndex((character) => /\p{L}/u.test(character));
  if (first < 0) return text;
  let end = first;
  while (end < characters.length && /\p{L}/u.test(characters[end])) end += 1;
  const word = characters.slice(first, end);
  let capitals = 0;
  while (capitals < word.length && isUppercase(word[capitals])) {
    capitals += 1;
  }
  if (!(capitals > 1 && capitals < word.length)) return text;
  return (
    characters.slice(0, first).join("") +
    word[0] +
    word.slice(1, capitals).join("").toLowerCase() +
    characters.slice(first + capitals).join("")
  );
}

export const OfficeReaderSectionBuilder = {
  compactContinuationSuffix,
  displaySections,
  writingOutSungWords,
  settingEnglishOfSungParts,
  isAntiphon,
  hymnEnglish,
  withCorrectedHeadings,
  showingDirectionsAsRubrics,
  sections,
  substantialSharedRun,
  longestSharedRun,
};
