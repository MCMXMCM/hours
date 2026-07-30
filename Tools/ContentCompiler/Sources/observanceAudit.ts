import { createHash } from "node:crypto";
import type { LoadedScoredOffice } from "./breviariumGregorianum.ts";
import type { ImportedOfficeCandidate } from "./divinumImporter.ts";
import type {
  EveningContext,
  LiturgicalRank,
  OfficeHour
} from "./types.ts";

export interface ObservanceExpectation {
  date: string;
  hour: OfficeHour;
  available: boolean;
  titleLatin?: string;
  titleEnglish?: string | null;
  rank?: LiturgicalRank | null;
  eveningContext?: EveningContext | null;
  commemorations?: string[];
  reason?: string;
  independentSource?: {
    observanceLatin: string;
    visibleContentDigest: string;
    requiredLatinIncipits: string[];
  };
}

function officeKey(value: { date: string; hour: OfficeHour }): string {
  return `${value.date}:${value.hour}`;
}

export function canonicalImportedOfficeDigest(
  office: ImportedOfficeCandidate
): string {
  const visibleContent = office.sections.map(section => ({
    upstreamID: section.upstreamID,
    titleLatin: section.titleLatin,
    titleEnglish: section.titleEnglish,
    rubricLatin: section.rubricLatin ?? null,
    rubricEnglish: section.rubricEnglish ?? null,
    latin: section.latin,
    english: section.english
  }));
  return createHash("sha256")
    .update(JSON.stringify(visibleContent))
    .digest("hex");
}

export function auditExpectedObservances(
  records: LoadedScoredOffice[],
  expectations: ObservanceExpectation[],
  independentOffices: ImportedOfficeCandidate[] = []
): void {
  const recordsByKey = new Map(records.map(record => [officeKey(record), record]));
  const independentByKey = new Map(
    independentOffices.map(office => [officeKey(office), office])
  );
  const expectationKeys = expectations.map(officeKey);
  if (new Set(expectationKeys).size !== expectationKeys.length) {
    throw new Error("High-risk observance expectations contain duplicate date/hour keys");
  }

  const failures: string[] = [];
  for (const expectation of expectations) {
    const key = officeKey(expectation);
    const record = recordsByKey.get(key);
    const independentExpectation = expectation.independentSource;
    if (independentExpectation) {
      const independentOffice = independentByKey.get(key);
      if (!independentOffice) {
        failures.push(`${key} is missing its independent Divinum Officium validation`);
      } else {
        const digest = canonicalImportedOfficeDigest(independentOffice);
        if (independentOffice.observanceLatin !== independentExpectation.observanceLatin) {
          failures.push(
            `${key} independent observance changed from `
            + `"${independentExpectation.observanceLatin}" to `
            + `"${independentOffice.observanceLatin}"`
          );
        }
        if (digest !== independentExpectation.visibleContentDigest) {
          failures.push(
            `${key} independent visible content changed:\n`
            + `expected ${independentExpectation.visibleContentDigest}\n`
            + `actual   ${digest}`
          );
        }
        const latin = independentOffice.sections.map(section => section.latin).join("\n");
        for (const incipit of independentExpectation.requiredLatinIncipits) {
          if (!latin.includes(incipit)) {
            failures.push(`${key} is missing special proper text "${incipit}"`);
          }
        }
      }
    }
    if (!expectation.available) {
      if (record) failures.push(`${key} was expected to remain an explicit source gap`);
      if (!expectation.reason?.trim()) {
        failures.push(`${key} source gap has no recorded reason`);
      }
      continue;
    }
    if (!record) {
      failures.push(`${key} is missing`);
      continue;
    }

    const actual = {
      titleLatin: record.observance.titleLatin,
      titleEnglish: record.observance.titleEnglish ?? null,
      rank: record.observance.rank ?? null,
      eveningContext: record.observance.eveningContext ?? null,
      commemorations: record.observance.commemorations.map(item => item.titleLatin)
    };
    const expected = {
      titleLatin: expectation.titleLatin,
      titleEnglish: expectation.titleEnglish ?? null,
      rank: expectation.rank ?? null,
      eveningContext: expectation.eveningContext ?? null,
      commemorations: expectation.commemorations ?? []
    };
    if (JSON.stringify(actual) !== JSON.stringify(expected)) {
      failures.push(
        `${key} metadata changed:\n`
        + `expected ${JSON.stringify(expected)}\n`
        + `actual   ${JSON.stringify(actual)}`
      );
    }
  }

  if (failures.length > 0) {
    throw new Error(
      `High-risk observance audit failed for ${failures.length} expectation(s):\n`
      + failures.map(failure => `- ${failure}`).join("\n")
    );
  }
}
