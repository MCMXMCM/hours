import type {
  ChantScore,
  OfficeSection,
  OfficeSectionKind,
} from "@/core/models.ts";

/**
 * Swift's memberwise `OfficeSection.init`: an argument left out is nil. Every
 * section the presentation makes carries all its fields, nil as `null`.
 */
export function makeOfficeSection(fields: {
  readonly id: string;
  readonly kind: OfficeSectionKind;
  readonly title: string;
  readonly titleEnglish?: string | null;
  readonly rubric?: string | null;
  readonly rubricEnglish?: string | null;
  readonly latin: string;
  readonly english?: string | null;
  readonly chant?: ChantScore | null;
}): OfficeSection {
  return {
    id: fields.id,
    kind: fields.kind,
    title: fields.title,
    titleEnglish: fields.titleEnglish ?? null,
    rubric: fields.rubric ?? null,
    rubricEnglish: fields.rubricEnglish ?? null,
    latin: fields.latin,
    english: fields.english ?? null,
    chant: fields.chant ?? null,
  };
}
