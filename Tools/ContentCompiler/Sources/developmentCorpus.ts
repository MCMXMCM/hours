import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { normalize, sep } from "node:path";
import { compileCorpus } from "./compiler.ts";
import {
  classifyImportedSection,
  loadSnapshotDirectory,
  type ImportedOfficeCandidate
} from "./divinumImporter.ts";
import { withResolvedEveningContexts } from "./eveningContext.ts";
import {
  officeHours,
  type CorpusInput,
  type LiturgicalDay,
  type LocalDay,
  type OfficeDocument,
  type OfficeHour,
  type OfficeSection,
  type OfficeSectionKind
} from "./types.ts";

const titles: Record<OfficeHour, { latin: string; english: string }> = {
  matins: { latin: "Ad Matutinum", english: "Matins" },
  lauds: { latin: "Ad Laudes", english: "Lauds" },
  prime: { latin: "Ad Primam", english: "Prime" },
  terce: { latin: "Ad Tertiam", english: "Terce" },
  sext: { latin: "Ad Sextam", english: "Sext" },
  none: { latin: "Ad Nonam", english: "None" },
  vespers: { latin: "Ad Vesperas", english: "Vespers" },
  compline: { latin: "Ad Completorium", english: "Compline" }
};

function localDay(isoDate: string): LocalDay {
  const [year, month, day] = isoDate.split("-").map(Number);
  if (!year || !month || !day) throw new Error(`Invalid snapshot date ${isoDate}`);
  return { year, month, day };
}

function rank(value: string): LiturgicalDay["rank"] {
  if (/\bI\.\s*classis\b/i.test(value)) return "firstClass";
  if (/\bII\.\s*classis\b/i.test(value)) return "secondClass";
  if (/\bIII\.\s*classis\b/i.test(value)) return "thirdClass";
  if (/\bIV\.\s*classis\b/i.test(value)) return "fourthClass";
  return null;
}

function sectionKind(section: ImportedOfficeCandidate["sections"][number]): OfficeSectionKind {
  return classifyImportedSection(section);
}

function stableID(value: string): string {
  return value
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .replace(/[^a-zA-Z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .toLowerCase();
}

function withoutLeadingHeading(value: string | null, headings: string[]): string | null {
  if (value === null) return null;
  const paragraphs = value.split(/\n\n+/);
  if (
    paragraphs.length > 1
    && headings.some(heading => paragraphs[0].localeCompare(
      heading,
      "en",
      { sensitivity: "base" }
    ) === 0)
  ) {
    return paragraphs.slice(1).join("\n\n");
  }
  return value;
}

function document(
  candidate: ImportedOfficeCandidate,
  evening: LiturgicalDay["eveningContext"]
): OfficeDocument {
  const sections: OfficeSection[] = candidate.sections.map((section, index) => ({
    id: `${candidate.hour}-${stableID(section.upstreamID) || index + 1}`,
    kind: sectionKind(section),
    title: section.titleLatin,
    titleEnglish: section.titleEnglish || null,
    rubric: section.rubricLatin ?? null,
    rubricEnglish: section.rubricEnglish ?? null,
    latin: section.latin,
    english: section.english || null,
    chant: null
  }));
  if (
    candidate.hour === "compline"
    && sections[0]
    && /^incipit$/i.test(sections[0].title)
    && /iube,\s*d[oó]mine,\s*bened/i.test(sections[0].latin)
    && sections.some(section => /lectio\s+brevis/i.test(section.title))
  ) {
    sections[0] = {
      ...sections[0],
      title: "Lectio brevis",
      latin: withoutLeadingHeading(sections[0].latin, ["Incipit"])!,
      english: withoutLeadingHeading(sections[0].english ?? null, ["Start", "Beginning"])
    };
  }
  return {
    id: `${candidate.date}-${candidate.hour}`,
    date: localDay(candidate.date),
    hour: candidate.hour,
    titleLatin: titles[candidate.hour].latin,
    titleEnglish: titles[candidate.hour].english,
    contextLabel: candidate.observanceLatin,
    sourceVersion: "Rubrics 1960 - 1960 · pinned Divinum Officium development import",
    format: "legacyReconstructed",
    observance: {
      observanceID: `divinum-officium/${candidate.date}/${stableID(candidate.observanceLatin)}`,
      titleLatin: candidate.observanceLatin,
      titleEnglish: null,
      rank: rank(candidate.rankLatin),
      color: null,
      season: candidate.seasonLatin,
      eveningContext: candidate.hour === "vespers" ? evening : null,
      commemorations: []
    },
    sections
  };
}

function eveningContext(
  daytime: ImportedOfficeCandidate,
  vespers: ImportedOfficeCandidate | undefined
): LiturgicalDay["eveningContext"] {
  if (!vespers || vespers.observanceLatin === daytime.observanceLatin) {
    return null;
  }
  return "firstVespers";
}

function seedDocuments(path: string | undefined): Map<string, OfficeDocument> {
  if (!path) return new Map();
  const seed = JSON.parse(readFileSync(path, "utf8")) as CorpusInput;
  return new Map(seed.offices.map(office => [`${office.date.year}-${office.date.month}-${office.date.day}:${office.hour}`, office]));
}

export function developmentCorpusFromSnapshots(options: {
  snapshots: string;
  seed?: string;
}): CorpusInput {
  const imported = loadSnapshotDirectory(options.snapshots);
  const byDate = Map.groupBy(imported.offices, office => office.date);
  const seeded = seedDocuments(options.seed);
  const days: LiturgicalDay[] = [];
  const offices: OfficeDocument[] = [];

  for (const [date, candidates] of [...byDate].sort(([a], [b]) => a.localeCompare(b))) {
    const byHour = new Map(candidates.map(candidate => [candidate.hour, candidate]));
    const daytime = byHour.get("matins") ?? byHour.get("lauds") ?? candidates[0];
    const dateValue = localDay(date);
    const vespersContext = eveningContext(daytime, byHour.get("vespers"));
    days.push({
      date: dateValue,
      observanceID: `divinum-officium/${date}/${stableID(daytime.observanceLatin)}`,
      titleLatin: daytime.observanceLatin,
      titleEnglish: null,
      rank: rank(daytime.rankLatin),
      color: null,
      season: daytime.seasonLatin,
      eveningContext: vespersContext,
      commemorations: [],
      sourceVersion: "Rubrics 1960 - 1960"
    });
    for (const hour of officeHours) {
      const candidate = byHour.get(hour);
      if (!candidate) continue;
      const seedKey = `${dateValue.year}-${dateValue.month}-${dateValue.day}:${hour}`;
      const seed = seeded.get(seedKey);
      offices.push(
        seed
          ? { ...seed, date: dateValue, id: `${date}-${hour}` }
          : document(candidate, vespersContext)
      );
    }
  }

  if (days.length === 0) throw new Error("No snapshot days were imported");
  const first = days[0].date;
  const last = days.at(-1)!.date;
  const input: CorpusInput = {
    manifest: {
      schemaVersion: 2,
      corpusVersion: `development-do-${imported.revision.slice(0, 12)}`,
      minimumAppVersion: "0.1.0",
      createdAt: "2026-07-24T00:00:00Z",
      rubrics: "Rubrics 1960 - 1960",
      sources: [{
        name: "Divinum Officium",
        revision: imported.revision,
        license: "MIT",
        url: "https://github.com/DivinumOfficium/divinum-officium",
        checksum: createHash("sha256")
          .update(imported.offices.map(office => office.sourceSHA256).join("\n"))
          .digest("hex")
      }],
      coverage: {
        startDate: first,
        endDate: last,
        expectedOfficeCount: days.length * officeHours.length,
        generatedOfficeCount: offices.length,
        unresolvedScoreCount: 0,
        ambiguousScoreCount: 0,
        isSample: true
      },
      packSHA256: "",
      signature: ""
    },
    days,
    offices
  };
  return withResolvedEveningContexts(input);
}

export function compileDevelopmentSnapshots(options: {
  snapshots: string;
  output: string;
  seed?: string;
}): string[] {
  const bundledSuffix = ["HoursApp", "Resources", "base-office.sqlite"].join(sep);
  if (normalize(options.output).endsWith(bundledSuffix)) {
    throw new Error(
      "Divinum Officium snapshots are text-only and cannot replace the bundled scored corpus"
    );
  }
  return compileCorpus(developmentCorpusFromSnapshots(options), options.output, true);
}

export function exportDevelopmentSnapshots(options: {
  snapshots: string;
  output: string;
  seed?: string;
}): void {
  const corpus = developmentCorpusFromSnapshots(options);
  writeFileSync(options.output, `${JSON.stringify(corpus, null, 2)}\n`);
}
