// Swift's string semantics, for code ported from the iOS app.
//
// Swift treats a String as a sequence of Characters (extended grapheme
// clusters) and compares by canonical equivalence; JavaScript treats it as
// UTF-16 code units and compares them literally. The corpus is normalized to
// NFC when it is loaded, which makes literal comparison agree with Swift's
// for everything but a boundary that falls inside a cluster (a combining
// mark with no precomposed form). The helpers below supply the rest.
//
// Regular expressions need separate care. Foundation's patterns are ICU:
// there `\w`, `\d`, and `\b` are Unicode-aware, while JavaScript's are ASCII
// even under the `u` flag. A ported pattern that uses them must use the
// classes exported here instead, or it will split words at every accented
// vowel.

const graphemeSegmenter = new Intl.Segmenter(undefined, {
  granularity: "grapheme",
});

/** A string's Characters, as Swift iterates them. */
export function characters(value: string): string[] {
  const result: string[] = [];
  for (const { segment } of graphemeSegmenter.segment(value)) {
    result.push(segment);
  }
  return result;
}

/** `String.count`. */
export function characterCount(value: string): number {
  let count = 0;
  for (const _ of graphemeSegmenter.segment(value)) count += 1;
  return count;
}

/** The corpus's canonical form. Idempotent. */
export function normalized(value: string): string {
  return value.normalize("NFC");
}

function firstScalar(character: string): string {
  const codePoint = character.codePointAt(0);
  return codePoint === undefined ? "" : String.fromCodePoint(codePoint);
}

// `Character.isLetter` is the Alphabetic property of the first scalar.
const alphabetic = /^\p{Alphabetic}$/u;
// `Character.isNumber` is a numeric type on the first scalar.
const numeric = /^\p{N}$/u;
const whitespace = /^\p{White_Space}$/u;
const punctuation = /^\p{P}$/u;
const decimalDigit = /^\p{Nd}$/u;

export function isLetter(character: string): boolean {
  return alphabetic.test(firstScalar(character));
}

export function isNumber(character: string): boolean {
  return numeric.test(firstScalar(character));
}

export function isWhitespace(character: string): boolean {
  return whitespace.test(firstScalar(character));
}

const newlines = new Set([
  "\r\n",
  "\n",
  "\r",
  String.fromCharCode(0x0b),
  String.fromCharCode(0x0c),
  String.fromCharCode(0x85),
  String.fromCharCode(0x2028),
  String.fromCharCode(0x2029),
]);

export function isNewline(character: string): boolean {
  return newlines.has(character);
}

export function isPunctuation(character: string): boolean {
  return punctuation.test(firstScalar(character));
}

/** `Character.isUppercase`: it changes when lowercased and not when uppercased. */
export function isUppercase(character: string): boolean {
  return (
    character !== character.toLowerCase() &&
    character === character.toUpperCase()
  );
}

/** `Character.isLowercase`: it changes when uppercased and not when lowercased. */
export function isLowercase(character: string): boolean {
  return (
    character !== character.toUpperCase() &&
    character === character.toLowerCase()
  );
}

/** `Character.wholeNumberValue` for the decimal digits. */
export function wholeNumberValue(character: string): number | null {
  if (!decimalDigit.test(character)) return null;
  const codePoint = character.codePointAt(0)!;
  // Every decimal-digit block runs 0–9 in order; find the block's zero.
  for (let zero = codePoint; zero >= codePoint - 9; zero -= 1) {
    if (!decimalDigit.test(String.fromCodePoint(zero))) {
      return codePoint - (zero + 1);
    }
    if (zero === 0) break;
  }
  return codePoint - (codePoint - 9);
}

export interface FoldingOptions {
  caseInsensitive?: boolean;
  diacriticInsensitive?: boolean;
}

// What Foundation's folding treats as a combining mark: the characters that
// extend a grapheme cluster. A spacing vowel sign and U+200D are not among
// them.
const foldingMark = /^[\p{Grapheme_Extend}\p{Emoji_Modifier}]$/u;
const foldingMarks = /[\p{Grapheme_Extend}\p{Emoji_Modifier}]/u;
// A base character with the marks written after it, or marks that open the
// string, the first of which then stands as the base.
const markedCluster =
  /(?:^|[^\p{Grapheme_Extend}\p{Emoji_Modifier}])[\p{Grapheme_Extend}\p{Emoji_Modifier}]+/gu;
// After a canonical decomposition, the marks of a Latin, Greek, or Cyrillic
// base (one below U+0510).
const marksAfterLowBase =
  /([\u{0}-\u{50F}])[\p{Grapheme_Extend}\p{Emoji_Modifier}]+/gu;
// Characters whose case folding is not their lowercase, or whose lowercase
// depends on what stands beside them.
const caseFoldingExceptions =
  /[\u{B5}\u{DF}\u{149}\u{17F}\u{1F0}\u{345}\u{370}-\u{3FF}\u{587}\u{1E96}-\u{1E9E}\u{1F00}-\u{1FFF}\u{FB00}-\u{FB17}]/u;

/**
 * The case folding of one scalar, as `.caseInsensitive` applies it: the
 * lowercase, or the full folding where that differs ("ß" to "ss", a final
 * sigma to a medial one).
 */
function caseFoldedScalar(scalar: string): string {
  const codePoint = scalar.codePointAt(0)!;
  // The dotless i folds to itself, as do the old forms of Cyrillic letters.
  if (codePoint === 0x131 || (codePoint >= 0x1c80 && codePoint <= 0x1c88)) {
    return scalar;
  }
  return scalar.toLowerCase().toUpperCase().toLowerCase();
}

function caseFolded(text: string): string {
  if (!caseFoldingExceptions.test(text)) return text.toLowerCase();
  let result = "";
  for (const scalar of text) result += caseFoldedScalar(scalar);
  return result;
}

// Characters no mark follows: each is folded by itself.
function foldingUnmarked(text: string, caseInsensitive: boolean): string {
  const stripped = text
    .normalize("NFD")
    .replace(marksAfterLowBase, "$1")
    .normalize("NFC");
  return caseInsensitive ? caseFolded(stripped) : stripped;
}

// A base and the marks after it, as Foundation folds a character cluster.
function foldingCluster(cluster: string, caseInsensitive: boolean): string {
  const scalars = Array.from(cluster);
  let character = scalars[0];
  // The replacement, once there is one; until then the text stands as it is.
  let produced: string[] | null = null;

  if (character.codePointAt(0)! >= 0x80) {
    const decomposed = Array.from(character.normalize("NFD"));
    if (
      (decomposed.length > 1 || decomposed[0] !== character) &&
      decomposed[0].codePointAt(0)! < 0x510
    ) {
      character = decomposed[0];
      produced = [character];
    }
  }
  if (caseInsensitive) {
    const folded = caseFoldedScalar(character);
    if (folded !== character) {
      const filtersMarks = character.codePointAt(0)! < 0x510;
      const foldedScalars = Array.from(folded);
      produced = foldedScalars.filter(
        (scalar) => !(filtersMarks && foldingMark.test(scalar)),
      );
      character = foldedScalars[foldedScalars.length - 1];
    }
  }

  // A base below U+0510 loses every mark. Any other keeps its marks, save a
  // first mark that is itself below U+0510.
  let keepsMarks = !(character.codePointAt(0)! < 0x510);
  let index = 1;
  if (produced === null && keepsMarks) {
    if (index < scalars.length) {
      produced = [character];
      if (scalars[index].codePointAt(0)! > 0x50f) {
        produced.push(...Array.from(scalars[index].normalize("NFD")));
      }
      index += 1;
    } else {
      keepsMarks = false;
    }
  }
  for (; index < scalars.length; index += 1) {
    if (keepsMarks) {
      produced = (produced ?? [character]).concat(
        Array.from(scalars[index].normalize("NFD")),
      );
    } else if (produced === null) {
      produced = [character];
    }
  }
  if (produced === null) return cluster;
  return prioritySorted(produced).join("");
}

// Whether a mark has combining class zero. One that decomposes has; of the
// rest, canonical ordering moves every other before U+0345, whose class is
// the highest.
function isStarter(mark: string): boolean {
  if (mark.normalize("NFD") !== mark) return true;
  const pair = "\u{345}" + mark;
  return mark !== "\u{345}" && pair.normalize("NFD") === pair;
}

// Foundation sorts the marks that end a folded cluster by combining class,
// those of class zero first; canonical ordering would leave these in place.
function prioritySorted(scalars: string[]): string[] {
  let start = scalars.length - 1;
  while (start > 0 && foldingMark.test(scalars[start])) start -= 1;
  const run = scalars.slice(start);
  if (run.length < 2) return scalars;
  const starters: string[] = [];
  let others = "";
  run.forEach((scalar, index) => {
    if ((index === 0 && !foldingMark.test(scalar)) || isStarter(scalar)) {
      starters.push(scalar);
    } else {
      others += scalar;
    }
  });
  return scalars
    .slice(0, start)
    .concat(starters, Array.from(others.normalize("NFD")));
}

/**
 * `String.folding(options:locale:)`, for a string in NFC and a locale without
 * casing rules of its own.
 *
 * Case folding is Unicode's full folding ("ß" becomes "ss"), which for the
 * Latin of the Office is lowercasing. Diacritic folding is not the removal of
 * every combining mark. Foundation folds one character cluster at a time: a
 * base below U+0510 (Latin, Greek, Cyrillic) is reduced to the first scalar of
 * its canonical decomposition and loses the marks written after it, so "é"
 * becomes "e" while "æ" and "ø", which do not decompose, are unchanged. A
 * base from U+0510 upward is left composed and keeps its marks, save that a
 * first mark below U+0510 is dropped: U+2719 keeps a U+FE0E after it, but
 * U+2123 loses a U+0301.
 */
export function folding(value: string, options: FoldingOptions): string {
  const caseInsensitive = options.caseInsensitive === true;
  if (!options.diacriticInsensitive) {
    return caseInsensitive ? caseFolded(value) : value;
  }
  if (!foldingMarks.test(value)) return foldingUnmarked(value, caseInsensitive);
  let result = "";
  let copied = 0;
  for (const match of value.matchAll(markedCluster)) {
    result +=
      foldingUnmarked(value.slice(copied, match.index), caseInsensitive) +
      foldingCluster(match[0], caseInsensitive);
    copied = match.index + match[0].length;
  }
  return result + foldingUnmarked(value.slice(copied), caseInsensitive);
}

// `CharacterSet.whitespacesAndNewlines`: general category Z, U+0009–U+000D,
// U+0085, and the zero-width space, which Foundation's sets still hold.
// Unlike `String.prototype.trim`, it leaves U+FEFF in place.
const leadingWhitespaceAndNewlines = /^[\p{Z}\u0009-\u000D\u0085\u200B]+/u;
const trailingWhitespaceAndNewlines = /[\p{Z}\u0009-\u000D\u0085\u200B]+$/u;
const leadingWhitespace = /^[\p{Zs}\u0009\u200B]+/u;
const trailingWhitespace = /[\p{Zs}\u0009\u200B]+$/u;

/** `trimmingCharacters(in: .whitespacesAndNewlines)`. */
export function trimmingWhitespaceAndNewlines(value: string): string {
  return value
    .replace(leadingWhitespaceAndNewlines, "")
    .replace(trailingWhitespaceAndNewlines, "");
}

/** `trimmingCharacters(in: .whitespaces)`. */
export function trimmingWhitespace(value: string): string {
  return value.replace(leadingWhitespace, "").replace(trailingWhitespace, "");
}

/** `trimmingCharacters(in:)` for an explicit set of Characters. */
export function trimmingCharacters(
  value: string,
  isMember: (character: string) => boolean,
): string {
  const all = characters(value);
  let start = 0;
  let end = all.length;
  while (start < end && isMember(all[start])) start += 1;
  while (end > start && isMember(all[end - 1])) end -= 1;
  return all.slice(start, end).join("");
}

const combiningMark = /^\p{M}/u;

/** `hasPrefix`, which never matches part of a Character. */
export function hasPrefix(value: string, prefix: string): boolean {
  if (!value.startsWith(prefix)) return false;
  return !combiningMark.test(value.slice(prefix.length));
}

/** `hasSuffix`, which never matches part of a Character. */
export function hasSuffix(value: string, suffix: string): boolean {
  if (!value.endsWith(suffix)) return false;
  return !combiningMark.test(suffix);
}

/**
 * `split(separator:)` and `split(whereSeparator:)`, which omit empty
 * subsequences. (`components(separatedBy:)` keeps them, as
 * `String.prototype.split` does.)
 */
export function splitOmittingEmpty(
  value: string,
  isSeparator: (character: string) => boolean,
): string[] {
  const result: string[] = [];
  let current = "";
  for (const character of characters(value)) {
    if (isSeparator(character)) {
      if (current.length > 0) result.push(current);
      current = "";
    } else {
      current += character;
    }
  }
  if (current.length > 0) result.push(current);
  return result;
}

/** `String.prefix(_:)`, counted in Characters. */
export function prefix(value: string, count: number): string {
  return characters(value).slice(0, Math.max(0, count)).join("");
}

/** `String.dropFirst(_:)`, counted in Characters. */
export function dropFirst(value: string, count = 1): string {
  return characters(value).slice(Math.max(0, count)).join("");
}

/** `String.dropLast(_:)`, counted in Characters. */
export function dropLast(value: string, count = 1): string {
  const all = characters(value);
  return all.slice(0, Math.max(0, all.length - count)).join("");
}

/** `String.suffix(_:)`, counted in Characters. */
export function suffix(value: string, count: number): string {
  const all = characters(value);
  return all.slice(Math.max(0, all.length - count)).join("");
}

/** `String.first`. */
export function first(value: string): string | null {
  for (const { segment } of graphemeSegmenter.segment(value)) return segment;
  return null;
}

/** `String.last`. */
export function last(value: string): string | null {
  const all = characters(value);
  return all.length > 0 ? all[all.length - 1] : null;
}

/** `caseInsensitiveCompare(_:) == .orderedSame`. */
export function equalsIgnoringCase(lhs: string, rhs: string): boolean {
  return (
    folding(lhs, { caseInsensitive: true }) ===
    folding(rhs, { caseInsensitive: true })
  );
}

/**
 * Sources for ICU's Unicode-aware classes, for use inside a `u`-flagged
 * JavaScript pattern. `icuWordBoundary` stands where a Foundation pattern
 * writes `\b`; `icuWord` and `icuDigit` are character-class bodies for
 * `\w` and `\d`.
 */
export const icuWord = "\\p{Alphabetic}\\p{M}\\p{Nd}\\p{Pc}\\u200C\\u200D";
export const icuDigit = "\\p{Nd}";

// ICU's `\b` passes over combining marks and format characters: the place
// before one is never a boundary, and the character that decides the other
// side is the nearest before it that is neither. (So there is a boundary
// between U+FE0E and a digit that follows it, though a mark is otherwise
// part of a word.)
const icuIgnorable = "[\\p{Grapheme_Extend}\\p{Cf}]";
const icuWordCharacter = `(?!${icuIgnorable})[${icuWord}]`;
export const icuWordBoundary = `(?:(?<=${icuWordCharacter}${icuIgnorable}*)(?!${icuIgnorable})(?![${icuWord}])|(?<!${icuWordCharacter}${icuIgnorable}*)(?=${icuWordCharacter}))`;

/** Escapes a literal for use in a pattern, as `NSRegularExpression.escapedPattern(for:)`. */
export function escapedPattern(literal: string): string {
  return literal.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
