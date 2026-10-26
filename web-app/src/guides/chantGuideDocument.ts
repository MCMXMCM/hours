// The Guide to Chant as the app holds it, parallel to
// `HoursApp/ChantGuideDocument.swift`: the lessons, their examples, and the
// glossary, with the rule that chooses which example the cantor guide attends
// to as a lesson is read.
//
// A Swift struct is plain data here, and what Swift attaches to it stands in
// the namespace named for its plural: `document.example(_:)` is
// `ChantGuideDocuments.example`, and `example.pitchReference` is
// `ChantGuideExamples.pitchReference`.
//
// `ChantGuideDocuments.decode` stands for `JSONDecoder` and the `Decodable`
// conformances of these types (see `decoding.ts`); a key the document does
// not declare, the guide's `coverage` for one, is passed over. The scores are
// decoded as `HoursCore/Models.swift` decodes them.

import type {
  ChantClef,
  ChantEvent,
  ChantNotationModifier,
  ChantProvenance,
  ChantReviewStatus,
  ChantScore,
  ChantTimeline,
} from "@/core/models.ts";
import {
  GuideDecodingError,
  array,
  bool,
  container,
  decode,
  decodeIfPresent,
  double,
  int,
  keyed,
  rawValue,
  string,
  type Read,
} from "./decoding.ts";

export interface ChantGuideDocument {
  readonly version: number;
  readonly title: string;
  readonly introduction: string;
  readonly sections: readonly ChantGuideSection[];
  readonly examples: readonly ChantGuideExample[];
  readonly glossary: readonly ChantGuideTerm[];
}

export interface ChantGuideSection {
  readonly id: string;
  readonly title: string;
  readonly source: string;
  readonly blocks: readonly ChantGuideBlock[];
}

/** `ChantGuideBlock.Kind`. */
export type ChantGuideBlockKind = "prose" | "example" | "pronunciation";

const chantGuideBlockKindAllCases: readonly ChantGuideBlockKind[] = [
  "prose",
  "example",
  "pronunciation",
];

export const ChantGuideBlockKinds = {
  allCases: chantGuideBlockKindAllCases,

  /** `ChantGuideBlock.Kind(rawValue:)`. */
  fromRawValue(rawValue: string): ChantGuideBlockKind | null {
    return (
      chantGuideBlockKindAllCases.find((kind) => kind === rawValue) ?? null
    );
  },
};

export interface ChantGuideBlock {
  readonly id: string;
  readonly kind: ChantGuideBlockKind;
  readonly title: string | null;
  readonly text: string | null;
  readonly detail: string | null;
  readonly exampleID: string | null;
}

export interface ChantGuideExample {
  readonly id: string;
  readonly title: string;
  readonly caption: string;
  readonly source: string;
  readonly variants: readonly ChantGuideVariant[];
}

export interface ChantGuideVariant {
  readonly id: string;
  readonly title: string;
  readonly explanation: string;
  readonly score: ChantScore;
  readonly annotations: readonly ChantGuideAnnotation[];
  readonly formula: readonly ChantGuideFormulaNote[] | null;
}

export interface ChantGuideAnnotation {
  readonly label: string;
  readonly explanation: string;
  readonly eventIDs: readonly string[];
}

/** Formula symbols illustrate a rule; they are deliberately not ChantEvents. */
export interface ChantGuideFormulaNote {
  readonly step: number;
  readonly optional: boolean;
  readonly label: string;
}

export interface ChantGuideTerm {
  readonly term: string;
  readonly definition: string;
  readonly sectionID: string;
}

// MARK: Decoding

const reviewStatus = rawValue<ChantReviewStatus>(
  [
    "exactMatch",
    "humanReviewed",
    "generatedFormula",
    "sourceTranscription",
    "ambiguous",
    "missing",
  ],
  "a review status",
);

const notationModifier = rawValue<ChantNotationModifier>(
  [
    "mora",
    "episema",
    "quilisma",
    "liquescent",
    "flat",
    "natural",
    "sharp",
    "phraseBoundary",
  ],
  "a notation modifier",
);

const clefKind = rawValue<ChantClef["kind"]>(["c", "f"], "a kind of clef");

const blockKind = rawValue<ChantGuideBlockKind>(
  chantGuideBlockKindAllCases,
  "a kind of block",
);

/** `ChantClef`, under its own keys or the compact ones of a stored event. */
function clef(keys: { kind: string; line: string; flattensB: string }) {
  return (value: unknown, codingPath: string): ChantClef => {
    const from = container(value, codingPath);
    return {
      kind: decode(from, keys.kind, codingPath, clefKind),
      line: decode(from, keys.line, codingPath, int),
      flattensB: decode(from, keys.flattensB, codingPath, bool),
    };
  };
}

const verboseClef = clef({
  kind: "kind",
  line: "line",
  flattensB: "flattensB",
});
const compactClef = clef({ kind: "k", line: "l", flattensB: "b" });

/** `ChantEvent.init(from:)`, which reads either of the two forms an event is stored in. */
const chantEvent: Read<ChantEvent> = (value, codingPath) => {
  const from = container(value, codingPath);
  if (from.id !== undefined) {
    return {
      id: decode(from, "id", codingPath, string),
      phraseID: decode(from, "phraseID", codingPath, string),
      syllableID: decode(from, "syllableID", codingPath, string),
      syllable: decode(from, "syllable", codingPath, string),
      relativePitch: decode(from, "relativePitch", codingPath, int),
      durationWeight: decode(from, "durationWeight", codingPath, double),
      modifiers: decode(from, "modifiers", codingPath, array(notationModifier)),
      clef: decodeIfPresent(from, "clef", codingPath, verboseClef),
    };
  }
  return {
    id: decode(from, "i", codingPath, string),
    phraseID: decode(from, "p", codingPath, string),
    syllableID: decode(from, "y", codingPath, string),
    syllable: decode(from, "s", codingPath, string),
    relativePitch: decode(from, "n", codingPath, int),
    durationWeight: decode(from, "d", codingPath, double),
    modifiers: decode(from, "m", codingPath, array(notationModifier)),
    clef: decodeIfPresent(from, "c", codingPath, compactClef),
  };
};

const chantTimeline: Read<ChantTimeline> = (value, codingPath) => {
  const from = container(value, codingPath);
  return { events: decode(from, "events", codingPath, array(chantEvent)) };
};

const chantProvenance: Read<ChantProvenance> = (value, codingPath) => {
  const from = container(value, codingPath);
  return {
    collection: decode(from, "collection", codingPath, string),
    sourceBook: decode(from, "sourceBook", codingPath, string),
    sourceURL: decodeIfPresent(from, "sourceURL", codingPath, string),
    license: decode(from, "license", codingPath, string),
    snapshot: decode(from, "snapshot", codingPath, string),
  };
};

const chantScore: Read<ChantScore> = (value, codingPath) => {
  const from = container(value, codingPath);
  return {
    id: decode(from, "id", codingPath, string),
    incipit: decode(from, "incipit", codingPath, string),
    gabc: decode(from, "gabc", codingPath, string),
    mode: decodeIfPresent(from, "mode", codingPath, string),
    reviewStatus: decode(from, "reviewStatus", codingPath, reviewStatus),
    provenance: decode(from, "provenance", codingPath, chantProvenance),
    timeline: decode(from, "timeline", codingPath, chantTimeline),
  };
};

const formulaNote: Read<ChantGuideFormulaNote> = (value, codingPath) => {
  const from = container(value, codingPath);
  return {
    step: decode(from, "step", codingPath, int),
    optional: decode(from, "optional", codingPath, bool),
    label: decode(from, "label", codingPath, string),
  };
};

const annotation: Read<ChantGuideAnnotation> = (value, codingPath) => {
  const from = container(value, codingPath);
  return {
    label: decode(from, "label", codingPath, string),
    explanation: decode(from, "explanation", codingPath, string),
    eventIDs: decode(from, "eventIDs", codingPath, array(string)),
  };
};

const variant: Read<ChantGuideVariant> = (value, codingPath) => {
  const from = container(value, codingPath);
  return {
    id: decode(from, "id", codingPath, string),
    title: decode(from, "title", codingPath, string),
    explanation: decode(from, "explanation", codingPath, string),
    score: decode(from, "score", codingPath, chantScore),
    annotations: decode(from, "annotations", codingPath, array(annotation)),
    formula: decodeIfPresent(from, "formula", codingPath, array(formulaNote)),
  };
};

const example: Read<ChantGuideExample> = (value, codingPath) => {
  const from = container(value, codingPath);
  const variants = decode(from, "variants", codingPath, array(variant));
  // Swift decodes an example without a version, and then cannot show it:
  // its first version is its pitch reference. Here it is not decoded.
  if (variants.length === 0) {
    throw new GuideDecodingError(keyed(codingPath, "variants"), "is empty");
  }
  return {
    id: decode(from, "id", codingPath, string),
    title: decode(from, "title", codingPath, string),
    caption: decode(from, "caption", codingPath, string),
    source: decode(from, "source", codingPath, string),
    variants,
  };
};

const block: Read<ChantGuideBlock> = (value, codingPath) => {
  const from = container(value, codingPath);
  return {
    id: decode(from, "id", codingPath, string),
    kind: decode(from, "kind", codingPath, blockKind),
    title: decodeIfPresent(from, "title", codingPath, string),
    text: decodeIfPresent(from, "text", codingPath, string),
    detail: decodeIfPresent(from, "detail", codingPath, string),
    exampleID: decodeIfPresent(from, "exampleID", codingPath, string),
  };
};

const section: Read<ChantGuideSection> = (value, codingPath) => {
  const from = container(value, codingPath);
  return {
    id: decode(from, "id", codingPath, string),
    title: decode(from, "title", codingPath, string),
    source: decode(from, "source", codingPath, string),
    blocks: decode(from, "blocks", codingPath, array(block)),
  };
};

const term: Read<ChantGuideTerm> = (value, codingPath) => {
  const from = container(value, codingPath);
  return {
    term: decode(from, "term", codingPath, string),
    definition: decode(from, "definition", codingPath, string),
    sectionID: decode(from, "sectionID", codingPath, string),
  };
};

export const ChantGuideDocuments = {
  /**
   * `JSONDecoder().decode(ChantGuideDocument.self, from:)`, for JSON already
   * parsed. Throws a `GuideDecodingError` naming what could not be read.
   */
  decode(json: unknown): ChantGuideDocument {
    const from = container(json, "");
    return {
      version: decode(from, "version", "", int),
      title: decode(from, "title", "", string),
      introduction: decode(from, "introduction", "", string),
      sections: decode(from, "sections", "", array(section)),
      examples: decode(from, "examples", "", array(example)),
      glossary: decode(from, "glossary", "", array(term)),
    };
  },

  example(document: ChantGuideDocument, id: string): ChantGuideExample | null {
    return document.examples.find((candidate) => candidate.id === id) ?? null;
  },
};

export const ChantGuideExamples = {
  pitchReference(example: ChantGuideExample): ChantScore {
    return example.variants[0].score;
  },
};

export const ChantGuideAnnotations = {
  id(annotation: ChantGuideAnnotation): string {
    return annotation.eventIDs.join(",") + annotation.label;
  },
};

export const ChantGuideTerms = {
  id(term: ChantGuideTerm): string {
    return term.term;
  },
};

// MARK: Viewport

/** A rectangle as CoreGraphics gives one: an origin and a size. */
export interface ChantGuideRect {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
}

// `CGRect`'s edges and size are those of the standardized rectangle, whose
// width and height are never negative.

function minX(rect: ChantGuideRect): number {
  return rect.width < 0 ? rect.x + rect.width : rect.x;
}

function maxX(rect: ChantGuideRect): number {
  return rect.width < 0 ? rect.x : rect.x + rect.width;
}

function minY(rect: ChantGuideRect): number {
  return rect.height < 0 ? rect.y + rect.height : rect.y;
}

function maxY(rect: ChantGuideRect): number {
  return rect.height < 0 ? rect.y : rect.y + rect.height;
}

function midY(rect: ChantGuideRect): number {
  return rect.y + rect.height / 2;
}

/**
 * `intersection(_:).height`. Rectangles that do not meet intersect in the
 * null rectangle, which has no height; those that only touch, in an empty one.
 */
function intersectionHeight(lhs: ChantGuideRect, rhs: ChantGuideRect): number {
  const left = Math.max(minX(lhs), minX(rhs));
  const right = Math.min(maxX(lhs), maxX(rhs));
  const top = Math.max(minY(lhs), minY(rhs));
  const bottom = Math.min(maxY(lhs), maxY(rhs));
  if (right < left || bottom < top) return 0;
  return bottom - top;
}

/**
 * `<` between two Strings, which orders them by their Unicode scalars. The
 * identifiers compared are in NFC, as everything the guide holds is.
 */
function precedes(lhs: string, rhs: string): boolean {
  const left = Array.from(lhs, (scalar) => scalar.codePointAt(0)!);
  const right = Array.from(rhs, (scalar) => scalar.codePointAt(0)!);
  const shared = Math.min(left.length, right.length);
  for (let index = 0; index < shared; index += 1) {
    if (left[index] !== right[index]) return left[index] < right[index];
  }
  return left.length < right.length;
}

/** `ChantGuideViewport.Reason`: why the guide looks again for its example. */
export type ChantGuideViewportReason =
  "opened" | "scrollEnded" | "layoutChanged";

export const ChantGuideViewport = {
  /**
   * Whether more than a sliver of a frame lies within the viewport: the test
   * Swift writes as `frame.intersection(viewport).height > 1`, both where it
   * chooses an example and where it stops one that has been scrolled away.
   */
  isVisible(frame: ChantGuideRect, viewport: ChantGuideRect): boolean {
    return intersectionHeight(frame, viewport) > 1;
  },

  /**
   * The example that keeps the cantor guide while any of it can be seen: the
   * one playing, and, when the page has only been laid out anew, the one the
   * reader chose. A new engraving of the version just chosen must not hand
   * the guide to a neighbouring example; a reader who has scrolled is given
   * the example nearest the middle.
   */
  retainedID(
    selectedID: string | null,
    isPlaying: boolean,
    reason: ChantGuideViewportReason,
  ): string | null {
    return isPlaying || reason === "layoutChanged" ? selectedID : null;
  },

  /**
   * The example the cantor guide attends to: the one retained, while any of
   * it can be seen, and otherwise the visible example nearest the middle of
   * the viewport.
   */
  target(
    frames: ReadonlyMap<string, ChantGuideRect>,
    viewport: ChantGuideRect,
    retainedID: string | null,
  ): string | null {
    if (!(Math.abs(viewport.width) > 0 && Math.abs(viewport.height) > 0)) {
      return null;
    }
    const visible = new Map<string, ChantGuideRect>();
    for (const [id, frame] of frames) {
      if (ChantGuideViewport.isVisible(frame, viewport)) visible.set(id, frame);
    }
    if (retainedID !== null && visible.has(retainedID)) return retainedID;

    // `min(by:)`. The order is total, so the dictionary's own order, which
    // Swift leaves unspecified, cannot change the result.
    let nearest: { key: string; value: ChantGuideRect } | null = null;
    for (const [key, value] of visible) {
      if (nearest === null) {
        nearest = { key, value };
        continue;
      }
      const left = Math.abs(midY(value) - midY(viewport));
      const right = Math.abs(midY(nearest.value) - midY(viewport));
      const areInIncreasingOrder =
        left === right ? precedes(key, nearest.key) : left < right;
      if (areInIncreasingOrder) nearest = { key, value };
    }
    return nearest?.key ?? null;
  },
};
