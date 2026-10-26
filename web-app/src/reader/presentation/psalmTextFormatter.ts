import {
  characterCount,
  characters,
  dropLast,
  folding,
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
   * Swift's `[Range<String.Index>]`: ranges of `latin`, in the UTF-16 offsets
   * `String.prototype.slice` takes.
   */
  readonly emphasizedRanges: readonly StringRange[];
}

const missingTranslationPlaceholder = "\u{2063}";
const emphasisStartMarker = "\u{F0000}";
const emphasisEndMarker = "\u{F0001}";

const latinDiphthongs: ReadonlySet<string> = new Set(["ae", "au", "oe"]);
const inseparableConsonantPairs: ReadonlySet<string> = new Set([
  "bl",
  "br",
  "ch",
  "cl",
  "cr",
  "dr",
  "fl",
  "fr",
  "gl",
  "gn",
  "gr",
  "gu",
  "ph",
  "pl",
  "pr",
  "qu",
  "th",
  "tr",
]);

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
      emphasizedRanges:
        pointedLatin.ranges.length === 0
          ? emphasizedSyllableRanges(pointedLatin.text)
          : pointedLatin.ranges,
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
  return replacingOccurrences(
    replacingOccurrences(value, emphasisStartMarker, ""),
    emphasisEndMarker,
    "",
  );
}

function extractingEmphasis(value: string): {
  text: string;
  ranges: StringRange[];
} {
  let text = "";
  const rangeOffsets: CharacterRange[] = [];
  let rangeStart: number | null = null;

  for (const character of characters(value)) {
    if (character === emphasisStartMarker) {
      rangeStart = characterCount(text);
    } else if (character === emphasisEndMarker) {
      const count = characterCount(text);
      if (rangeStart !== null && rangeStart < count) {
        rangeOffsets.push({ lowerBound: rangeStart, upperBound: count });
      }
      rangeStart = null;
    } else {
      text += character;
    }
  }

  const view = characterView(text);
  const ranges = rangeOffsets.map((offset) => stringRange(view, offset));
  return { text, ranges };
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

function emphasizedSyllableRanges(value: string): StringRange[] {
  // Point the prose text like the corresponding psalm-tone score:
  // emphasize the lexical accent nearest each half-verse cadence.
  // Liturgical Latin marks polysyllabic stress with an acute accent;
  // unmarked endings fall back to the natural penultimate syllable.
  const view = characterView(value);
  const mediants: number[] = [];
  for (let index = 0; index < view.characters.length; index += 1) {
    if (view.characters[index] === "*") mediants.push(index);
  }
  if (mediants.length === 0) return [];

  const ranges: CharacterRange[] = [];
  let segmentStart = 0;
  for (const mediant of mediants) {
    const range = finalAccentRange(view, {
      lowerBound: segmentStart,
      upperBound: mediant,
    });
    if (range !== null) {
      ranges.push(range);
    }
    segmentStart = mediant + 1;
  }
  const range = finalAccentRange(view, {
    lowerBound: segmentStart,
    upperBound: view.characters.length,
  });
  if (range !== null) {
    ranges.push(range);
  }
  return ranges.map((characterRange) => stringRange(view, characterRange));
}

function finalAccentRange(
  value: CharacterView,
  segment: CharacterRange,
): CharacterRange | null {
  let finalLetter = -1;
  for (
    let index = segment.upperBound - 1;
    index >= segment.lowerBound;
    index -= 1
  ) {
    if (isLetter(value.characters[index])) {
      finalLetter = index;
      break;
    }
  }
  if (finalLetter < 0) {
    return null;
  }

  let wordStart = finalLetter;
  while (wordStart > segment.lowerBound) {
    const previous = wordStart - 1;
    if (!isLetter(value.characters[previous])) break;
    wordStart = previous;
  }
  const wordEnd = finalLetter + 1;
  const wordRange: CharacterRange = {
    lowerBound: wordStart,
    upperBound: wordEnd,
  };
  const nuclei = vowelNuclei(value, wordRange);
  if (nuclei.length === 0) return wordRange;

  const firstAccented = nuclei.findIndex((nucleus) =>
    containsAcuteAccent(
      value.characters.slice(nucleus.lowerBound, nucleus.upperBound).join(""),
    ),
  );
  const accentedNucleus =
    firstAccented >= 0 ? firstAccented : Math.max(0, nuclei.length - 2);
  const lowerBound =
    accentedNucleus === 0
      ? wordRange.lowerBound
      : syllableBoundary(
          value,
          nuclei[accentedNucleus - 1],
          nuclei[accentedNucleus],
        );
  const upperBound =
    accentedNucleus === nuclei.length - 1
      ? wordRange.upperBound
      : syllableBoundary(
          value,
          nuclei[accentedNucleus],
          nuclei[accentedNucleus + 1],
        );
  return { lowerBound, upperBound };
}

function vowelNuclei(
  value: CharacterView,
  wordRange: CharacterRange,
): CharacterRange[] {
  const result: CharacterRange[] = [];
  let index = wordRange.lowerBound;

  while (index < wordRange.upperBound) {
    const character = value.characters[index];
    if (!(
      isLatinVowel(character) && !isConsonantalVowel(value, index, wordRange)
    )) {
      index += 1;
      continue;
    }

    let upperBound = index + 1;
    if (upperBound < wordRange.upperBound) {
      const pair =
        unaccentedLowercase(character) +
        unaccentedLowercase(value.characters[upperBound]);
      if (latinDiphthongs.has(pair)) {
        upperBound += 1;
      }
    }
    result.push({ lowerBound: index, upperBound });
    index = upperBound;
  }
  return result;
}

function isConsonantalVowel(
  value: CharacterView,
  index: number,
  wordRange: CharacterRange,
): boolean {
  const vowel = unaccentedLowercase(value.characters[index]);
  const previous =
    index > wordRange.lowerBound
      ? unaccentedLowercase(value.characters[index - 1])
      : null;
  const nextIndex = index + 1;
  const nextIsVowel =
    nextIndex < wordRange.upperBound &&
    isLatinVowel(value.characters[nextIndex]);

  if (vowel === "i" && nextIsVowel) {
    return (
      index === wordRange.lowerBound ||
      (previous !== null &&
        ["a", "e", "i", "o", "u", "y", "æ", "œ"].includes(previous))
    );
  }
  return (
    vowel === "u" && (previous === "q" || (previous === "g" && nextIsVowel))
  );
}

function syllableBoundary(
  value: CharacterView,
  leftNucleus: CharacterRange,
  rightNucleus: CharacterRange,
): number {
  const consonantIndices: number[] = [];
  for (
    let index = leftNucleus.upperBound;
    index < rightNucleus.lowerBound;
    index += 1
  ) {
    consonantIndices.push(index);
  }
  if (consonantIndices.length === 0) {
    return rightNucleus.lowerBound;
  }
  if (!(consonantIndices.length > 1)) {
    return consonantIndices[0];
  }

  const lastPair = consonantIndices
    .slice(-2)
    .map((index) => unaccentedLowercase(value.characters[index]))
    .join("");
  if (inseparableConsonantPairs.has(lastPair)) {
    return lastPairStart(consonantIndices);
  }
  return consonantIndices[consonantIndices.length - 1];
}

function lastPairStart(indices: readonly number[]): number {
  return indices[indices.length - 2];
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

// Swift's private `Character` extension.

function isLatinVowel(character: string): boolean {
  return ["a", "e", "i", "o", "u", "y", "æ", "œ"].includes(
    unaccentedLowercase(character),
  );
}

function unaccentedLowercase(character: string): string {
  return folding(character, {
    caseInsensitive: true,
    diacriticInsensitive: true,
  }).toLowerCase();
}

// Swift's private `Substring` extension.

function containsAcuteAccent(substring: string): boolean {
  return (
    substring.includes("\u{301}") ||
    substring.normalize("NFD").includes("\u{301}")
  );
}

export const PsalmTextFormatter = {
  missingTranslationPlaceholder,
  emphasisStartMarker,
  emphasisEndMarker,
  lines,
  isSetVerseByLine,
  removingEmphasisMarkers,
  scriptureVerseNumber,
  emphasizedSyllableRanges,
  scriptureParagraphs,
  strippingScriptureReference,
  strippingVersePrefix,
};
