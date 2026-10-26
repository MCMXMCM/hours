// Swift and Foundation string behaviour that search relies on, beyond what
// `@/core/swiftString.ts`, `@/core/notation/strings.ts`, and
// `@/reader/presentation/strings.ts` supply. Each helper names the Swift it
// stands for. The behaviour was measured with Swift 6.3 against the macOS 26
// Foundation, the generation the app's iOS 26 deployment target runs on.

import * as SwiftString from "@/core/swiftString.ts";
import * as Strings from "@/reader/presentation/strings.ts";

/**
 * Swift compares, hashes, and searches Strings by canonical equivalence;
 * JavaScript does so by code unit. Two strings in one normal form are
 * canonically equivalent exactly when they are identical, so a comparison
 * ported from Swift is made on what this returns.
 */
export function canonical(value: string): string {
  return value.normalize("NFC");
}

/**
 * `String.<`, which orders by the Unicode scalars of the normal form. (A
 * JavaScript comparison orders by UTF-16 unit, and so places a scalar beyond
 * the basic plane before U+E000.)
 */
export function compare(lhs: string, rhs: string): number {
  const left = canonical(lhs);
  const right = canonical(rhs);
  let leftIndex = 0;
  let rightIndex = 0;
  while (leftIndex < left.length && rightIndex < right.length) {
    const leftScalar = left.codePointAt(leftIndex)!;
    const rightScalar = right.codePointAt(rightIndex)!;
    if (leftScalar !== rightScalar) return leftScalar < rightScalar ? -1 : 1;
    leftIndex += leftScalar > 0xffff ? 2 : 1;
    rightIndex += rightScalar > 0xffff ? 2 : 1;
  }
  if (leftIndex < left.length) return 1;
  return rightIndex < right.length ? -1 : 0;
}

/**
 * `hasPrefix(_:)` for strings in canonical form: the prefix's Characters
 * stand first, so it never ends inside one. (`SwiftString.hasPrefix` looks
 * only for a combining mark after the prefix; a joiner or an emoji modifier
 * extends a Character as well.)
 */
export function hasPrefix(value: string, prefix: string): boolean {
  return (
    value.startsWith(prefix) &&
    Strings.isCharacterBoundary(value, prefix.length)
  );
}

// NSString declines a match that the next scalar would extend. Its table is
// Grapheme_Extend together with the emoji modifiers, as
// `@/core/notation/strings.ts` records for the literal search; the search
// that disregards case keeps the same table.
const extendsPrecedingScalar = "[\\p{Grapheme_Extend}\\p{Emoji_Modifier}]";

const caseInsensitivePatterns = new Map<string, RegExp>();

/**
 * `replacingOccurrences(of:with:options: .caseInsensitive)` for a target of
 * one letter that has no canonical decomposition, such as U+00E6.
 *
 * The NSString search compares case foldings, so the capital is replaced as
 * well. It matches whole composed characters: neither the letter with a
 * combining mark after it nor a precomposed letter that carries a mark
 * (U+01FD, the ligature with an acute accent) is an occurrence.
 */
export function replacingOccurrencesCaseInsensitive(
  value: string,
  target: string,
  replacement: string,
): string {
  let pattern = caseInsensitivePatterns.get(target);
  if (pattern === undefined) {
    // The letter's two cases are written out. Under the `i` flag the class
    // that follows would disregard case as well, and U+0345, which extends,
    // would then stand for the Greek iota it folds to.
    const cases = [
      ...new Set([target, target.toLowerCase(), target.toUpperCase()]),
    ].map(SwiftString.escapedPattern);
    pattern = new RegExp(
      `(?:${cases.join("|")})(?!${extendsPrecedingScalar})`,
      "gu",
    );
    caseInsensitivePatterns.set(target, pattern);
  }
  return value.replace(pattern, () => replacement);
}

// Scalars each of which is a Character by itself beside another of them:
// nothing here extends, prepends, or joins, and CR is left out so that no
// CR-LF pair forms. (The set `@/reader/presentation/strings.ts` uses.) A
// string of them has one UTF-16 unit to a Character.
const plainCharactersOnly =
  /^[\u{0}-\u{C}\u{E}-\u{2FF}\u{1E00}-\u{1FFF}\u{2010}-\u{2027}\u{2030}-\u{205E}\u{2100}-\u{214F}\u{2700}-\u{27BF}]*$/u;

const whitespaceRun = /\p{White_Space}+/u;

/**
 * `split(whereSeparator: \.isWhitespace).joined(separator: " ")`.
 *
 * A Character is whitespace when its first scalar is, so a space that
 * carries a combining mark separates and takes the mark with it.
 */
export function collapsingWhitespace(value: string): string {
  if (plainCharactersOnly.test(value)) {
    return value
      .split(whitespaceRun)
      .filter((piece) => piece.length > 0)
      .join(" ");
  }
  return SwiftString.splitOmittingEmpty(value, SwiftString.isWhitespace).join(
    " ",
  );
}

/** `String.count`, without dividing a plain string into Characters. */
export function characterCount(value: string): number {
  return plainCharactersOnly.test(value)
    ? value.length
    : SwiftString.characterCount(value);
}

/** `String.prefix(_:)`, without dividing a plain string into Characters. */
export function prefix(value: string, count: number): string {
  return plainCharactersOnly.test(value)
    ? value.slice(0, Math.max(0, count))
    : SwiftString.prefix(value, count);
}

// `localizedStandardCompare(_:)` compares as the Finder sorts: disregarding
// case and width until all else is equal, and reading a run of digits as a
// number. Foundation walks the two strings together and hands what follows
// their first difference to ICU's collator for the current locale. The app
// is localized in English alone, so on a device that locale's language is
// always English, whatever its region; the collator here is English too,
// rather than the browser's own.
const finderCollator = new Intl.Collator("en", {
  usage: "sort",
  numeric: true,
  sensitivity: "variant",
});

function isASCIIDigit(unit: number): boolean {
  return unit >= 0x30 && unit <= 0x39;
}

function digitRunEnd(value: string, start: number): number {
  let end = start;
  while (end < value.length && isASCIIDigit(value.charCodeAt(end))) end += 1;
  return end;
}

function withoutLeadingZeros(digits: string): string {
  return digits.replace(/^0+(?=.)/, "");
}

// What Foundation's forced ordering returns for two strings the collator
// holds equal: the first place they differ decides. Two runs of ASCII digits
// of one value differ by their length, the shorter standing first ("2"
// before "02"); anything else differs by its scalar value, so that a
// decomposed letter stands before the precomposed one.
function forcedOrdering(lhs: string, rhs: string): number {
  let left = 0;
  let right = 0;
  while (left < lhs.length && right < rhs.length) {
    if (
      isASCIIDigit(lhs.charCodeAt(left)) &&
      isASCIIDigit(rhs.charCodeAt(right))
    ) {
      const leftEnd = digitRunEnd(lhs, left);
      const rightEnd = digitRunEnd(rhs, right);
      if (
        withoutLeadingZeros(lhs.slice(left, leftEnd)) ===
        withoutLeadingZeros(rhs.slice(right, rightEnd))
      ) {
        if (leftEnd - left !== rightEnd - right) {
          return leftEnd - left < rightEnd - right ? -1 : 1;
        }
        left = leftEnd;
        right = rightEnd;
        continue;
      }
    }
    const leftScalar = lhs.codePointAt(left)!;
    const rightScalar = rhs.codePointAt(right)!;
    if (leftScalar !== rightScalar) return leftScalar < rightScalar ? -1 : 1;
    left += leftScalar > 0xffff ? 2 : 1;
    right += rightScalar > 0xffff ? 2 : 1;
  }
  if (left < lhs.length) return 1;
  return right < rhs.length ? -1 : 0;
}

/**
 * `localizedStandardCompare(_:)` in an English locale: negative for
 * `.orderedAscending`, zero for `.orderedSame`, positive for
 * `.orderedDescending`. Only identical strings are the same.
 */
export function localizedStandardCompare(lhs: string, rhs: string): number {
  if (lhs === rhs) return 0;
  const order = finderCollator.compare(lhs, rhs);
  if (order !== 0) return order < 0 ? -1 : 1;
  return forcedOrdering(lhs, rhs);
}
