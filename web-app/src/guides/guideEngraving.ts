// The notation of the guide's examples: engraved as the reader's is, and
// marked where an example points to its notes.

import type { ChantScore } from "@/core/models.ts";
import { engrave, type Engraving } from "@/notation/engraver.ts";
import {
  ChantGuideAnnotationOverlay,
  type ChantGuideAnnotationMarks,
} from "./chantGuideExample.ts";

/** An example's drawing, or the reason there is none. */
export type GuideScorePreparation = Engraving | { error: string };

/**
 * Engraves an example for a column of the given width. An example is set at
 * the notation's ordinary size, as the native guide sets it at the ordinary
 * size of type. Call only once the notation's typeface has loaded.
 */
export function prepareGuideScore(
  score: ChantScore,
  width: number,
): GuideScorePreparation {
  try {
    return engrave(score, width);
  } catch (error) {
    return { error: error instanceof Error ? error.message : String(error) };
  }
}

/**
 * Where the notes of the given events are drawn, and what marks them: a
 * frame about each, and a bracket over those that share a staff, in the
 * drawing's own coordinates.
 */
export function annotationMarks(
  engraving: Engraving,
  eventIDs: readonly string[],
): ChantGuideAnnotationMarks {
  const selected = new Set(eventIDs);
  const placements = engraving.layout.events
    .filter((event) => selected.has(event.eventId))
    .map((event) => ({
      frame: {
        x: event.frame.left,
        y: event.frame.top,
        width: event.frame.width,
        height: event.frame.height,
      },
      lineIndex: event.lineIndex,
    }));
  const staffs = engraving.layout.staffs
    .filter((staff) =>
      placements.some((placement) => placement.lineIndex === staff.index),
    )
    .map((staff) => ({ index: staff.index, minY: staff.frame.top }));
  return ChantGuideAnnotationOverlay.marks(placements, staffs);
}
