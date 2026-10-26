import type {
  ChantScore,
  OfficeDocument,
  OfficeSection,
} from "@/core/models.ts";
import {
  OfficeReaderOutlineBuilder,
  type OfficeReaderOutlineEntry,
} from "./outline.ts";
import { OfficeReaderSectionBuilder } from "./sectionBuilder.ts";

/** The stored properties of Swift's `OfficeReaderPresentation`. */
export interface OfficeReaderPresentationValue {
  readonly officeID: string;
  readonly sections: OfficeSection[];
  readonly scores: ChantScore[];
  /**
   * Swift's `Hasher` value, here a string: it says only whether the set of
   * scores changed, and is not comparable with the Swift value.
   */
  readonly scoreSignature: string;
  readonly outlineEntries: OfficeReaderOutlineEntry[];
}

/**
 * In place of Swift's `Hasher`: a deterministic digest of what is combined
 * into it, in the order it is combined.
 */
class SignatureHasher {
  private high = 0xdeadbeef;
  private low = 0x41c6ce57;

  private mix(unit: number): void {
    this.high = Math.imul(this.high ^ unit, 2654435761);
    this.low = Math.imul(this.low ^ unit, 1597334677);
  }

  combine(value: string | number | null): void {
    // A tag and a length keep adjacent values from running together.
    if (value === null) {
      this.mix(0);
      return;
    }
    const text = typeof value === "number" ? String(value) : value;
    this.mix(typeof value === "number" ? 1 : 2);
    this.mix(text.length);
    for (let index = 0; index < text.length; index += 1) {
      this.mix(text.charCodeAt(index));
    }
  }

  finalize(): string {
    let high = this.high;
    let low = this.low;
    high =
      Math.imul(high ^ (high >>> 16), 2246822507) ^
      Math.imul(low ^ (low >>> 13), 3266489909);
    low =
      Math.imul(low ^ (low >>> 16), 2246822507) ^
      Math.imul(high ^ (high >>> 13), 3266489909);
    return (
      (low >>> 0).toString(16).padStart(8, "0") +
      (high >>> 0).toString(16).padStart(8, "0")
    );
  }
}

/** The sections as shown, and the scores to prepare: none where the chant
 * is not shown (`showsScores`). */
function prepare(
  office: OfficeDocument,
  usesCompactPsalmody = false,
  showsOrdinary = true,
  showsScores = true,
): OfficeReaderPresentationValue {
  const sections = OfficeReaderSectionBuilder.displaySections(
    office.sections,
    office.format,
    usesCompactPsalmody,
    showsOrdinary,
    showsScores,
  );

  const seenScoreIDs = new Set<string>();
  const scores: ChantScore[] = [];
  for (const section of showsScores ? sections : []) {
    const chant = section.chant;
    if (chant == null || seenScoreIDs.has(chant.id)) continue;
    seenScoreIDs.add(chant.id);
    scores.push(chant);
  }
  const hasher = new SignatureHasher();
  for (const score of scores) {
    hasher.combine(score.id);
    hasher.combine(score.gabc);
    hasher.combine(score.mode ?? null);
    hasher.combine(score.timeline.events.length);
  }

  return {
    officeID: office.id,
    sections,
    scores,
    scoreSignature: hasher.finalize(),
    outlineEntries: OfficeReaderOutlineBuilder.entries(sections),
  };
}

export const OfficeReaderPresentation = {
  prepare,
};
