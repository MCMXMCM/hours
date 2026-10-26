// The GABC engraving parser, parallel to `GregorianScoreParserError`,
// `GregorianScoreParser`, `GregorianNeumeClassifier`, and
// `GregorianNeumeSegmenter` in gabc-parser's `Sources/GABCParser/GregorianNotation.swift`. A Swift
// private helper is a module-private function of the same name.
//
// Offsets. Every offset here (the `offset` of an error, and the bounds of a
// `GregorianSourceRange`) counts Characters, that is, extended grapheme
// clusters. It is neither a count of UTF-16 units nor of Unicode scalars: a
// vowel with a combining accent counts once, and so does CR LF. The origin is
// the start of the notation body, which is the text after the first `%%`
// with its line comments already removed. Swift settles the unit where it
// measures a notation group,
//
//     let groupOffset = body.distance(from: body.startIndex, to: notationStart)
//
// since `String.distance(from:to:)` counts Characters, and then adds to it an
// index into `Array(notation)`, an array of Characters. The body is therefore
// held below as its array of Characters, so that an index into the array is
// already the distance Swift computes.
//
// Comparison. Swift compares Characters and Strings by canonical
// equivalence; the comparisons below are literal. They agree for a score
// normalized to NFC, as the corpus is when it is loaded.

import type { ChantTimeline } from "@/core/models.ts";
import * as SwiftString from "@/core/swiftString.ts";
import {
  GregorianNotes,
  GregorianScores,
  type GregorianAccidental,
  type GregorianAccidentalMark,
  type GregorianClef,
  type GregorianDivision,
  type GregorianEpisemaPosition,
  type GregorianLiquescence,
  type GregorianLyricStyle,
  type GregorianNeume,
  type GregorianNeumeForm,
  type GregorianNotationElement,
  type GregorianNote,
  type GregorianNoteShape,
  type GregorianScore,
  type GregorianSourceRange,
} from "./model.ts";
import * as Strings from "./strings.ts";

type GregorianScoreParserErrorDetail =
  | { kind: "missingBody" }
  | { kind: "unterminatedNotation"; offset: number }
  | { kind: "invalidClef"; token: string; offset: number }
  | { kind: "unsupportedToken"; token: string; offset: number }
  | { kind: "tooManyNotationNotes"; offset: number }
  | { kind: "timelineMismatch"; expected: number; parsed: number }
  | { kind: "eventSyllableMismatch"; eventID: string };

function errorDescription(detail: GregorianScoreParserErrorDetail): string {
  switch (detail.kind) {
    case "missingBody":
      return "The GABC score does not contain a notation body.";
    case "unterminatedNotation":
      return `The GABC notation beginning at offset ${detail.offset} is not closed.`;
    case "invalidClef":
      return `Invalid clef ${detail.token} at offset ${detail.offset}.`;
    case "unsupportedToken":
      return `Unsupported GABC token ${detail.token} at offset ${detail.offset}.`;
    case "tooManyNotationNotes":
      return `The notation contains more notes than its compiled timeline near offset ${detail.offset}.`;
    case "timelineMismatch":
      return `The compiled timeline contains ${detail.expected} notes but the notation contains ${detail.parsed}.`;
    case "eventSyllableMismatch":
      return `Timeline event ${detail.eventID} is assigned to a different syllable than its neume.`;
  }
}

/**
 * One case of Swift's `GregorianScoreParserError`, named by `detail.kind` and
 * carrying that case's associated values. `message` is its
 * `errorDescription`.
 */
export class GregorianScoreParserError extends Error {
  readonly detail: GregorianScoreParserErrorDetail;

  constructor(detail: GregorianScoreParserErrorDetail) {
    super(errorDescription(detail));
    this.name = "GregorianScoreParserError";
    this.detail = detail;
  }
}

/** `GregorianNote.init`, with the defaults of its Swift parameters. */
export function makeGregorianNote(init: {
  readonly id: string;
  readonly pitch: number;
  readonly relativePitch: number;
  readonly shape: GregorianNoteShape;
  readonly accidental: GregorianAccidental | null;
  readonly hasMora: boolean;
  readonly hasEpisema: boolean;
  readonly moraCount?: number;
  readonly episemaPosition?: GregorianEpisemaPosition;
  readonly liquescence?: GregorianLiquescence;
  readonly isCavum?: boolean;
  readonly hasIctus?: boolean;
  readonly repetitionCount?: number;
  readonly sourceRange: GregorianSourceRange;
}): GregorianNote {
  return {
    id: init.id,
    pitch: init.pitch,
    relativePitch: init.relativePitch,
    shape: init.shape,
    accidental: init.accidental,
    hasMora: init.hasMora,
    hasEpisema: init.hasEpisema,
    moraCount: Math.max(init.moraCount ?? 0, init.hasMora ? 1 : 0),
    episemaPosition: init.episemaPosition ?? "above",
    liquescence: init.liquescence ?? "none",
    isCavum: init.isCavum ?? false,
    hasIctus: init.hasIctus ?? false,
    repetitionCount: Math.max(1, init.repetitionCount ?? 1),
    sourceRange: init.sourceRange,
  };
}

/**
 * `GregorianNeume.init`, with the defaults of its Swift parameters: a neume
 * given no form takes the one its notes classify as.
 */
export function makeGregorianNeume(init: {
  readonly id: string;
  readonly syllableID: string;
  readonly lyric: string;
  readonly lyricStyle?: GregorianLyricStyle;
  readonly startsWord: boolean;
  readonly notes: readonly GregorianNote[];
  readonly form?: GregorianNeumeForm | null;
  readonly sourceRange: GregorianSourceRange;
}): GregorianNeume {
  return {
    id: init.id,
    syllableID: init.syllableID,
    lyric: init.lyric,
    lyricStyle: init.lyricStyle ?? "regular",
    startsWord: init.startsWord,
    notes: init.notes,
    form: init.form ?? GregorianNeumeClassifier.classify(init.notes),
    sourceRange: init.sourceRange,
  };
}

type ParsedToken =
  | { readonly type: "clef"; readonly clef: GregorianClef }
  | {
      readonly type: "accidental";
      readonly accidental: GregorianAccidentalMark;
    }
  | { readonly type: "notes"; readonly notes: readonly ParsedNote[] }
  | { readonly type: "division"; readonly division: GregorianDivision }
  | { readonly type: "forcedBreak" };

interface ParsedNote {
  readonly pitch: number;
  readonly shape: GregorianNoteShape;
  readonly accidental: GregorianAccidental | null;
  readonly hasMora: boolean;
  readonly hasEpisema: boolean;
  readonly moraCount: number;
  readonly episemaPosition: GregorianEpisemaPosition;
  readonly liquescence: GregorianLiquescence;
  readonly isCavum: boolean;
  readonly hasIctus: boolean;
  readonly repetitionCount: number;
  readonly sourceRange: GregorianSourceRange;
}

export const GregorianScoreParser = {
  /** Throws a `GregorianScoreParserError`. */
  parse(gabc: string, timeline: ChantTimeline): GregorianScore {
    const bodyRange = Strings.range(gabc, "%%");
    if (bodyRange === null) {
      throw new GregorianScoreParserError({ kind: "missingBody" });
    }

    // The Characters of the body: an index into this array is the distance
    // from `body.startIndex` that Swift reports.
    const body = SwiftString.characters(
      gabc
        .slice(bodyRange.upperBound)
        // In GABC, a single percent sign begins a comment through the end
        // of its line. Preserve the newline so surrounding lyric fragments
        // cannot be joined accidentally.
        .replace(/%[^\r\n]*/gu, ""),
    );
    const elements: GregorianNotationElement[] = [];
    let cursor = 0;
    let eventIndex = 0;
    let sourceOffset = 0;
    // A word begins where a space stands before a group, and a clef or a
    // bar that stands there alone does not use the beginning up: in
    // "mus.(h.) (:)De(g)us" the bar ends one word and "De" begins the
    // next, though no space follows the bar. Notes without words are the
    // melisma of the syllable before them, and leave it a word unfinished.
    let wordStartIsPending = false;

    for (;;) {
      const open = body.indexOf("(", cursor);
      if (open === -1) break;
      const lyricSource = body.slice(cursor, open).join("");
      const close = body.indexOf(")", open);
      if (close === -1) {
        throw new GregorianScoreParserError({
          kind: "unterminatedNotation",
          offset: open,
        });
      }

      const notationStart = open + 1;
      const notation = body.slice(notationStart, close).join("");
      const groupOffset = notationStart;
      const lyric = cleanLyric(lyricSource);
      const parsedLyricStyle = lyricStyle(lyricSource);
      const sourceStartsWord = lyricStartsWord(
        lyricSource,
        elements.length === 0,
      );
      const startsWord =
        sourceStartsWord || (wordStartIsPending && lyric.length > 0);

      const parsed = parseNotationGroup(notation, groupOffset);
      const hasNotes = parsed.some((token) => token.type === "notes");
      if (lyric.length > 0 || hasNotes) {
        wordStartIsPending = false;
      } else if (sourceStartsWord && parsed.length > 0) {
        wordStartIsPending = true;
      }
      if (lyric.length > 0 && !hasNotes) {
        const displayLyric = standaloneLyricText(lyric);
        const lyricStart = cursor;
        const lyricEnd = open;
        elements.push({
          type: "lyricMark",
          lyricMark: {
            text: displayLyric,
            style: standaloneLyricStyle(displayLyric, parsedLyricStyle),
            startsWord,
            sourceRange: { lowerBound: lyricStart, upperBound: lyricEnd },
          },
        });
      }
      let appliedLyric = false;

      for (const token of parsed) {
        switch (token.type) {
          case "clef":
            elements.push({ type: "clef", clef: token.clef });
            break;
          case "accidental":
            elements.push({ type: "accidental", accidental: token.accidental });
            break;
          case "division":
            elements.push({ type: "division", division: token.division });
            break;
          case "forcedBreak":
            elements.push({ type: "forcedBreak" });
            break;
          case "notes": {
            const mappedNotes: GregorianNote[] = [];
            for (const note of token.notes) {
              if (!(eventIndex >= 0 && eventIndex < timeline.events.length)) {
                throw new GregorianScoreParserError({
                  kind: "tooManyNotationNotes",
                  offset: note.sourceRange.lowerBound,
                });
              }
              const event = timeline.events[eventIndex];
              mappedNotes.push(
                makeGregorianNote({
                  id: event.id,
                  pitch: note.pitch,
                  relativePitch: event.relativePitch,
                  shape: note.shape,
                  accidental: note.accidental,
                  hasMora: note.hasMora,
                  hasEpisema: note.hasEpisema,
                  moraCount: note.moraCount,
                  episemaPosition: note.episemaPosition,
                  liquescence: note.liquescence,
                  isCavum: note.isCavum,
                  hasIctus: note.hasIctus,
                  repetitionCount: note.repetitionCount,
                  sourceRange: note.sourceRange,
                }),
              );
              eventIndex += 1;
            }

            const first = mappedNotes.at(0);
            if (first === undefined) continue;
            const event = timeline.events[eventIndex - mappedNotes.length];
            const neumeLyric = appliedLyric ? "" : lyric;
            if (
              neumeLyric.length > 0 &&
              mappedNotes.some(
                (mapped) =>
                  timeline.events.find(
                    (candidate) => candidate.id === mapped.id,
                  )?.syllableID !== event.syllableID,
              )
            ) {
              throw new GregorianScoreParserError({
                kind: "eventSyllableMismatch",
                eventID: first.id,
              });
            }
            const segments = GregorianNeumeSegmenter.segment(mappedNotes);
            for (const [segmentIndex, segment] of segments.entries()) {
              const segmentFirst = segment.at(0);
              if (segmentFirst === undefined) continue;
              elements.push({
                type: "neume",
                neume: makeGregorianNeume({
                  id: segmentFirst.id,
                  syllableID: event.syllableID,
                  lyric: segmentIndex === 0 ? neumeLyric : "",
                  lyricStyle:
                    segmentIndex === 0 && neumeLyric.length > 0
                      ? parsedLyricStyle
                      : "regular",
                  startsWord:
                    segmentIndex === 0 && !appliedLyric ? startsWord : false,
                  notes: segment,
                  sourceRange: {
                    lowerBound:
                      segment.at(0)?.sourceRange.lowerBound ?? groupOffset,
                    upperBound:
                      segment.at(-1)?.sourceRange.upperBound ?? groupOffset,
                  },
                }),
              });
            }
            appliedLyric = true;
            break;
          }
        }
      }

      cursor = close + 1;
      sourceOffset = cursor;
    }

    if (eventIndex !== timeline.events.length) {
      throw new GregorianScoreParserError({
        kind: "timelineMismatch",
        expected: timeline.events.length,
        parsed: eventIndex,
      });
    }
    if (!(elements.length > 0 || timeline.events.length === 0)) {
      throw new GregorianScoreParserError({
        kind: "unsupportedToken",
        token: "empty score",
        offset: sourceOffset,
      });
    }
    return GregorianScores.make(elements);
  },
};

function parseNotationGroup(
  notation: string,
  baseOffset: number,
): ParsedToken[] {
  const characters = SwiftString.characters(notation);
  const result: ParsedToken[] = [];
  let currentNotes: ParsedNote[] = [];
  let index = 0;

  const flushNotes = () => {
    if (currentNotes.length > 0) {
      result.push({ type: "notes", notes: currentNotes });
      currentNotes = [];
    }
  };

  while (index < characters.length) {
    const character = characters[index];

    if (character === "[") {
      flushNotes();
      const close = characters.indexOf("]", index + 1);
      if (close !== -1) {
        index = close + 1;
      } else {
        index = characters.length;
      }
      continue;
    }

    if (SwiftString.isWhitespace(character) || character === "/") {
      flushNotes();
      index += 1;
      continue;
    }

    if (character === "!") {
      flushNotes();
      index += 1;
      continue;
    }

    const isFlatCClef =
      character === "c" &&
      index + 2 < characters.length &&
      characters[index + 1] === "b" &&
      SwiftString.isNumber(characters[index + 2]);
    if (
      (character === "c" || character === "f") &&
      index + 1 < characters.length &&
      (SwiftString.isNumber(characters[index + 1]) || isFlatCClef)
    ) {
      flushNotes();
      const lineIndex = index + (isFlatCClef ? 2 : 1);
      const token = characters.slice(index, lineIndex + 1).join("");
      const line = Strings.int(characters[lineIndex]);
      if (line === null || !(line >= 1 && line <= 4)) {
        throw new GregorianScoreParserError({
          kind: "invalidClef",
          token,
          offset: baseOffset + index,
        });
      }
      result.push({
        type: "clef",
        clef: {
          kind: character === "c" ? "c" : "f",
          line,
          flattensB: isFlatCClef,
        },
      });
      index = lineIndex + 1;
      continue;
    }

    if (
      character === ":" ||
      character === ";" ||
      character === "," ||
      character === "`"
    ) {
      flushNotes();
      if (
        character === ":" &&
        index + 1 < characters.length &&
        characters[index + 1] === ":"
      ) {
        result.push({ type: "division", division: "final" });
        index += 2;
      } else {
        let division: GregorianDivision;
        switch (character) {
          case ",":
          case "`":
            division = "minima";
            break;
          case ";":
            division = "minor";
            break;
          default:
            division = "major";
        }
        result.push({ type: "division", division });
        index += 1;
      }
      continue;
    }

    if (character === "z" || character === "Z") {
      flushNotes();
      result.push({ type: "forcedBreak" });
      index += 1;
      continue;
    }

    const pitch = pitchValue(character);
    if (pitch === null) {
      if (isIgnorableControl(character)) {
        index += 1;
        continue;
      }
      throw new GregorianScoreParserError({
        kind: "unsupportedToken",
        token: character,
        offset: baseOffset + index,
      });
    }

    const noteStart = index;
    if (index + 1 < characters.length) {
      const accidentalCharacter = characters[index + 1];
      let accidental: GregorianAccidental | null;
      switch (accidentalCharacter) {
        case "x":
          accidental = "flat";
          break;
        case "y":
          accidental = "natural";
          break;
        case "#":
          accidental = "sharp";
          break;
        default:
          accidental = null;
      }
      if (accidental !== null) {
        flushNotes();
        result.push({
          type: "accidental",
          accidental: {
            kind: accidental,
            pitch,
            sourceRange: {
              lowerBound: baseOffset + noteStart,
              upperBound: baseOffset + noteStart + 2,
            },
          },
        });
        index += 2;
        continue;
      }
    }
    index += 1;
    let suffix = "";
    while (index < characters.length) {
      const next = characters[index];
      if (next === "[") {
        const close = characters.indexOf("]", index + 1);
        if (close !== -1) {
          index = close + 1;
        } else {
          index = characters.length;
        }
        continue;
      }
      if (
        SwiftString.isWhitespace(next) ||
        next === "/" ||
        next === ":" ||
        next === ";" ||
        next === "," ||
        next === "`" ||
        next === "z" ||
        next === "Z" ||
        pitchValue(next) !== null ||
        ((next === "c" || next === "f") &&
          index + 1 < characters.length &&
          (SwiftString.isNumber(characters[index + 1]) ||
            (next === "c" &&
              index + 2 < characters.length &&
              characters[index + 1] === "b" &&
              SwiftString.isNumber(characters[index + 2]))))
      ) {
        break;
      }
      suffix += next;
      index += 1;
    }

    let liquescence: GregorianLiquescence;
    if (Strings.contains(suffix, "<")) {
      liquescence = "ascending";
    } else if (Strings.contains(suffix, ">")) {
      liquescence = "descending";
    } else if (Strings.contains(suffix, "~")) {
      liquescence = "small";
    } else {
      liquescence = "none";
    }

    // A pitch letter whose signs end in `+` is a custos, as in
    // Exsurge: it stands apart from the notes on either side.
    const isCustos = Strings.hasSuffix(suffix, "+");

    let shape: GregorianNoteShape;
    if (isCustos) {
      shape = "custos";
    } else if (Strings.contains(suffix, "w") || Strings.contains(suffix, "W")) {
      shape = "quilisma";
    } else if (
      Strings.contains(suffix, "<") ||
      Strings.contains(suffix, ">") ||
      Strings.contains(suffix, "~")
    ) {
      shape = "liquescent";
    } else if (Strings.contains(suffix, "v") || Strings.contains(suffix, "V")) {
      shape = "virga";
    } else if (SwiftString.isUppercase(character)) {
      shape = "inclinatum";
    } else if (Strings.contains(suffix, "o") || Strings.contains(suffix, "O")) {
      shape = "oriscus";
    } else if (Strings.contains(suffix, "s") || Strings.contains(suffix, "S")) {
      shape = "stropha";
    } else {
      shape = "punctum";
    }

    let accidental: GregorianAccidental | null;
    if (Strings.contains(suffix, "x")) {
      accidental = "flat";
    } else if (Strings.contains(suffix, "y")) {
      accidental = "natural";
    } else if (Strings.contains(suffix, "#")) {
      accidental = "sharp";
    } else {
      accidental = null;
    }

    const unsupported = Strings.filter(
      suffix,
      (element) => !isSupportedSuffix(element),
    );
    const token = SwiftString.first(unsupported);
    if (token !== null) {
      throw new GregorianScoreParserError({
        kind: "unsupportedToken",
        token,
        offset: baseOffset + noteStart + 1,
      });
    }

    if (isCustos) {
      flushNotes();
    }
    currentNotes.push({
      pitch,
      shape,
      accidental,
      hasMora: Strings.contains(suffix, "."),
      hasEpisema: Strings.contains(suffix, "_"),
      moraCount: SwiftString.characterCount(
        Strings.filter(suffix, (element) => element === "."),
      ),
      episemaPosition: Strings.contains(suffix, "_0") ? "below" : "above",
      liquescence,
      // r0 is a hollow note within lines; r1 to r5 are signs
      // written above the note (an accent, a circle), not a
      // hollow note.
      isCavum: isCavum(suffix),
      hasIctus: Strings.contains(suffix, "'"),
      repetitionCount: isCustos ? 1 : repeatedNoteCount(suffix),
      sourceRange: {
        lowerBound: baseOffset + noteStart,
        upperBound: baseOffset + index,
      },
    });
    if (isCustos || Strings.contains(suffix, "!")) {
      flushNotes();
    }
  }

  flushNotes();
  return result;
}

/**
 * GABC's quick virga and stropha: each repeated sign is another note on the
 * same pitch (`hvv` is two virgae, `hsss` three strophae).
 */
function repeatedNoteCount(suffix: string): number {
  let count = 1;
  let shape: string | null = null;
  for (const sign of SwiftString.characters(suffix)) {
    if (sign !== "s" && sign !== "v") continue;
    if (shape === sign) count += 1;
    shape = sign;
  }
  return count;
}

function isCavum(suffix: string): boolean {
  const characters = SwiftString.characters(suffix);
  return characters.some((_, index) => {
    if (!(characters[index] === "r" || characters[index] === "R")) {
      return false;
    }
    if (!(index + 1 < characters.length)) return true;
    const sign = SwiftString.wholeNumberValue(characters[index + 1]);
    if (sign === null) return true;
    return sign === 0;
  });
}

function pitchValue(character: string): number | null {
  if (Strings.unicodeScalarCount(character) !== 1) {
    return null;
  }
  const normalized = character.toLowerCase();
  const normalizedScalar = normalized.codePointAt(0);
  if (
    normalizedScalar === undefined ||
    Strings.unicodeScalarCount(normalized) !== 1
  ) {
    return null;
  }
  const lower = "a".codePointAt(0)!;
  const upper = "m".codePointAt(0)!;
  if (!(normalizedScalar >= lower && normalizedScalar <= upper)) return null;
  return normalizedScalar - lower;
}

function isSupportedSuffix(character: string): boolean {
  return (
    SwiftString.isNumber(character) ||
    [
      ".",
      "_",
      "w",
      "W",
      "<",
      ">",
      "~",
      "x",
      "y",
      "#",
      "v",
      "V",
      "o",
      "O",
      "q",
      "Q",
      "s",
      "S",
      "r",
      "R",
      "'",
      "!",
      "@",
      "-",
      "+",
      "*",
      "†",
      "(",
    ].includes(character)
  );
}

function isIgnorableControl(character: string): boolean {
  return (
    SwiftString.isNumber(character) ||
    ["'", "!", "@", "]", "-", "+", "_", "*", "†", "(", "."].includes(character)
  );
}

function cleanLyric(source: string): string {
  let result = source.replace(/<[^>]+>/gu, "");
  result = Strings.replacingOccurrences(result, "{", "");
  result = Strings.replacingOccurrences(result, "}", "");
  // Psalm-tone sources use paired underscores for preparatory
  // syllables and paired asterisks for accented syllables. These
  // delimiters describe pointing/style and are not lyric text.
  // The paired patterns intentionally leave a standalone
  // liturgical asterisk unchanged.
  result = result.replace(/_([^_]+)_/gu, "$1");
  result = result.replace(/\*([^*]+)\*/gu, "$1");
  result = Strings.replacingOccurrences(result, "\n", " ");
  result = SwiftString.splitOmittingEmpty(
    result,
    SwiftString.isWhitespace,
  ).join(" ");
  return Strings.trimmingWhitespaceAndNewlines(result);
}

function lyricStyle(source: string): GregorianLyricStyle {
  const withoutTags = source.replace(/<[^>]+>/gu, "");
  if (Strings.hasRangeOfRegularExpression(withoutTags, /\*[^*]+\*/u)) {
    return "accented";
  }
  if (Strings.hasRangeOfRegularExpression(withoutTags, /_([^_]+)_/u)) {
    return "preparatory";
  }
  return "regular";
}

function standaloneLyricText(lyric: string): string {
  switch (lyric) {
    case "V/.":
      return "℣.";
    case "R/.":
      return "℟.";
    default:
      return lyric;
  }
}

function standaloneLyricStyle(
  lyric: string,
  parsedStyle: GregorianLyricStyle,
): GregorianLyricStyle {
  if (parsedStyle !== "regular") return parsedStyle;
  const rubricMarks = new Set(["*", "†", "‡", "+", "℣.", "℟."]);
  return rubricMarks.has(lyric) ? "rubric" : "regular";
}

function lyricStartsWord(source: string, isFirst: boolean): boolean {
  if (isFirst) return true;
  const withoutTags = source.replace(/<[^>]+>/gu, "");
  const first = SwiftString.first(withoutTags);
  return first !== null && SwiftString.isWhitespace(first);
}

/** `==` between two arrays of the same element. */
function elementsEqual(
  lhs: readonly number[],
  rhs: readonly number[],
): boolean {
  return (
    lhs.length === rhs.length &&
    lhs.every((element, index) => element === rhs[index])
  );
}

/** `Sequence.starts(with:)`. */
function starts(
  sequence: readonly number[],
  possiblePrefix: readonly number[],
): boolean {
  return (
    possiblePrefix.length <= sequence.length &&
    possiblePrefix.every((element, index) => element === sequence[index])
  );
}

export const GregorianNeumeClassifier = {
  classify(notes: readonly GregorianNote[]): GregorianNeumeForm {
    const first = notes.at(0);
    if (first === undefined) return "punctum";
    const pitches = notes.map((note) => note.pitch);
    const directions = pitches
      .slice(1)
      .map((to, index) => nextDirection(pitches[index], to));
    const allEqual = new Set(pitches).size === 1;
    const allInclinata = notes.every((note) => note.shape === "inclinatum");
    const allStropha = notes.every((note) => note.shape === "stropha");
    const allVirga = notes.every((note) => note.shape === "virga");
    // A note written twice or thrice (`hvv`, `hsss`) counts as so many.
    const writtenCount = notes.reduce(
      (count, note) => count + note.repetitionCount,
      0,
    );

    if (allInclinata) return "punctaInclinata";
    if (writtenCount === 1) {
      switch (first.shape) {
        case "virga":
          return "virga";
        case "stropha":
          return "apostropha";
        case "oriscus":
          return "oriscus";
        default:
          return "punctum";
      }
    }
    if (allEqual && allStropha) {
      return writtenCount >= 3 ? "tristropha" : "distropha";
    }
    if (allEqual && allVirga) {
      return writtenCount >= 3 ? "trivirga" : "bivirga";
    }
    if (allEqual) {
      return writtenCount >= 3 ? "tristropha" : "distropha";
    }
    if (notes.length === 2) {
      if (directions[0] > 0) {
        return notes.at(0)?.shape === "oriscus" ? "pesQuassus" : "podatus";
      }
      return directions[0] < 0 ? "clivis" : "punctum";
    }

    const firstTwo = directions.slice(0, 2);
    if (elementsEqual(firstTwo, [1, 1])) {
      if (notes.slice(1).some((note) => note.shape === "oriscus")) {
        return directions.slice(2).includes(-1) ? "salicusFlexus" : "salicus";
      }
      return directions.slice(2).includes(-1) ? "scandicusFlexus" : "scandicus";
    }
    if (elementsEqual(firstTwo, [-1, -1])) {
      return (notes.at(-1)?.liquescence ?? "none") !== "none"
        ? "ancus"
        : "climacus";
    }
    if (elementsEqual(firstTwo, [1, -1])) {
      return starts(directions.slice(2), [1, -1])
        ? "torculusResupinusFlexus"
        : directions.slice(2).at(0) === 1
          ? "torculusResupinus"
          : "torculus";
    }
    if (elementsEqual(firstTwo, [-1, 1])) {
      return directions.slice(2).at(0) === -1 ? "porrectusFlexus" : "porrectus";
    }
    if (
      directions.at(0) === 1 &&
      directions.slice(1).every((direction) => direction < 0)
    ) {
      return "pesSubpunctis";
    }
    return "punctum";
  },
};

function nextDirection(from: number, to: number): number {
  if (to > from) return 1;
  if (to < from) return -1;
  return 0;
}

/**
 * Splits a continuous GABC note run into the named forms accepted by the
 * native compositor. This is the native counterpart of Exsurge's
 * `createNeumesFromNotes` state machine.
 */
export const GregorianNeumeSegmenter = {
  segment(notes: readonly GregorianNote[]): GregorianNote[][] {
    // A note written twice or thrice (`hvv`, `hsss`) is a bivirga or a
    // tristropha in itself, and a custos belongs to no neume. Each stands
    // alone, and the notes on either side group as they would without it.
    if (!notes.some(GregorianNotes.standsAlone)) return segmentRun(notes);
    const result: GregorianNote[][] = [];
    let run: GregorianNote[] = [];
    for (const note of notes) {
      if (GregorianNotes.standsAlone(note)) {
        result.push(...segmentRun(run));
        run = [];
        result.push([note]);
      } else {
        run.push(note);
      }
    }
    result.push(...segmentRun(run));
    return result;
  },
};

function segmentRun(notes: readonly GregorianNote[]): GregorianNote[][] {
  if (!(notes.length > 1)) return notes.length === 0 ? [] : [[...notes]];
  const result: GregorianNote[][] = [];
  let index = 0;

  while (index < notes.length) {
    const remaining = notes.length - index;
    if (!(remaining > 1)) {
      result.push([notes[index]]);
      break;
    }

    const first = notes[index];
    const second = notes[index + 1];
    const firstDirection = direction(first.pitch, second.pitch);

    if (first.shape === "virga") {
      const count = repeatedShapeCount(notes, index, "virga", first.pitch, 3);
      result.push(notes.slice(index, index + count));
      index += count;
      continue;
    }
    if (first.shape === "stropha") {
      const count = repeatedShapeCount(notes, index, "stropha", first.pitch, 3);
      result.push(notes.slice(index, index + count));
      index += count;
      continue;
    }
    if (first.shape === "inclinatum") {
      let end = index + 1;
      while (end < notes.length && notes[end].shape === "inclinatum") {
        end += 1;
      }
      result.push(notes.slice(index, end));
      index = end;
      continue;
    }

    let length = 1;
    if (firstDirection > 0) {
      if (
        remaining >= 3 &&
        notes[index + 2].shape === "inclinatum" &&
        direction(second.pitch, notes[index + 2].pitch) < 0
      ) {
        length = 3;
        while (
          index + length < notes.length &&
          notes[index + length].shape === "inclinatum" &&
          direction(
            notes[index + length - 1].pitch,
            notes[index + length].pitch,
          ) < 0
        ) {
          length += 1;
        }
      } else if (remaining >= 3) {
        const secondDirection = direction(second.pitch, notes[index + 2].pitch);
        if (secondDirection > 0) {
          length = 3;
          if (
            remaining >= 4 &&
            direction(notes[index + 2].pitch, notes[index + 3].pitch) < 0
          ) {
            length = 4;
          }
        } else if (secondDirection < 0) {
          length = 3;
          if (
            remaining >= 4 &&
            direction(notes[index + 2].pitch, notes[index + 3].pitch) > 0
          ) {
            length = 4;
            if (
              remaining >= 5 &&
              direction(notes[index + 3].pitch, notes[index + 4].pitch) < 0
            ) {
              length = 5;
            }
          }
        } else {
          length = 2;
        }
      } else {
        length = 2;
      }
    } else if (firstDirection < 0) {
      if (second.shape === "inclinatum") {
        length = 2;
        while (
          index + length < notes.length &&
          notes[index + length].shape === "inclinatum" &&
          direction(
            notes[index + length - 1].pitch,
            notes[index + length].pitch,
          ) < 0
        ) {
          length += 1;
        }
      } else if (
        remaining >= 3 &&
        direction(second.pitch, notes[index + 2].pitch) < 0 &&
        notes[index + 2].liquescence !== "none"
      ) {
        length = 3;
      } else if (
        remaining >= 3 &&
        direction(second.pitch, notes[index + 2].pitch) > 0
      ) {
        length = 3;
        if (
          remaining >= 4 &&
          direction(notes[index + 2].pitch, notes[index + 3].pitch) < 0
        ) {
          length = 4;
        }
      } else {
        length = 2;
      }
    } else {
      length = Math.min(3, repeatedPitchCount(notes, index, first.pitch));
    }

    result.push(notes.slice(index, index + length));
    index += length;
  }
  return result;
}

function direction(from: number, to: number): number {
  if (to > from) return 1;
  if (to < from) return -1;
  return 0;
}

function repeatedShapeCount(
  notes: readonly GregorianNote[],
  index: number,
  shape: GregorianNoteShape,
  pitch: number,
  maximum: number,
): number {
  let count = 0;
  while (
    index + count < notes.length &&
    count < maximum &&
    notes[index + count].shape === shape &&
    notes[index + count].pitch === pitch
  ) {
    count += 1;
  }
  return Math.max(1, count);
}

function repeatedPitchCount(
  notes: readonly GregorianNote[],
  index: number,
  pitch: number,
): number {
  let count = 0;
  while (index + count < notes.length && notes[index + count].pitch === pitch) {
    count += 1;
  }
  return Math.max(1, count);
}
