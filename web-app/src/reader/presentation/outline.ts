import type { OfficeSection } from "@/core/models.ts";
import {
  equalsIgnoringCase,
  folding,
  isWhitespace,
  splitOmittingEmpty,
  trimmingWhitespaceAndNewlines,
} from "@/core/swiftString.ts";
import { componentsSeparatedByNonAlphanumerics, swiftInt } from "./strings.ts";

export interface OfficeReaderOutlineEntry {
  readonly id: string;
  readonly title: string;
}

export const OfficeReaderSectionJump = {
  /**
   * Sheet rows must not reuse reader section IDs. `ScrollViewReader`
   * matches the first view with that ID, and the still-presented outline
   * row is in the hierarchy before a lazy hymn has been realized.
   */
  outlineRowID(sectionID: string): string {
    return `office-outline-row-${sectionID}`;
  },
};

function entries(
  sections: readonly OfficeSection[],
): OfficeReaderOutlineEntry[] {
  const result: OfficeReaderOutlineEntry[] = [];
  for (const section of sections) {
    const title = outlineTitle(section);
    if (title.length === 0) continue;
    result.push({
      id: section.id,
      title,
    });
  }
  return result;
}

function outlineTitle(section: OfficeSection): string {
  const title = trimmingWhitespaceAndNewlines(section.title);
  if (title.length > 0) {
    return title;
  }

  // The ordered Matins source stores lesson and Te Deum labels as
  // content inside the broader "Pater" part. Repeated-heading
  // suppression correctly hides that inherited part title, so recover
  // these explicit structural labels for the jump outline itself.
  const latin = trimmingWhitespaceAndNewlines(section.latin);
  if (isNumberedLessonTitle(latin)) {
    return latin;
  }
  const words = normalizedWords(latin);
  if (
    words.length >= 3 &&
    words[0] === "te" &&
    words[1] === "deum" &&
    words[2] === "laudamus"
  ) {
    return "Te Deum";
  }
  return "";
}

function isNumberedLessonTitle(value: string): boolean {
  const parts = splitOmittingEmpty(value, isWhitespace);
  if (!(parts.length === 2 && equalsIgnoringCase(parts[0], "Lectio"))) {
    return false;
  }
  const number = swiftInt(parts[1]);
  if (number === null) {
    return false;
  }
  return number > 0;
}

function normalizedWords(value: string): string[] {
  return componentsSeparatedByNonAlphanumerics(
    folding(value, { caseInsensitive: true, diacriticInsensitive: true }),
  ).filter((word) => word.length > 0);
}

export const OfficeReaderOutlineBuilder = {
  entries,
};
