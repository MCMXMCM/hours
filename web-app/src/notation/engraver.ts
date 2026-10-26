// Engraves a chant with gabc-parser and reports where its neumes lie.
//
// This is the only module that touches the engraver. It reads the GABC
// with the score's compiled timeline, so that every note drawn is named by
// the event that sings it; lays it out for a given width, as the native
// apps do with the same library; and draws it as SVG. The layout says where
// each neume lies, so the reader can hit-test a tap and mark the note being
// sung.

import {
  GregorianEngravingLayoutEngine,
  GregorianScoreHighlight,
  GregorianScoreParser,
  createCanvasLyricMeasurer,
  gregorianScoreSVG,
  type GregorianLayout,
  type GregorianRect,
  type GregorianScore,
} from "gabc-parser";
import type { ChantScore } from "@/core/models.ts";

export const notationFontFamily = "'EB Garamond'";

/** The size of the words at a notation scale of one. */
const lyricFontSize = 21;
const minimumWidth = 240;

export interface Frame {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
}

export interface EngravedNeume {
  /** Position among the score's neumes. */
  readonly index: number;
  /** The layout's name for it, which its drawing carries as `data-neume`. */
  readonly id: string;
  /** The timeline events it draws, in order. */
  readonly eventIDs: readonly string[];
  /** How many notes it draws and sings. */
  readonly noteCount: number;
  /** The syllable sung to it; empty within a melisma. */
  readonly lyric: string;
  readonly lineIndex: number;
  readonly inkFrame: Frame;
  /** Where a tap counts as this neume: never smaller than a fingertip. */
  readonly hitFrame: Frame;
}

export interface EngravedLine {
  readonly top: number;
  readonly bottom: number;
}

export interface Engraving {
  readonly scoreID: string;
  readonly width: number;
  readonly height: number;
  readonly scale: number;
  /** The drawing. It is created once and moved into the page by its view. */
  readonly svg: SVGSVGElement;
  readonly neumes: readonly EngravedNeume[];
  /**
   * The band of the drawing each staff and its words occupy, from the head
   * of the drawing down. The bands meet, so that a page may break between
   * any two of them and nowhere else.
   */
  readonly lines: readonly EngravedLine[];
  /** The score as it was read, its notes named by the timeline's events. */
  readonly score: GregorianScore;
  readonly layout: GregorianLayout;
}

let fontsReady: Promise<void> | null = null;

/**
 * Lyrics are measured with the page's fonts, so engraving before EB Garamond
 * has loaded would break every line in the wrong place.
 */
export function notationFontsReady(): Promise<void> {
  fontsReady ??= Promise.all([
    document.fonts.load(`${lyricFontSize}px ${notationFontFamily}`),
    document.fonts.load(`700 ${lyricFontSize}px ${notationFontFamily}`),
    document.fonts.load(`italic ${lyricFontSize}px ${notationFontFamily}`),
  ]).then(() => undefined);
  return fontsReady;
}

let layoutEngine: GregorianEngravingLayoutEngine | null = null;

/** The engine, measuring lyrics with a canvas in the page's own EB Garamond. */
function engine(): GregorianEngravingLayoutEngine {
  layoutEngine ??= new GregorianEngravingLayoutEngine(
    createCanvasLyricMeasurer(),
  );
  return layoutEngine;
}

interface ParsedScore {
  readonly gabc: string;
  readonly score: GregorianScore;
}

const parsedScores = new Map<string, ParsedScore>();
const parsedScoreLimit = 256;

/**
 * The score as the engraver reads it: with its compiled timeline, which names
 * its notes one for one. Throws if the two disagree.
 */
export function parsedScore(chant: ChantScore): GregorianScore {
  const cached = parsedScores.get(chant.id);
  if (cached && cached.gabc === chant.gabc) {
    parsedScores.delete(chant.id);
    parsedScores.set(chant.id, cached);
    return cached.score;
  }
  const score = GregorianScoreParser.parse(chant.gabc, {
    scoreId: chant.id,
    timeline: {
      events: chant.timeline.events.map((event) => ({
        id: event.id,
        syllableId: event.syllableID,
        relativePitch: event.relativePitch,
      })),
    },
  });
  parsedScores.set(chant.id, { gabc: chant.gabc, score });
  if (parsedScores.size > parsedScoreLimit) {
    parsedScores.delete(parsedScores.keys().next().value!);
  }
  return score;
}

function frame(rect: GregorianRect): Frame {
  return { x: rect.left, y: rect.top, width: rect.width, height: rect.height };
}

/** The drawing, as an element of this page. */
function drawing(layout: GregorianLayout): SVGSVGElement {
  const template = document.createElement("template");
  template.innerHTML = gregorianScoreSVG(layout, { ink: "currentColor" });
  const svg = template.content.firstElementChild as SVGSVGElement;
  // The stylesheet styles every score alike.
  svg.querySelector("style")?.remove();
  svg.setAttribute("aria-hidden", "true");
  svg.setAttribute("focusable", "false");
  return svg;
}

export interface EngraveOptions {
  /** The reader's notation scale. */
  readonly scale?: number;
  /**
   * Whether the score is a piece the books open with an initial
   * (`OfficeSectionKinds.opensPiece`); it takes one only where it has a
   * mode to head it.
   */
  readonly opensPiece?: boolean;
  /**
   * The pixels to a point of the screen it is drawn on, to which its lines
   * are fitted; null for paper, where they are drawn where they fall.
   */
  readonly displayScale?: number | null;
}

/**
 * Engraves a chant for a column of the given width.
 * Throws if the notation cannot be drawn; the caller shows the text instead.
 * Call only after `notationFontsReady()` has resolved.
 */
export function engrave(
  chant: ChantScore,
  width: number,
  options: EngraveOptions = {},
): Engraving {
  const scale = options.scale ?? 1;
  const score = parsedScore(chant);
  const openingLabel = GregorianEngravingLayoutEngine.openingLabel(
    chant.mode ?? null,
    options.opensPiece ?? false,
  );
  const layout = engine().layout(
    score,
    Math.max(minimumWidth, Math.floor(width)),
    {
      metrics: {
        notationScale: scale,
        displayScale:
          options.displayScale === undefined
            ? window.devicePixelRatio || 1
            : options.displayScale,
      },
      openingLabel,
      opensPiece: openingLabel !== null && (options.opensPiece ?? false),
    },
  );
  const { width: drawnWidth, height: drawnHeight } = layout.size;

  // Each staff's band reaches down to the foot of its words, which is where
  // the drawing puts what follows into the next staff's group.
  const lines: EngravedLine[] = layout.staffs.map((staff, index) => ({
    top: index === 0 ? 0 : layout.staffs[index - 1].systemFrame.bottom,
    bottom:
      index + 1 < layout.staffs.length ? staff.systemFrame.bottom : drawnHeight,
  }));

  return {
    scoreID: chant.id,
    width: drawnWidth,
    height: drawnHeight,
    scale,
    svg: drawing(layout),
    neumes: layout.neumes.map((neume, index) => ({
      index,
      id: neume.id,
      eventIDs: neume.eventIds,
      noteCount: neume.noteCount,
      lyric: neume.lyric,
      lineIndex: neume.lineIndex,
      inkFrame: frame(neume.inkFrame),
      hitFrame: frame(neume.hitFrame),
    })),
    lines,
    score,
    layout,
  };
}

/** A note the drawing sets to be sung. */
export interface DrawnNote {
  readonly eventID: string;
  /**
   * The pitch it is drawn at, counted in staff steps from the GABC letter
   * `h`, as the timeline's `relativePitch` is.
   */
  readonly pitch: number;
}

/**
 * The notes drawn to be sung, in order: as many for an event as the GABC
 * writes it (`hvv`, `hsss`), and none for a custos.
 */
export function drawnNotes(engraving: Engraving): DrawnNote[] {
  return engraving.score.neumes.flatMap((neume) =>
    neume.notes.flatMap((note) =>
      Array.from({ length: note.writtenNoteCount }, () => ({
        eventID: note.id,
        pitch: note.pitch - 7,
      })),
    ),
  );
}

/**
 * What to light while an event is sung: the neume that holds it, and the
 * neumes of its syllable, whose words are lit with it. Null for a note the
 * drawing does not hold.
 */
export function sungParts(
  engraving: Engraving,
  eventID: string,
): { neume: EngravedNeume; syllableNeumeIDs: ReadonlySet<string> } | null {
  const highlight = GregorianScoreHighlight.of(
    eventID,
    engraving.score,
    engraving.layout,
  );
  const neume = highlight
    ? engraving.neumes.find((candidate) => candidate.id === highlight.neume.id)
    : undefined;
  return highlight && neume
    ? { neume, syllableNeumeIDs: highlight.syllableNeumeIds }
    : null;
}

/**
 * The neume a tap at a point in the drawing's own coordinates selects: the
 * nearest of those whose tap target contains it.
 */
export function neumeAt(
  engraving: Engraving,
  x: number,
  y: number,
): EngravedNeume | null {
  let best: EngravedNeume | null = null;
  let bestDistance = Number.POSITIVE_INFINITY;
  for (const neume of engraving.neumes) {
    const frame = neume.hitFrame;
    if (x < frame.x || x > frame.x + frame.width) continue;
    if (y < frame.y || y > frame.y + frame.height) continue;
    const deltaX = x - (frame.x + frame.width / 2);
    const deltaY = y - (frame.y + frame.height / 2);
    const distance = deltaX * deltaX + deltaY * deltaY;
    if (distance < bestDistance) {
      best = neume;
      bestDistance = distance;
    }
  }
  return best;
}

/** How the reader names a neume to assistive technology. */
export function neumeLabel(neume: EngravedNeume): string {
  const lyric = neume.lyric.length === 0 ? "Chant" : neume.lyric;
  const count = neume.noteCount;
  return count === 1
    ? `${lyric}, one-note neume`
    : `${lyric}, ${count}-note neume`;
}
