// What the Home header says of a day, parallel to
// `HoursApp/HomeHeaderPresentation.swift`.

import {
  ObservanceTitle,
  Ranks,
  type Commemoration,
  type LiturgicalDay,
  type LiturgicalRank,
  type OfficeDocument,
  type OfficeObservance,
} from "@/core/models.ts";
import { icuWordBoundary } from "@/core/swiftString.ts";

export interface HomeHeaderPresentation {
  readonly rank: LiturgicalRank | null;
  readonly rankDisplayName: string | null;
  readonly titleLatin: string;
  readonly commemorations: readonly Commemoration[];
  readonly officeContext: string | null;
}

const hebdomada = new RegExp(`${icuWordBoundary}Hebd${icuWordBoundary}`, "giu");
const quadragesima = new RegExp(
  `${icuWordBoundary}Quadr${icuWordBoundary}`,
  "giu",
);

function normalizedObservanceTitle(value: string): string {
  return value
    .replace(hebdomada, "Hebdomadam")
    .replace(quadragesima, "Quadragesima");
}

function sameObservance(
  day: LiturgicalDay,
  officeObservance: OfficeObservance,
): boolean {
  if (officeObservance.observanceID === day.observanceID) return true;
  return (
    normalizedObservanceTitle(officeObservance.titleLatin) ===
    normalizedObservanceTitle(day.titleLatin)
  );
}

function officeContext(
  day: LiturgicalDay,
  office: OfficeDocument | null,
): string | null {
  const observance = office?.observance;
  const eveningContext = observance?.eveningContext;
  if (!office || !observance || !eveningContext) return null;

  const followsEveningOffice = office.hour === "compline";
  const prefix = followsEveningOffice ? "After " : "";
  const namesAnotherObservance = !sameObservance(day, observance);
  const title = ObservanceTitle.latin(observance.titleLatin);

  switch (eveningContext) {
    case "firstVespers": {
      const label = `${prefix}First Vespers`;
      return namesAnotherObservance ? `${label} · ${title}` : label;
    }
    case "secondVespers":
      return namesAnotherObservance
        ? `${prefix}Second Vespers · ${title}`
        : null;
    case "ferialVespers": {
      if (!namesAnotherObservance) return null;
      const label = followsEveningOffice ? "After Vespers" : "Vespers";
      return `${label} · ${title}`;
    }
    default:
      return null;
  }
}

export function homeHeaderPresentation(
  day: LiturgicalDay,
  office: OfficeDocument | null,
): HomeHeaderPresentation {
  return {
    rank: day.rank ?? null,
    rankDisplayName: Ranks.rankLabel(day),
    titleLatin: ObservanceTitle.latin(day.titleLatin),
    commemorations: day.commemorations,
    officeContext: officeContext(day, office),
  };
}
