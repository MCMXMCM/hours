import type { GregorianLyricStyle } from "@/core/notation";
import {
  characterCount,
  characters,
  dropLast,
  hasSuffix,
  isLetter,
  isNumber,
  isWhitespace,
  trimmingWhitespace,
  trimmingWhitespaceAndNewlines,
} from "@/core/swiftString.ts";
import {
  componentsSeparatedBy,
  componentsSeparatedByNewlines,
  firstCharacter,
  icuWhitespace,
  icuWordBoundary,
  replacingOccurrences,
  swiftInt,
  type StringRange,
} from "./strings.ts";

export type { StringRange } from "./strings.ts";

export interface PsalmTextLine {
  readonly id: number;
  readonly number: number | null;
  readonly latin: string;
  readonly english: string | null;
  /**
   * The syllables sung to a cadence's accented notes, set in heavy type.
   * Swift's `[Range<String.Index>]`: ranges of `latin`, in the UTF-16 offsets
   * `String.prototype.slice` takes.
   */
  readonly emphasizedRanges: readonly StringRange[];
  /**
   * The syllables sung to the notes preparatory to an accent, set in italics
   * as the Liber Usualis sets them; ranges as `emphasizedRanges`.
   */
  readonly preparatoryRanges: readonly StringRange[];
}

const missingTranslationPlaceholder = "\u{2063}";
const emphasisStartMarker = "\u{F0000}";
const emphasisEndMarker = "\u{F0001}";
const preparatoryStartMarker = "\u{F0002}";
const preparatoryEndMarker = "\u{F0003}";

/** The markers around a syllable of the style in pointed text: an accented
 * syllable's, a preparatory one's, or none. */
function markers(
  style: GregorianLyricStyle,
): { start: string; end: string } | null {
  switch (style) {
    case "accented":
      return { start: emphasisStartMarker, end: emphasisEndMarker };
    case "preparatory":
      return { start: preparatoryStartMarker, end: preparatoryEndMarker };
    case "regular":
    case "rubric":
      return null;
  }
}

/**
 * A string as Swift indexes it: its Characters, and the UTF-16 offset at which
 * each begins (with the string's length last). A Swift `String.Index` is an
 * index into `characters` here; a `Range<String.Index>` is a `CharacterRange`.
 */
interface CharacterView {
  readonly characters: readonly string[];
  readonly offsets: readonly number[];
}

interface CharacterRange {
  readonly lowerBound: number;
  readonly upperBound: number;
}

function characterView(value: string): CharacterView {
  const all = characters(value);
  const offsets: number[] = [];
  let offset = 0;
  for (const character of all) {
    offsets.push(offset);
    offset += character.length;
  }
  offsets.push(offset);
  return { characters: all, offsets };
}

function stringRange(view: CharacterView, range: CharacterRange): StringRange {
  return {
    lowerBound: view.offsets[range.lowerBound],
    upperBound: view.offsets[range.upperBound],
  };
}

function lines(
  latin: string,
  english: string | null | undefined,
  startsAfterScoredVerse: boolean,
): PsalmTextLine[] {
  const latinParagraphs = versesOfLines(paragraphs(latin));
  const englishParagraphs =
    english == null ? null : versesOfLines(paragraphs(english));
  const translationsAlign =
    englishParagraphs !== null &&
    englishParagraphs.length === latinParagraphs.length;
  let verseNumber = startsAfterScoredVerse ? 2 : 1;

  return latinParagraphs.map((paragraph, index) => {
    const latinVerse = versePrefix(paragraph);
    const pointedLatin = extractingEmphasis(latinVerse.text);
    let number: number | null;
    if (latinVerse.isNumbered) {
      number = latinVerse.explicitNumber ?? verseNumber;
      verseNumber = (number ?? verseNumber) + 1;
    } else {
      number = null;
    }
    let lineEnglish: string | null = null;
    if (translationsAlign && englishParagraphs !== null) {
      const englishParagraph = englishParagraphs[index];
      lineEnglish =
        englishParagraph !== missingTranslationPlaceholder
          ? strippingVersePrefix(englishParagraph)
          : null;
    }
    return {
      id: index,
      number,
      latin: pointedLatin.text,
      english: lineEnglish,
      emphasizedRanges: pointedLatin.accents,
      preparatoryRanges: pointedLatin.preparatory,
    };
  });
}

/** Whether a text is set a verse to a line, each opening with its
 * reference, or with the mark of the doxology's versicle or response, as
 * the 1954 edition sets its psalms and canticles. */
function isSetVerseByLine(text: string): boolean {
  const lines = text
    .split(/\r\n|\r|\n/u)
    .map((line) => line.trim())
    .filter((line) => line.length > 0);
  return (
    lines.length > 1 &&
    lines.some((line) => scriptureVerseNumber(line) !== null) &&
    lines.every(
      (line) =>
        scriptureVerseNumber(line) !== null ||
        line.startsWith("℣.") ||
        line.startsWith("℟."),
    )
  );
}

/** A text set a verse to a line, as a verse to a paragraph. */
function versesOfLines(values: string[]): string[] {
  if (!(values.length === 1 && isSetVerseByLine(values[0]))) return values;
  return values[0]
    .split(/\r\n|\r|\n/u)
    .map((line) => line.trim())
    .filter((line) => line.length > 0);
}

function removingEmphasisMarkers(value: string): string {
  return [
    emphasisStartMarker,
    emphasisEndMarker,
    preparatoryStartMarker,
    preparatoryEndMarker,
  ].reduce((text, marker) => replacingOccurrences(text, marker, ""), value);
}

/** The text without its markers, and the ranges of its accented and its
 * preparatory syllables. Syllables of one kind that meet are one range
 * (dex-tris), so that they are set as one word. */
function extractingEmphasis(value: string): {
  text: string;
  accents: StringRange[];
  preparatory: StringRange[];
} {
  let text = "";
  const accentOffsets: CharacterRange[] = [];
  const preparatoryOffsets: CharacterRange[] = [];
  let accentStart: number | null = null;
  let preparatoryStart: number | null = null;

  function close(start: number | null, offsets: CharacterRange[]): void {
    const count = characterCount(text);
    if (start === null || start >= count) return;
    const last = offsets.length > 0 ? offsets[offsets.length - 1] : null;
    if (last !== null && last.upperBound === start) {
      offsets[offsets.length - 1] = {
        lowerBound: last.lowerBound,
        upperBound: count,
      };
    } else {
      offsets.push({ lowerBound: start, upperBound: count });
    }
  }

  for (const character of characters(value)) {
    if (character === emphasisStartMarker) {
      accentStart = characterCount(text);
    } else if (character === emphasisEndMarker) {
      close(accentStart, accentOffsets);
      accentStart = null;
    } else if (character === preparatoryStartMarker) {
      preparatoryStart = characterCount(text);
    } else if (character === preparatoryEndMarker) {
      close(preparatoryStart, preparatoryOffsets);
      preparatoryStart = null;
    } else {
      text += character;
    }
  }

  const view = characterView(text);
  return {
    text,
    accents: accentOffsets.map((offset) => stringRange(view, offset)),
    preparatory: preparatoryOffsets.map((offset) => stringRange(view, offset)),
  };
}

function scriptureVerseNumber(value: string): number | null {
  const trimmed = trimmingWhitespaceAndNewlines(value);
  const separator = firstCharacter(trimmed, isWhitespace);
  if (separator === null) {
    return null;
  }
  const prefix = trimmed.slice(0, separator.offset);
  const parts = componentsSeparatedBy(prefix, ":");
  if (!(
    parts.length === 2 &&
    parts.every((part) => part.length > 0 && characters(part).every(isNumber))
  )) {
    return null;
  }
  return swiftInt(parts[1]);
}

function paragraphs(value: string): string[] {
  return componentsSeparatedBy(value, "\n\n")
    .map(trimmingWhitespaceAndNewlines)
    .filter((paragraph) => paragraph.length > 0);
}

// These are ICU patterns: NSRegularExpression, and Foundation's replacement.
const scriptureReferencePattern = `${icuWordBoundary}[0-9]+:[0-9]+[a-z]?[${icuWhitespace}]+`;
const pointingMarks = /[†‡*]/gu;
const whitespaceRun = new RegExp(`[${icuWhitespace}]+`, "gu");

/**
 * The stored paragraphs follow chant divisions; explicit inline Scripture
 * references come from the compiler's checked Bible concordance. Full-score
 * translations follow those references instead, joining verse continuations.
 * Never infer a missing reference from a mediant or a numerical gap here.
 */
function scriptureParagraphs(value: string): string {
  const reference = new RegExp(scriptureReferencePattern, "gu");
  const output: { reference: string | null; text: string }[] = [];
  for (const untrimmedLine of componentsSeparatedByNewlines(value)) {
    const line = trimmingWhitespaceAndNewlines(untrimmedLine);
    if (line.length === 0) continue;
    const matches = Array.from(line.matchAll(reference), (match) => ({
      location: match.index,
      length: match[0].length,
    }));
    if (!(matches.length > 0 && matches[0].location === 0)) {
      output.push({ reference: null, text: line });
      continue;
    }
    for (const [index, match] of matches.entries()) {
      const label = trimmingWhitespace(
        line.slice(match.location, match.location + match.length),
      );
      const start = match.location + match.length;
      const end =
        index + 1 < matches.length ? matches[index + 1].location : line.length;
      const text = trimmingWhitespaceAndNewlines(
        line
          .slice(start, end)
          .replace(pointingMarks, "")
          .replace(whitespaceRun, " "),
      );
      if (text.length === 0) continue;
      const last = output.length > 0 ? output[output.length - 1] : null;
      if (last !== null && last.reference === label) {
        last.text += " " + text;
      } else {
        output.push({ reference: label, text });
      }
    }
  }
  return output
    .map((item) => {
      if (item.reference === null) return item.text;
      // A biblical verse may begin inside a chant line (87:6, for
      // example). Capitalize its paragraph opening only after joining
      // continuations, retaining the source's case everywhere else.
      let text = item.text;
      const firstLetter = firstCharacter(text, isLetter);
      if (firstLetter !== null) {
        text =
          text.slice(0, firstLetter.offset) +
          firstLetter.character.toUpperCase() +
          text.slice(firstLetter.offset + firstLetter.character.length);
      }
      return `${item.reference} ${text}`;
    })
    .join("\n\n");
}

function removingScriptureReferences(value: string): string {
  return value.replace(new RegExp(scriptureReferencePattern, "gu"), "");
}

function strippingScriptureReference(value: string): string {
  const result = versePrefix(value);
  return result.isScriptureReference
    ? removingScriptureReferences(result.text)
    : value;
}

function strippingVersePrefix(value: string): string {
  return removingScriptureReferences(versePrefix(value).text);
}

interface VersePrefix {
  readonly text: string;
  readonly explicitNumber: number | null;
  readonly isNumbered: boolean;
  readonly isScriptureReference: boolean;
}

function versePrefix(value: string): VersePrefix {
  const trimmed = trimmingWhitespaceAndNewlines(value);
  const separator = firstCharacter(trimmed, isWhitespace);
  if (separator === null) {
    return {
      text: trimmed,
      explicitNumber: null,
      isNumbered: false,
      isScriptureReference: false,
    };
  }
  const prefix = trimmed.slice(0, separator.offset);
  const remainder = trimmingWhitespaceAndNewlines(
    trimmed.slice(separator.offset + separator.character.length),
  );

  if (hasSuffix(prefix, ".")) {
    const number = swiftInt(dropLast(prefix));
    if (number !== null && number > 0) {
      return {
        text: remainder,
        explicitNumber: number,
        isNumbered: true,
        isScriptureReference: false,
      };
    }
  }

  // A reference is two numbers and the one colon between them: empty
  // pieces are kept, so that "76::15" and "76:15:" are not references. (A
  // separator of one Character divides as `components(separatedBy:)` does.)
  const scriptureParts = componentsSeparatedBy(prefix, ":");
  if (
    scriptureParts.length === 2 &&
    scriptureParts.every(
      (part) => part.length > 0 && characters(part).every(isNumber),
    )
  ) {
    return {
      text: remainder,
      explicitNumber: null,
      isNumbered: true,
      isScriptureReference: true,
    };
  }
  return {
    text: trimmed,
    explicitNumber: null,
    isNumbered: false,
    isScriptureReference: false,
  };
}

export const PsalmTextFormatter = {
  missingTranslationPlaceholder,
  emphasisStartMarker,
  emphasisEndMarker,
  preparatoryStartMarker,
  preparatoryEndMarker,
  markers,
  lines,
  isSetVerseByLine,
  removingEmphasisMarkers,
  scriptureVerseNumber,
  scriptureParagraphs,
  strippingScriptureReference,
  strippingVersePrefix,
};
