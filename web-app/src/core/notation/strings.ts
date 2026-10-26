// String behaviour of Foundation and the standard library that the GABC
// parser needs beyond the shared helpers in `@/core/swiftString.ts`.
//
// gabc-parser's `Sources/GABCParser/GregorianNotation.swift` reaches its strings through several
// mechanisms, and they disagree about a Character of more than one scalar
// (a sign followed by a combining mark, for example):
//
// - The standard library (`==`, `firstIndex(of:)`, `filter`, `split`) and
//   Foundation's literal `range(of:)` and `contains(_:)` compare whole
//   Characters.
// - Foundation's literal `replacingOccurrences(of:with:)` is NSString's. It
//   searches UTF-16, and gives up a match only where the scalar that follows
//   would extend it.
// - `replacingOccurrences(of:with:options: .regularExpression)` is ICU's,
//   which matches scalar by scalar and knows nothing of Characters. A plain
//   `u`-flagged JavaScript pattern stands for it.
// - `range(of:options: .regularExpression)` is not ICU's but Swift's own
//   Regex, which matches Character by Character.
//
// Each helper names the Swift it stands for. The behaviour was observed with
// Swift 6.3 and Foundation on macOS 26; the app's deployment target is
// iOS 26.

import { characters } from "@/core/swiftString.ts";

/** A span of a string in UTF-16 offsets, as `String.prototype.slice` takes them. */
export interface StringRange {
  readonly lowerBound: number;
  readonly upperBound: number;
}

/**
 * `range(of:)` for a literal: the first place where `other`'s Characters
 * stand in order, or `null`. It never matches part of a Character, so "%%"
 * is not found where a combining mark follows the second sign.
 */
export function range(value: string, other: string): StringRange | null {
  if (other.length === 0 || !value.includes(other)) return null;
  const all = characters(value);
  const sought = characters(other);
  let offset = 0;
  for (let start = 0; start + sought.length <= all.length; start += 1) {
    if (sought.every((character, index) => all[start + index] === character)) {
      return { lowerBound: offset, upperBound: offset + other.length };
    }
    offset += all[start].length;
  }
  return null;
}

/** `StringProtocol.contains(_:)` for a literal, which is `range(of:) != nil`. */
export function contains(value: string, other: string): boolean {
  return range(value, other) !== null;
}

/**
 * `hasSuffix(_:)` for a literal: whether `other`'s Characters end the string.
 * A sign followed by a combining mark is another Character, and no suffix.
 */
export function hasSuffix(value: string, other: string): boolean {
  if (other.length === 0) return true;
  if (!value.endsWith(other)) return false;
  const all = characters(value);
  const sought = characters(other);
  if (sought.length > all.length) return false;
  const start = all.length - sought.length;
  return sought.every((character, index) => all[start + index] === character);
}

/** `String.filter(_:)`, whose result is a String and so is divided into Characters anew. */
export function filter(
  value: string,
  isIncluded: (character: string) => boolean,
): string {
  return characters(value).filter(isIncluded).join("");
}

/** `unicodeScalars.count`. */
export function unicodeScalarCount(value: string): number {
  let count = 0;
  for (const _ of value) count += 1;
  return count;
}

// NSString declines a literal match that the next scalar would extend. Its
// table is Grapheme_Extend together with the emoji modifiers; it is not the
// whole of what joins a Character (a spacing mark or a joiner does not stop
// it), nor does it keep CR LF together.
const extendsPrecedingScalar = /[\p{Grapheme_Extend}\p{Emoji_Modifier}]/uy;

/**
 * `replacingOccurrences(of:with:)` for a literal target that has no canonical
 * equivalent but itself. "{" before a combining acute is left in place, while
 * the line feed of a CR LF pair is replaced.
 */
export function replacingOccurrences(
  value: string,
  target: string,
  replacement: string,
): string {
  if (target.length === 0) return value;
  let result = "";
  let copied = 0;
  let from = 0;
  for (;;) {
    const found = value.indexOf(target, from);
    if (found === -1) break;
    const end = found + target.length;
    extendsPrecedingScalar.lastIndex = end;
    if (extendsPrecedingScalar.test(value)) {
      from = found + 1;
      continue;
    }
    result += value.slice(copied, found) + replacement;
    copied = end;
    from = end;
  }
  return copied === 0 ? value : result + value.slice(copied);
}

// Stands for any Character of more than one UTF-16 unit. It is not a
// character that either pattern in the parser names.
const compoundCharacter = "\u{FFFD}";

/**
 * `range(of: pattern, options: .regularExpression) != nil`.
 *
 * Swift's Regex matches by Character: a literal matches only a Character
 * equal to it, and a negated class matches any other whole Character. The
 * pattern is therefore tried against the string with every Character of
 * several units reduced to one unit that the pattern does not name. That is
 * sound only for a pattern built, as the parser's are, from single ASCII
 * literals and negated classes of them; it must carry neither the `g` nor
 * the `y` flag.
 */
export function hasRangeOfRegularExpression(
  value: string,
  pattern: RegExp,
): boolean {
  const byCharacter = characters(value)
    .map((character) =>
      character.length === 1 ? character : compoundCharacter,
    )
    .join("");
  return pattern.test(byCharacter);
}

// `CharacterSet.whitespacesAndNewlines` as Foundation holds it: general
// category Z, U+0009 to U+000D, U+0085, and also U+200B ZERO WIDTH SPACE,
// which is no longer of category Z and which
// `swiftString.trimmingWhitespaceAndNewlines` leaves in place.
const leadingWhitespaceAndNewlines = /^[\p{Z}\u{9}-\u{D}\u{85}\u{200B}]+/u;
const trailingWhitespaceAndNewlines = /[\p{Z}\u{9}-\u{D}\u{85}\u{200B}]+$/u;

/** `trimmingCharacters(in: .whitespacesAndNewlines)`, which trims scalars, not Characters. */
export function trimmingWhitespaceAndNewlines(value: string): string {
  return value
    .replace(leadingWhitespaceAndNewlines, "")
    .replace(trailingWhitespaceAndNewlines, "");
}

/**
 * `Int(_ description: String)`: ASCII digits with an optional sign, and
 * nothing else. (Swift also refuses a value beyond `Int`; none arises here.)
 */
export function int(description: string): number | null {
  if (!/^[+-]?[0-9]+$/.test(description)) return null;
  const value = Number.parseInt(description, 10);
  return value === 0 ? 0 : value;
}
