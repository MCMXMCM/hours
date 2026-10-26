import type { ChantScore } from "@/core/models.ts";
import { engrave, type Engraving } from "@/notation/engraver.ts";

export type ScorePreparation = Engraving | { error: string };

/** Identifies one preparation of an office's scores, as the native reader's key does. */
export interface ScorePreparationKey {
  readonly officeID: string;
  readonly scoreSignature: string;
  readonly width: number;
  readonly scale: number;
}

export function samePreparation(
  a: ScorePreparationKey | null,
  b: ScorePreparationKey,
): boolean {
  return (
    a !== null &&
    a.officeID === b.officeID &&
    a.scoreSignature === b.scoreSignature &&
    a.width === b.width &&
    a.scale === b.scale
  );
}

/**
 * Engraves every score of an office for one column width. A score that
 * cannot be drawn is reported in its place and does not stop the others.
 *
 * `pieceScoreIDs` are the scores that open a piece, and so take an initial
 * (`OfficeSectionKinds.opensPiece`); `displayScale` is null for paper.
 */
export function prepareScores(
  scores: readonly ChantScore[],
  width: number,
  scale: number,
  pieceScoreIDs: ReadonlySet<string>,
  displayScale?: number | null,
): Map<string, ScorePreparation> {
  const prepared = new Map<string, ScorePreparation>();
  for (const score of scores) {
    try {
      prepared.set(
        score.id,
        engrave(score, width, {
          scale,
          opensPiece: pieceScoreIDs.has(score.id),
          displayScale,
        }),
      );
    } catch (error) {
      prepared.set(score.id, {
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }
  return prepared;
}
