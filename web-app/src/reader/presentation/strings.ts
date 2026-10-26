// Swift and Foundation string behaviour the reader's presentation relies on,
// beyond what `@/core/swiftString.ts` supplies.
//
// Foundation does not search a String in one way. Measured with Swift 6.3
// against the macOS 26 Foundation, which is the generation the app's iOS 26
// deployment target runs on:
//
//   `contains(_:)`, `range(of:)`, `components(separatedBy:)`
//       match whole Characters: an occurrence that begins or ends inside an
//       extended grapheme cluster is not one. `components(separatedBy: "\n")`
//       alone is literal, so that it still divides a CR-LF pair.
//   `replacingOccurrences(of:with:)`
//       matches literally, but never where a combining mark follows the
//       occurrence (the NSString search).
//   `replacingOccurrences(of:with:options: .literal)`
//       matches literally.
//   `replacingOccurrences(of:with:options: .regularExpression)`,
//   `NSRegularExpression`
//       are ICU regular expressions, matched by code point.
//   `range(of:options: .regularExpression)`
//       is Swift's native Regex, matched by Character: `$` is the end of the
//       string only, `\d` is `Character.isNumber`, and `\s` is
//       `Character.isWhitespace`. (That is for a native Swift string, as the
//       corpus decodes. One still bridged from an NSString and not ASCII is
//       searched by ICU instead; the two part only where a combining mark,
//       a CR-LF pair, or a final line terminator touches the match.)
//
// Every input is assumed to be in NFC, where canonical equivalence is
// identity; offsets are UTF-16 code units, as an NSRange's are.

import { icuWord, isNumber, isWhitespace } from "@/core/swiftString.ts";

const graphemeSegmenter = new Intl.Segmenter(undefined, {
  granularity: "grapheme",
});

/** A range of a string in UTF-16 offsets, as `String.prototype.slice` takes them. */
export interface StringRange {
  readonly lowerBound: number;
  readonly upperBound: number;
}

// Code units whose scalar is always a Character by itself beside another of
// them: nothing here extends, prepends, or joins, and only CR-LF pairs.
function isPlainUnit(unit: number): boolean {
  return (
    unit < 0x300 ||
    (unit >= 0x1e00 && unit <= 0x1fff) ||
    (unit >= 0x2010 && unit <= 0x2027) ||
    (unit >= 0x2030 && unit <= 0x205e) ||
    (unit >= 0x2100 && unit <= 0x214f) ||
    (unit >= 0x2700 && unit <= 0x27bf)
  );
}

// The same scalars as `isPlainUnit`, less CR: a string of them has one scalar
// to a Character.
const plainCharactersOnly =
  /^[\u{0}-\u{C}\u{E}-\u{2FF}\u{1E00}-\u{1FFF}\u{2010}-\u{2027}\u{2030}-\u{205E}\u{2100}-\u{214F}\u{2700}-\u{27BF}]*$/u;

/** Whether an offset falls between two Characters rather than inside one. */
export function isCharacterBoundary(value: string, offset: number): boolean {
  if (offset <= 0 || offset >= value.length) return true;
  const before = value.charCodeAt(offset - 1);
  const after = value.charCodeAt(offset);
  if (isPlainUnit(before) && isPlainUnit(after)) {
    return !(before === 0x0d && after === 0x0a);
  }
  return graphemeSegmenter.segment(value).containing(offset)!.index === offset;
}

/** `String.last`, without dividing the whole string into Characters. */
export function lastCharacter(value: string): string | null {
  if (value.length === 0) return null;
  const unit = value.charCodeAt(value.length - 1);
  if (
    isPlainUnit(unit) &&
    (value.length === 1 || isPlainUnit(value.charCodeAt(value.length - 2))) &&
    !(unit === 0x0a && value.charCodeAt(value.length - 2) === 0x0d)
  ) {
    return value[value.length - 1];
  }
  return graphemeSegmenter.segment(value).containing(value.length - 1)!.segment;
}

/**
 * `firstIndex(where:)` over a string's Characters: the first Character the
 * predicate accepts, with its offset.
 */
export function firstCharacter(
  value: string,
  predicate: (character: string) => boolean,
): { readonly offset: number; readonly character: string } | null {
  for (const { segment, index } of graphemeSegmenter.segment(value)) {
    if (predicate(segment)) return { offset: index, character: segment };
  }
  return null;
}

/**
 * `range(of:)` with no options: the first occurrence made of whole
 * Characters, at or after `from` (itself a Character boundary).
 */
export function rangeOf(
  value: string,
  target: string,
  from = 0,
): StringRange | null {
  if (target.length === 0) return null;
  let index = value.indexOf(target, from);
  while (index >= 0) {
    const end = index + target.length;
    if (isCharacterBoundary(value, index) && isCharacterBoundary(value, end)) {
      return { lowerBound: index, upperBound: end };
    }
    index = value.indexOf(target, index + 1);
  }
  return null;
}

/** `contains(_:)` for a string argument. An empty string is never contained. */
export function contains(value: string, other: string): boolean {
  return rangeOf(value, other) !== null;
}

/** `components(separatedBy:)` for a string separator. */
export function componentsSeparatedBy(
  value: string,
  separator: string,
): string[] {
  // Foundation keeps a lone "\n" literal, so that it divides "\r\n".
  if (separator === "\n") return value.split("\n");
  const result: string[] = [];
  let searchStart = 0;
  while (searchStart < value.length) {
    const range = rangeOf(value, separator, searchStart);
    if (range === null) break;
    result.push(value.slice(searchStart, range.lowerBound));
    searchStart = range.upperBound;
  }
  result.push(value.slice(searchStart));
  return result;
}

const graphemeExtend = /^\p{Grapheme_Extend}/u;

/**
 * `replacingOccurrences(of:with:)` with no options. The NSString search it
 * uses is literal, save that an occurrence a combining mark follows is not
 * one: "j" is not replaced in "j" + U+0301.
 */
export function replacingOccurrences(
  value: string,
  target: string,
  replacement: string,
): string {
  if (target.length === 0) return value;
  let index = value.indexOf(target);
  if (index < 0) return value;
  let result = "";
  let copied = 0;
  while (index >= 0) {
    const end = index + target.length;
    if (
      end < value.length &&
      value.charCodeAt(end) >= 0x300 &&
      graphemeExtend.test(String.fromCodePoint(value.codePointAt(end)!))
    ) {
      index = value.indexOf(target, index + 1);
      continue;
    }
    result += value.slice(copied, index) + replacement;
    copied = end;
    index = value.indexOf(target, end);
  }
  return result + value.slice(copied);
}

/** `replacingOccurrences(of:with:options: .literal)`. */
export function replacingLiteralOccurrences(
  value: string,
  target: string,
  replacement: string,
): string {
  if (target.length === 0) return value;
  return value.split(target).join(replacement);
}

// `CharacterSet.alphanumerics`: general categories L*, M*, and N*.
const notAlphanumeric = /[^\p{L}\p{M}\p{N}]/u;

/** `components(separatedBy: CharacterSet.alphanumerics.inverted)`. */
export function componentsSeparatedByNonAlphanumerics(value: string): string[] {
  return value.split(notAlphanumeric);
}

// `CharacterSet.newlines`: U+000A through U+000D, U+0085, U+2028, and U+2029.
const newline = /[\n\u{B}\f\r\u{85}\u{2028}\u{2029}]/u;

/** `components(separatedBy: .newlines)`. */
export function componentsSeparatedByNewlines(value: string): string[] {
  return value.split(newline);
}

const integerLiteral = /^[+-]?[0-9]+$/;
const greatestInt = BigInt("9223372036854775807");
const leastInt = BigInt("-9223372036854775808");

/**
 * `Int(_:)` for a string: an optional sign and ASCII digits, nothing else,
 * and nil beyond 64 bits.
 */
export function swiftInt(text: string): number | null {
  if (!integerLiteral.test(text)) return null;
  const value = BigInt(text.startsWith("+") ? text.slice(1) : text);
  if (value > greatestInt || value < leastInt) return null;
  return Number(value);
}

/** `Sequence.min(by:)`: the first of the least elements. */
export function minBy<Element>(
  elements: readonly Element[],
  areInIncreasingOrder: (lhs: Element, rhs: Element) => boolean,
): Element | null {
  if (elements.length === 0) return null;
  let result = elements[0];
  for (let index = 1; index < elements.length; index += 1) {
    if (areInIncreasingOrder(elements[index], result)) result = elements[index];
  }
  return result;
}

/** `Sequence.max(by:)`: the first of the greatest elements. */
export function maxBy<Element>(
  elements: readonly Element[],
  areInIncreasingOrder: (lhs: Element, rhs: Element) => boolean,
): Element | null {
  if (elements.length === 0) return null;
  let result = elements[0];
  for (let index = 1; index < elements.length; index += 1) {
    if (areInIncreasingOrder(result, elements[index])) result = elements[index];
  }
  return result;
}

// --- ICU regular expressions ------------------------------------------------
//
// For `replacingOccurrences(of:with:options: .regularExpression)` and
// `NSRegularExpression`. These are sources for a `u`-flagged pattern compiled
// without the `m` flag, so that `^` and `$` in it mean the ends of the input.

/** Class body for ICU's `\s`, which is the White_Space property. */
export const icuWhitespace = "\\p{White_Space}";

// ICU's `\b`, exactly; it is defined beside `icuWord`.
export { icuWordBoundary } from "@/core/swiftString.ts";

const icuLineTerminators = "\\n\\u{B}\\f\\r\\u{85}\\u{2028}\\u{2029}";

/**
 * ICU's `$` outside multiline mode: the end of the input, or the place before
 * a line terminator that ends it.
 */
export const icuEnd = `(?:$|(?=\\r\\n$)|(?<!\\r)(?=\\n$)|(?=[\\u{B}\\f\\r\\u{85}\\u{2028}\\u{2029}]$))`;

/**
 * ICU's `^` under `(?m)`: the start of the input, or the place after a line
 * terminator that does not end it (and never between a CR and its LF).
 */
export const icuLineStart = `(?:^|(?<=[${icuLineTerminators}])(?!$)(?!(?<=\\r)\\n))`;

/** ICU's `$` under `(?m)`: the end of the input or of any line. */
export const icuLineEnd = `(?:$|(?=[\\u{B}\\f\\r\\u{85}\\u{2028}\\u{2029}])|(?<!\\r)(?=\\n))`;

// --- Swift Regex ------------------------------------------------------------
//
// For `range(of:options: .regularExpression)`. Swift's Regex consumes whole
// Characters, which a JavaScript pattern cannot; so the pattern is matched
// against the string's Characters, each written as one scalar. A Character of
// one scalar is itself. One of several scalars can equal no literal and lie
// in no range, and is replaced by a stand-in that says only what `\d`, `\s`,
// and a negated class need to know of it.

const numberCharacter = "\u{E000}";
const whitespaceCharacter = "\u{E001}";
const otherCharacter = "\u{E002}";

/** Class body for Swift Regex's `\d`, which is `Character.isNumber`. */
export const swiftDigit = `\\p{N}${numberCharacter}`;

/** Class body for Swift Regex's `\s`, which is `Character.isWhitespace`. */
export const swiftWhitespace = `\\p{White_Space}${whitespaceCharacter}`;

function isSingleScalar(character: string): boolean {
  return (
    character.length === 1 ||
    (character.length === 2 && character.codePointAt(0)! > 0xffff)
  );
}

// A case-insensitive Swift Regex compares each Character's lowercase mapping.
function lowercasedCharacter(character: string): string {
  const lowered = character.toLowerCase();
  return isSingleScalar(lowered) ? lowered : otherCharacter;
}

function characterAlphabet(
  value: string,
  caseInsensitive: boolean,
): { readonly text: string; readonly offsets: readonly number[] | null } {
  if (plainCharactersOnly.test(value)) {
    if (!caseInsensitive) return { text: value, offsets: null };
    let text = "";
    for (let index = 0; index < value.length; index += 1) {
      text += lowercasedCharacter(value[index]);
    }
    return { text, offsets: null };
  }

  let text = "";
  const offsets: number[] = [];
  for (const { segment, index } of graphemeSegmenter.segment(value)) {
    let character: string;
    if (isSingleScalar(segment)) {
      if (
        segment === numberCharacter ||
        segment === whitespaceCharacter ||
        segment === otherCharacter
      ) {
        character = otherCharacter;
      } else {
        character = caseInsensitive ? lowercasedCharacter(segment) : segment;
      }
    } else {
      const first = String.fromCodePoint(segment.codePointAt(0)!);
      character = isNumber(first)
        ? numberCharacter
        : isWhitespace(first)
          ? whitespaceCharacter
          : otherCharacter;
    }
    offsets[text.length] = index;
    text += character;
  }
  offsets[text.length] = value.length;
  return { text, offsets };
}

/**
 * `range(of:options: .regularExpression)`, with `.caseInsensitive` on request:
 * the first match of a pattern written for the Character alphabet above. A
 * case-insensitive pattern must itself be in lowercase.
 */
export function firstMatch(
  expression: RegExp,
  value: string,
  caseInsensitive = false,
): StringRange | null {
  const { text, offsets } = characterAlphabet(value, caseInsensitive);
  const match = expression.exec(text);
  if (match === null) return null;
  const lowerBound = match.index;
  const upperBound = match.index + match[0].length;
  return offsets === null
    ? { lowerBound, upperBound }
    : { lowerBound: offsets[lowerBound], upperBound: offsets[upperBound] };
}
