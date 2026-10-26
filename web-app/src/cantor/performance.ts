// The cantor guide's performance model, parallel to
// `CantorGuidePerformanceEvent`, `CantorGuideSynthesizer`, and `GABCClef` in
// `HoursApp/ChantPlaybackController.swift`: how long each note lasts, where a
// phrase breathes, and the pitch at which each note sounds.
//
// A Swift private helper is a module-private function of the same name. A
// struct is plain data, with its initializers and methods in the namespace
// named for its plural: `GABCClef(gabc:)` is `GABCClefs.fromGABC`.
//
// Comparison. Swift compares Strings by canonical equivalence, and keys its
// dictionaries so; the comparisons and maps below are literal. They agree for
// a score normalized to NFC, as the corpus is when it is loaded.
//
// Arithmetic. Every quantity here is a Swift `Double` or `Int`, so a
// JavaScript number reproduces it. `pow` is the platform's on either side,
// and the two may differ in the last place.

import type { ChantClef, ChantEvent, ChantScore } from "@/core/models.ts";
import {
  GregorianNotes,
  GregorianScoreParser,
  type GregorianDivision,
  type GregorianNeumeForm,
  type GregorianNote,
  type GregorianScore,
} from "@/core/notation/index.ts";
import * as Strings from "@/core/notation/strings.ts";
import * as SwiftString from "@/core/swiftString.ts";
import { max, min } from "./swiftNumerics.ts";

export interface CantorGuidePerformanceEvent {
  readonly event: ChantEvent;
  readonly durationWeight: number;
  readonly followingSilenceWeight: number;
  readonly startsPhrase: boolean;
  readonly endsPhrase: boolean;
  readonly startsSyllable: boolean;
  readonly endsSyllable: boolean;
}

/** `GABCClef.Kind`. */
export type GABCClefKind = "c" | "f";

export interface GABCClef {
  readonly kind: GABCClefKind;
  readonly line: number;
  readonly flattensB: boolean;
}

const c3: GABCClef = { kind: "c", line: 3, flattensB: false };

/**
 * `split(separator:maxSplits:)` for a separator of several Characters. Like
 * the standard library's, it omits an empty subsequence and does not count
 * the one omitted against `maxSplits`; it never divides a Character.
 */
function split(value: string, separator: string, maxSplits: number): string[] {
  const all = SwiftString.characters(value);
  const sought = SwiftString.characters(separator);
  const result: string[] = [];
  let subSequenceStart = 0;

  const appendSubsequence = (end: number): boolean => {
    if (subSequenceStart === end) return false;
    result.push(all.slice(subSequenceStart, end).join(""));
    return true;
  };

  if (maxSplits === 0 || all.length === 0) {
    appendSubsequence(all.length);
    return result;
  }

  let index = 0;
  while (index + sought.length <= all.length) {
    if (
      sought.every((character, offset) => all[index + offset] === character)
    ) {
      const didAppend = appendSubsequence(index);
      index += sought.length;
      subSequenceStart = index;
      if (didAppend && result.length === maxSplits) break;
      continue;
    }
    index += 1;
  }

  if (subSequenceStart !== all.length) {
    result.push(all.slice(subSequenceStart).join(""));
  }
  return result;
}

// Stands for any Character of more than one UTF-16 unit. It is not a
// character that the clef pattern names.
const compoundCharacter = "\u{FFFD}";

/**
 * The text matched by `range(of: pattern, options: .regularExpression)`, or
 * `null`. Foundation hands such a pattern to Swift's own Regex, which matches
 * Character by Character, so the pattern is tried against the string with
 * every Character of several units reduced to one unit that the pattern does
 * not name. That is sound only for a pattern built, as the clef's is, from
 * single ASCII literals and classes of them; what it matches is then the
 * same text in the original.
 */
function firstMatch(value: string, pattern: RegExp): string | null {
  const byCharacter = SwiftString.characters(value)
    .map((character) =>
      character.length === 1 ? character : compoundCharacter,
    )
    .join("");
  return pattern.exec(byCharacter)?.[0] ?? null;
}

function diatonicOffsetFromC(clef: GABCClef, staffStep: number): number {
  // GABC `h` is Exsurge staff position 1; C/F clef lines occupy
  // positions -3, -1, 1, and 3. An F clef places C three steps lower.
  const noteStaffPosition = staffStep + 1;
  const clefStaffPosition = 2 * clef.line - 5;
  const cStaffPosition =
    clef.kind === "c" ? clefStaffPosition : clefStaffPosition - 3;
  return noteStaffPosition - cStaffPosition;
}

export const GABCClefs = {
  c3,

  /** `GABCClef(kind:line:flattensB:)`. */
  make(kind: GABCClefKind, line: number, flattensB = false): GABCClef {
    return { kind, line, flattensB };
  },

  /** `GABCClef(_ clef: ChantClef)`. */
  fromChantClef(clef: ChantClef): GABCClef {
    return GABCClefs.make(
      clef.kind === "f" ? "f" : "c",
      clef.line,
      clef.flattensB,
    );
  },

  /** `GABCClef(gabc:)`: the first clef of the notation body, or `c3`. */
  fromGABC(gabc: string): GABCClef {
    const body = split(gabc, "%%", 1).at(-1) ?? gabc;
    const range = firstMatch(body, /\((cb?[1-4]|f[1-4])/u);
    if (range === null) return c3;

    const token = SwiftString.dropFirst(range);
    const isF = SwiftString.first(token) === "f";
    const isFlatC = SwiftString.hasPrefix(token, "cb");
    const lineCharacter = SwiftString.last(token);
    return GABCClefs.make(
      isF ? "f" : "c",
      (lineCharacter === null ? null : Strings.int(lineCharacter)) ?? 3,
      isFlatC,
    );
  },

  semitoneOffset(clef: GABCClef, staffStep: number): number {
    const offset = diatonicOffsetFromC(clef, staffStep);
    const octave = Math.floor(offset / 7.0);
    const scaleIndex = offset - octave * 7;
    const naturalSemitonesFromC = [0, 2, 4, 5, 7, 9, 11];
    let semitones = octave * 12 + naturalSemitonesFromC[scaleIndex];
    if (clef.flattensB && scaleIndex === 6) {
      semitones -= 1;
    }
    return semitones;
  },

  appliesDefaultFlat(clef: GABCClef, staffStep: number): boolean {
    if (!clef.flattensB) return false;
    const offset = diatonicOffsetFromC(clef, staffStep);
    const octave = Math.floor(offset / 7.0);
    return offset - octave * 7 === 6;
  },

  /** `==`, as `Equatable` is synthesized for the struct. */
  equals(lhs: GABCClef, rhs: GABCClef): boolean {
    return (
      lhs.kind === rhs.kind &&
      lhs.line === rhs.line &&
      lhs.flattensB === rhs.flattensB
    );
  },
};

const g4Frequency = 392.0;
/**
 * The length of a simple note at a tempo of 100%, for every voice. It was
 * first 0.38 of a second, which is quick for chant and let the tempo be
 * raised to a pace no chant is sung at. The pace then had at 70% is now the
 * measure, so that the tempo runs from very slow to about the former 100%.
 */
export const secondsPerBeat = 0.38 / 0.7;

interface SemanticNote {
  readonly note: GregorianNote;
  readonly neumeForm: GregorianNeumeForm;
}

function isSalicusPulse(semantic: SemanticNote): boolean {
  return (
    semantic.note.hasIctus &&
    (semantic.neumeForm === "salicus" || semantic.neumeForm === "salicusFlexus")
  );
}

interface NotationSemantics {
  readonly notesByEventID: Map<string, SemanticNote>;
  readonly divisionAfterEvent: Map<string, GregorianDivision>;
}

function notationSemantics(score: ChantScore): NotationSemantics {
  const result: NotationSemantics = {
    notesByEventID: new Map(),
    divisionAfterEvent: new Map(),
  };

  const parseableGABC = Strings.contains(score.gabc, "%%")
    ? score.gabc
    : `%%${score.gabc}`;
  let notation: GregorianScore;
  try {
    notation = GregorianScoreParser.parse(parseableGABC, score.timeline);
  } catch {
    return result;
  }

  let lastEventID: string | null = null;
  for (const element of notation.elements) {
    switch (element.type) {
      case "neume":
        for (const note of element.neume.notes) {
          result.notesByEventID.set(note.id, {
            note,
            neumeForm: element.neume.form,
          });
          // A division written after a custos closes the phrase
          // of the last note sung before it.
          if (!GregorianNotes.isCustos(note)) {
            lastEventID = note.id;
          }
        }
        break;
      case "division":
        if (lastEventID !== null) {
          result.divisionAfterEvent.set(lastEventID, element.division);
        }
        break;
      case "clef":
      case "accidental":
      case "lyricMark":
      case "forcedBreak":
        break;
      default:
        break;
    }
  }
  return result;
}

function durationWeight(
  index: number,
  events: readonly ChantEvent[],
  notesByEventID: ReadonlyMap<string, SemanticNote>,
): number {
  const event = events[index];
  const semantic = notesByEventID.get(event.id);
  const hasMora = semantic?.note.hasMora ?? event.modifiers.includes("mora");
  const hasEpisema =
    semantic?.note.hasEpisema ?? event.modifiers.includes("episema");

  // Remove the compiler's former additive timing hints before applying
  // the contextual Solesmes-style values below. This also preserves
  // deliberately unusual fixture or generated-event weights.
  let baseline = event.durationWeight;
  if (event.modifiers.includes("phraseBoundary")) baseline -= 0.4;
  if (event.modifiers.includes("mora")) baseline -= 0.5;
  if (event.modifiers.includes("episema")) baseline -= 0.25;
  baseline = max(0.01, baseline);

  if (hasMora) {
    return max(baseline, 2);
  }

  // In a salicus it is the marked note itself that is broadened.
  // The preceding-note rule belongs to the quilisma, not the salicus.
  if (semantic !== undefined && isSalicusPulse(semantic)) {
    return max(baseline, 1.8);
  }

  if (index + 1 < events.length) {
    const next = events[index + 1];
    const nextSemantic = notesByEventID.get(next.id);
    const nextHasDoubleMora = (nextSemantic?.note.moraCount ?? 0) > 1;
    const nextIsQuilisma =
      nextSemantic?.note.shape === "quilisma" ||
      next.modifiers.includes("quilisma");
    if (nextHasDoubleMora || nextIsQuilisma) {
      return max(baseline, 1.8);
    }
  }

  if (hasEpisema) {
    let neighboringEpisemata = 1;
    if (index > 0) {
      const previous = events[index - 1];
      if (
        notesByEventID.get(previous.id)?.note.hasEpisema ??
        previous.modifiers.includes("episema")
      ) {
        neighboringEpisemata += 1;
      }
    }
    if (index + 1 < events.length) {
      const next = events[index + 1];
      if (
        notesByEventID.get(next.id)?.note.hasEpisema ??
        next.modifiers.includes("episema")
      ) {
        neighboringEpisemata += 1;
      }
    }
    return max(baseline, 1 + 0.9 / neighboringEpisemata);
  }

  return baseline;
}

function silenceWeight(division: GregorianDivision): number {
  switch (division) {
    case "minima":
      return 0;
    case "minor":
      return 1;
    case "major":
    case "final":
      return 2;
    default:
      return 1;
  }
}

function fallbackSilenceWeight(
  event: ChantEvent,
  next: ChantEvent | null,
): number {
  if (!(
    event.modifiers.includes("phraseBoundary") &&
    (next === null || next.phraseID !== event.phraseID)
  )) {
    return 0;
  }
  return 1;
}

/**
 * A note written twice or thrice (`hvv`, `hsss`) has a single event in the
 * timeline, and is sung as often as it is written: each note but the last an
 * ordinary one, and the last with whatever lengthening, pause, and close of
 * phrase or syllable the written signs give it.
 */
function repetitions(
  performed: CantorGuidePerformanceEvent,
  count: number,
): CantorGuidePerformanceEvent[] {
  if (!(count > 1)) return [performed];
  return Array.from({ length: count }, (_, repetition) => {
    const isFirst = repetition === 0;
    const isLast = repetition === count - 1;
    return {
      event: performed.event,
      durationWeight: isLast
        ? performed.durationWeight
        : min(1, performed.durationWeight),
      followingSilenceWeight: isLast ? performed.followingSilenceWeight : 0,
      startsPhrase: isFirst && performed.startsPhrase,
      endsPhrase: isLast && performed.endsPhrase,
      startsSyllable: isFirst && performed.startsSyllable,
      endsSyllable: isLast && performed.endsSyllable,
    };
  });
}

export const CantorGuideSynthesizer = {
  seconds(event: ChantEvent, tempo: number): number {
    const safeTempo = max(0.1, tempo);
    return max(0.09, (secondsPerBeat * event.durationWeight) / safeTempo);
  },

  performance(
    selectedEvents: readonly ChantEvent[],
    score: ChantScore,
  ): CantorGuidePerformanceEvent[] {
    if (selectedEvents.length === 0) return [];

    const semantics = notationSemantics(score);
    // `silenceWeight(for:)` of the division that follows an event, or else
    // the weight its phrase boundary implies.
    const silenceAfter = (event: ChantEvent, next: ChantEvent | null) => {
      const division = semantics.divisionAfterEvent.get(event.id);
      return division !== undefined
        ? silenceWeight(division)
        : fallbackSilenceWeight(event, next);
    };

    // The compiled timeline holds an event for every pitch letter of the
    // score, a custos among them. A custos guides the eye to the pitch
    // that follows and is not sung: the notes on either side of it are
    // performed as neighbours.
    const sungEvents = selectedEvents.filter((event) => {
      const semantic = semantics.notesByEventID.get(event.id);
      return semantic === undefined || !GregorianNotes.isCustos(semantic.note);
    });
    return sungEvents.flatMap((event, index) => {
      const previous = index > 0 ? sungEvents[index - 1] : null;
      const next = index + 1 < sungEvents.length ? sungEvents[index + 1] : null;
      const followingSilenceWeight = silenceAfter(event, next);
      const previousSilence =
        previous !== null ? silenceAfter(previous, event) : 0;

      const performed: CantorGuidePerformanceEvent = {
        event,
        durationWeight: durationWeight(
          index,
          sungEvents,
          semantics.notesByEventID,
        ),
        followingSilenceWeight,
        startsPhrase: index === 0 || previousSilence > 0,
        endsPhrase:
          index === sungEvents.length - 1 || followingSilenceWeight > 0,
        startsSyllable: previous?.syllableID !== event.syllableID,
        endsSyllable: next?.syllableID !== event.syllableID,
      };
      return repetitions(
        performed,
        semantics.notesByEventID.get(event.id)?.note.repetitionCount ?? 1,
      );
    });
  },

  semitoneOffset(event: ChantEvent, clef: GABCClef = GABCClefs.c3): number {
    const eventClef =
      event.clef != null ? GABCClefs.fromChantClef(event.clef) : clef;
    let semitones = GABCClefs.semitoneOffset(eventClef, event.relativePitch);
    if (
      event.modifiers.includes("flat") &&
      !GABCClefs.appliesDefaultFlat(eventClef, event.relativePitch)
    ) {
      semitones -= 1;
    } else if (
      event.modifiers.includes("natural") &&
      GABCClefs.appliesDefaultFlat(eventClef, event.relativePitch)
    ) {
      semitones += 1;
    } else if (event.modifiers.includes("sharp")) {
      semitones += GABCClefs.appliesDefaultFlat(eventClef, event.relativePitch)
        ? 2
        : 1;
    }
    return semitones;
  },

  centeredTransposition(
    events: readonly ChantEvent[],
    targetOffset: number,
    clef: GABCClef = GABCClefs.c3,
  ): number {
    const offsets = events.map((event) =>
      CantorGuideSynthesizer.semitoneOffset(event, clef),
    );
    const counts = new Map<number, number>();
    for (const offset of offsets) {
      counts.set(offset, (counts.get(offset) ?? 0) + 1);
    }
    // `max(by:)`. The order is total, so the dictionary's own order, which
    // Swift leaves unspecified, cannot change the result.
    let dominant: { key: number; value: number } | null = null;
    for (const [key, value] of counts) {
      const right = { key, value };
      if (dominant === null) {
        dominant = right;
        continue;
      }
      const left: { key: number; value: number } = dominant;
      const areInIncreasingOrder =
        left.value === right.value
          ? left.key < right.key
          : left.value < right.value;
      if (areInIncreasingOrder) dominant = right;
    }
    if (dominant === null) {
      return targetOffset;
    }
    return targetOffset - dominant.key;
  },

  frequency(
    event: ChantEvent,
    transposition: number,
    clef: GABCClef = GABCClefs.c3,
  ): number {
    const semitones =
      CantorGuideSynthesizer.semitoneOffset(event, clef) + transposition;
    return g4Frequency * Math.pow(2, semitones / 12.0);
  },
};
