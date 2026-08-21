import type { OfficeDocument, OfficeSection } from "./types.ts";
import { parenthesizeLiturgicalDirections } from "./inlineRubrics.ts";

export const latinPrimeMartyrologyProclamationToken =
  "{{hours:prime-martyrology-latin-proclamation}}";
export const englishPrimeMartyrologyProclamationToken =
  "{{hours:prime-martyrology-english-proclamation}}";

const latinProclamation = /Luna\s+[^\n.]+?\s+Anno(?:\s+Dómini)?\s+\d{4}/giu;
const englishProclamation = /(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2}(?:st|nd|rd|th)\s+\d{4},\s+the\s+\d{1,2}(?:st|nd|rd|th)\s+day\s+of\s+the\s+Moon,/giu;
const leadingLatinMartyrologyMetadata =
  /^\s*Martyrologium\s*\{\s*anticipatur\s*\}\s*/iu;
const leadingEnglishMartyrologyMetadata =
  /^\s*Martyrology\s*\{\s*anticipated\s*\}\s*/iu;

function normalizeSection(
  section: OfficeSection,
  materializesPrimeCalendarText: boolean
): OfficeSection {
  const latin = parenthesizeLiturgicalDirections(section.latin);
  const english = section.english
    ? parenthesizeLiturgicalDirections(section.english)
    : null;
  if (!materializesPrimeCalendarText) {
    return { ...section, latin, english };
  }
  return {
    ...section,
    latin: latin
      .replace(leadingLatinMartyrologyMetadata, "")
      .replace(latinProclamation, latinPrimeMartyrologyProclamationToken),
    english: english
      ?.replace(leadingEnglishMartyrologyMetadata, "")
      .replace(englishProclamation, englishPrimeMartyrologyProclamationToken)
      ?? null
  };
}

export function normalizeDynamicOfficeText(office: OfficeDocument): OfficeDocument {
  return {
    ...office,
    sections: office.sections.map(section => normalizeSection(
      section,
      office.hour === "prime"
    ))
  };
}
