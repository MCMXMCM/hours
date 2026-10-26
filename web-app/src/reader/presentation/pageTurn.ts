/**
 * The turning of the reader's pages where it shows both languages: the
 * Latin on one page and the English on another, the reader's place carried
 * from each to the other. The web counterpart of `OfficeReaderPageTurn` in
 * `HoursApp/OfficeReaderPager.swift`.
 */

import { OfficeReaderSectionBuilder } from "./sectionBuilder.ts";

/** A page of the reader: the Latin, or the English. */
export type ReaderPageName = "latin" | "english";

/** The other page of a reader of both languages. */
export function facingPage(page: ReaderPageName): ReaderPageName {
  return page === "latin" ? "english" : "latin";
}

/** The top and foot of a part of a page on the screen. */
export interface PartBounds {
  readonly top: number;
  readonly bottom: number;
}

/**
 * Where the reader reads on a page: the part the reading line falls in,
 * how far into it (0 at its top, 1 at its foot), and, where the line falls
 * between two parts, how far below the top of the next it lies.
 */
export interface ReadingPlace {
  readonly sectionID: string;
  readonly progress: number;
  readonly offset: number;
}

export const OfficeReaderPageTurn = {
  /**
   * The rest of a psalm that compact psalmody sets after the verse sung
   * from its score. A page without the chant reads it in the psalm itself.
   */
  continuationSuffix: OfficeReaderSectionBuilder.compactContinuationSuffix,

  /** The width along either edge of the window left to the browser's own
   * swipes, back and forward. */
  edgeWidth: 24,

  /** How much farther across than up or down a drag must run to turn the
   * page: twice, within some 27° of the horizontal. A drag nearer the
   * vertical scrolls. */
  horizontalRatio: 2,

  /**
   * The section of a page that stands for a section of the other: the same
   * section, or, for the rest of a psalm in compact psalmody, the psalm.
   */
  counterpart(
    sectionID: string,
    sectionIDs: ReadonlySet<string>,
  ): string | null {
    if (sectionIDs.has(sectionID)) return sectionID;
    const suffix = OfficeReaderPageTurn.continuationSuffix;
    if (!sectionID.endsWith(suffix)) return null;
    const base = sectionID.slice(0, -suffix.length);
    return sectionIDs.has(base) ? base : null;
  },

  /** How far down the reading area the reading line lies, where the eye
   * rests on what is being read: a quarter of the way. */
  readingLineFraction: 0.25,

  /**
   * Where the reader reads on a page whose parts stand at `parts` (their
   * tops and feet on the screen), the reading line at `lineY`: the part the
   * line falls in, and how far into it, so that the facing page can show
   * the same words there, however much longer or shorter its part runs. A
   * psalm that compact psalmody divides is read as one.
   */
  readingPlace(
    parts: ReadonlyMap<string, PartBounds>,
    lineY: number,
  ): ReadingPlace | null {
    const merged = new Map<string, PartBounds>();
    const suffix = OfficeReaderPageTurn.continuationSuffix;
    for (const [sectionID, bounds] of parts) {
      if (!(bounds.bottom > bounds.top)) continue;
      const id = sectionID.endsWith(suffix)
        ? sectionID.slice(0, -suffix.length)
        : sectionID;
      const known = merged.get(id);
      merged.set(
        id,
        known
          ? {
              top: Math.min(known.top, bounds.top),
              bottom: Math.max(known.bottom, bounds.bottom),
            }
          : bounds,
      );
    }
    let next: [string, PartBounds] | null = null;
    for (const [id, bounds] of merged) {
      if (bounds.top <= lineY && lineY < bounds.bottom) {
        return {
          sectionID: id,
          progress: (lineY - bounds.top) / (bounds.bottom - bounds.top),
          offset: 0,
        };
      }
      if (bounds.top > lineY && (!next || bounds.top < next[1].top)) {
        next = [id, bounds];
      }
    }
    // Between two parts, at its distance above the next.
    return next
      ? { sectionID: next[0], progress: 0, offset: lineY - next[1].top }
      : null;
  },

  /**
   * Where a part of a page should stand for the reader to read at a place:
   * the part that stands for the place's own, and the height of its top on
   * the screen. A psalm this page divides is placed by its first verse, the
   * whole psalm running on from it.
   */
  placement(
    place: ReadingPlace,
    parts: ReadonlyMap<string, PartBounds>,
    lineY: number,
  ): { readonly sectionID: string; readonly top: number } | null {
    const id = OfficeReaderPageTurn.counterpart(
      place.sectionID,
      new Set(parts.keys()),
    );
    const bounds = id === null ? undefined : parts.get(id);
    if (id === null || !bounds) return null;
    let height = bounds.bottom - bounds.top;
    const rest = parts.get(id + OfficeReaderPageTurn.continuationSuffix);
    if (rest) height = rest.bottom - bounds.top;
    return {
      sectionID: id,
      top: lineY - place.progress * height - place.offset,
    };
  },

  /**
   * Whether a touch begun at `startX` may turn the page: away from either
   * edge of a window `width` wide.
   */
  beginsAwayFromEdges(startX: number, width: number): boolean {
    const edge = OfficeReaderPageTurn.edgeWidth;
    return startX > edge && startX < width - edge;
  },

  /** Whether a drag so far runs clearly across rather than up or down. */
  isHorizontal(dx: number, dy: number): boolean {
    return (
      dx !== 0 &&
      Math.abs(dx) >= OfficeReaderPageTurn.horizontalRatio * Math.abs(dy)
    );
  },

  /**
   * The page a drag let go turns to, if it turns: right to left to the
   * English, left to right back to the Latin, carried a sixth of the way
   * across or flung.
   */
  turnedTo(
    from: ReaderPageName,
    dx: number,
    dy: number,
    milliseconds: number,
    width: number,
  ): ReaderPageName | null {
    if (!OfficeReaderPageTurn.isHorizontal(dx, dy)) return null;
    const toward = from === "latin" ? -1 : 1;
    const distance = dx * toward;
    const speed = distance / Math.max(1, milliseconds);
    if (distance <= 0) return null;
    return distance > Math.max(56, width / 6) || (distance > 32 && speed > 0.5)
      ? facingPage(from)
      : null;
  },
};
