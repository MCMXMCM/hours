import { createHash } from "node:crypto";
import { normalize, sep } from "node:path";
import {
  loadScoredSnapshotDirectory,
  type LoadedScoredOffice
} from "./breviariumGregorianum.ts";
import { canonicalVisibleContentDigest, compileCorpus } from "./compiler.ts";
import { developmentCorpusFromSnapshots } from "./developmentCorpus.ts";
import { requireSameLiturgicalIdentity } from "./liturgicalIdentity.ts";
import {
  curatedOfficePromotions,
  curatedPromotionChecksum
} from "./curatedOfficePromotions.ts";
import type { CorpusInput, OfficeDocument, OfficeSection } from "./types.ts";

function officeKey(value: { date: string; hour: string }): string {
  return `${value.date}:${value.hour}`;
}

function localDateKey(office: OfficeDocument): string {
  const date = office.date;
  return `${String(date.year).padStart(4, "0")}-${String(date.month).padStart(2, "0")}-${String(date.day).padStart(2, "0")}`;
}

function stableID(value: string): string {
  return value
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .replace(/[^a-zA-Z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .toLowerCase();
}

function withoutLeakedGABCCommentMarker(value: string): string {
  return value.replace(/^\s*%\s*/, "");
}

function assertCalendarConcordance(
  office: OfficeDocument,
  source: LoadedScoredOffice
): string {
  const identity = requireSameLiturgicalIdentity(
    office.contextLabel,
    source.observance.titleLatin,
    `Calendar disagreement for ${source.date}:${source.hour}`
  );
  const divinumRank = office.observance?.rank ?? null;
  const referenceRank = source.observance.rank ?? null;
  if (divinumRank !== referenceRank) {
    throw new Error(
      `Rank disagreement for ${source.date}:${source.hour}: `
      + `${divinumRank} versus ${referenceRank}`
    );
  }
  return identity;
}

export function officeWithScoredReference(
  office: OfficeDocument,
  source: LoadedScoredOffice
): OfficeDocument {
  if (!source.orderedSections) {
    throw new Error(
      `Scored snapshot ${source.date}:${source.hour} has no ordered sidecar; recapture it`
    );
  }
  const observanceIdentity = assertCalendarConcordance(office, source);
  const sourceVisibleContentDigest = canonicalVisibleContentDigest(
    source.orderedSections
  );
  if (
    !source.visibleContentDigest
    || source.visibleContentDigest !== sourceVisibleContentDigest
  ) {
    throw new Error(
      `Visible-content golden mismatch for ${source.date}:${source.hour}`
    );
  }
  const sections = source.orderedSections.map((ordered, index) => {
    const {
      sourceOffset: _sourceOffset,
      sourceRole,
      ...section
    } = ordered;
    if (sourceRole !== "chant" || !section.chant) {
      return {
        ...section,
        id: `${source.hour}-ordered-${index}`
      };
    }
    return {
      ...section,
      latin: withoutLeakedGABCCommentMarker(section.latin),
      chant: {
        ...section.chant,
        incipit: withoutLeakedGABCCommentMarker(section.chant.incipit)
      },
      id: `${source.hour}-ordered-${index}`
    };
  });
  const visibleContentDigest = canonicalVisibleContentDigest(sections);
  return {
    ...office,
    contextLabel: source.observance.titleLatin,
    format: "authoritativeOrdered",
    visibleContentDigest,
    observance: {
      observanceID:
        `breviarium-gregorianum/${observanceIdentity}`,
      titleLatin: source.observance.titleLatin,
      titleEnglish: source.observance.titleEnglish,
      rank: source.observance.rank,
      color: null,
      season: office.observance?.season,
      eveningContext: source.observance.eveningContext,
      commemorations: source.observance.commemorations.map(commemoration => ({
        id:
          "breviarium-gregorianum/commemoration/"
          + stableID(commemoration.titleLatin),
        ...commemoration
      }))
    },
    sections
  };
}

function scoreCounts(offices: OfficeDocument[]): { unresolved: number; ambiguous: number } {
  const scores = offices.flatMap(office =>
    office.sections.flatMap(section => section.chant ? [section.chant] : [])
  );
  return {
    unresolved: scores.filter(score =>
      score.reviewStatus === "ambiguous" || score.reviewStatus === "missing"
    ).length,
    ambiguous: scores.filter(score => score.reviewStatus === "ambiguous").length
  };
}

function scoredSnapshotChecksum(
  scored: LoadedScoredOffice[],
  missingOfficeKeys: string[]
): string {
  return createHash("sha256")
    .update(scored.map(record =>
      `${record.sha256}:${record.scoresSHA256 ?? "legacy-inline"}:`
      + `${record.orderedSHA256 ?? "legacy-unordered"}:`
      + `${record.visibleContentDigest ?? "legacy-undigested"}:`
      + `${record.orderedParserVersion ?? "legacy-parser"}`
    ).join("\n"))
    .update(`\nmissing:${missingOfficeKeys.slice().sort().join(",")}`)
    .digest("hex");
}

export function authoritativeOfficesOnly(
  offices: OfficeDocument[],
  authoritativeByOffice: ReadonlyMap<string, OfficeDocument>
): OfficeDocument[] {
  return offices.flatMap(office => {
    const authoritative = authoritativeByOffice.get(
      `${localDateKey(office)}:${office.hour}`
    );
    return authoritative ? [authoritative] : [];
  });
}

export function officesWithUnavailablePlaceholders(
  offices: OfficeDocument[],
  authoritativeByOffice: ReadonlyMap<string, OfficeDocument>
): OfficeDocument[] {
  return offices.map(office => {
    const authoritative = authoritativeByOffice.get(
      `${localDateKey(office)}:${office.hour}`
    );
    if (authoritative) return authoritative;
    return {
      ...office,
      format: "contentUnavailable",
      visibleContentDigest: null,
      observance: office.observance ?? {
        observanceID:
          `unavailable/${localDateKey(office)}/${stableID(office.contextLabel)}`,
        titleLatin: office.contextLabel,
        titleEnglish: null,
        rank: null,
        color: null,
        season: null,
        eveningContext: null,
        commemorations: []
      },
      sections: []
    };
  });
}

export function scoredDevelopmentCorpusFromSnapshots(options: {
  divinumSnapshots: string;
  scoredSnapshots: string;
  requireComplete?: boolean;
}): CorpusInput {
  const corpus = developmentCorpusFromSnapshots({
    snapshots: options.divinumSnapshots
  });
  const scored = loadScoredSnapshotDirectory(options.scoredSnapshots);
  const byOffice = new Map(scored.map(record => [officeKey(record), record]));
  const curated = curatedOfficePromotions(corpus.offices, scored);
  const missing = corpus.offices
    .map(office => `${localDateKey(office)}:${office.hour}`)
    .filter(key => !byOffice.has(key));
  const unpromotedMissing = missing.filter(key => !curated.has(key));
  const empty = scored.filter(record => record.scores.length === 0);
  const unordered = scored.filter(record => !record.orderedSections);
  if (
    (options.requireComplete ?? true)
    && (unpromotedMissing.length > 0 || empty.length > 0 || unordered.length > 0)
  ) {
    const first = unpromotedMissing[0]
      ?? `${empty[0]?.date ?? unordered[0].date}:${empty[0]?.hour ?? unordered[0].hour}`;
    throw new Error(
      `Scored coverage is incomplete: ${unpromotedMissing.length} unpromoted missing pages and `
      + `${empty.length} zero-score offices and ${unordered.length} unordered offices; `
      + `first gap ${first}`
    );
  }

  const authoritativeByOffice = new Map<string, OfficeDocument>(curated);
  const concordanceIssues: string[] = [];
  for (const office of corpus.offices) {
    const key = `${localDateKey(office)}:${office.hour}`;
    const source = byOffice.get(key);
    if (!source) continue;
    try {
      authoritativeByOffice.set(key, officeWithScoredReference(office, source));
    } catch (error) {
      concordanceIssues.push(
        error instanceof Error ? error.message : `${key}: ${String(error)}`
      );
    }
  }
  if (concordanceIssues.length > 0) {
    const detail = concordanceIssues.slice(0, 25).join("\n- ");
    const remainder = concordanceIssues.length > 25
      ? `\n- …and ${concordanceIssues.length - 25} more`
      : "";
    throw new Error(
      `Calendar/content concordance failed for ${concordanceIssues.length} offices:\n`
      + `- ${detail}${remainder}`
    );
  }
  // A missing ordered reference is represented by metadata-only content. It
  // must never inherit the legacy Divinum prayer sections.
  const offices = officesWithUnavailablePlaceholders(
    corpus.offices,
    authoritativeByOffice
  );
  const counts = scoreCounts(offices);
  const sections: OfficeSection[] = offices.flatMap(office => office.sections);
  if (sections.every(section => !section.chant)) {
    throw new Error("Scored development corpus contains no chant");
  }
  const officesByKey = new Map(
    offices.map(office => [`${localDateKey(office)}:${office.hour}`, office])
  );
  const days = corpus.days.map(day => {
    const date = `${String(day.date.year).padStart(4, "0")}-`
      + `${String(day.date.month).padStart(2, "0")}-`
      + String(day.date.day).padStart(2, "0");
    const daytime = officesByKey.get(`${date}:matins`)?.observance
      ?? officesByKey.get(`${date}:lauds`)?.observance;
    const evening = officesByKey.get(`${date}:vespers`)?.observance;
    if (!daytime) {
      throw new Error(`No authoritative daytime observance metadata for ${date}`);
    }
    return {
      ...day,
      observanceID: daytime.observanceID,
      titleLatin: daytime.titleLatin,
      titleEnglish: daytime.titleEnglish,
      rank: daytime.rank,
      color: daytime.color,
      season: daytime.season ?? day.season,
      eveningContext: evening?.eveningContext,
      commemorations: daytime.commemorations
    };
  });
  return {
    ...corpus,
    manifest: {
      ...corpus.manifest,
      corpusVersion: `${corpus.manifest.corpusVersion}-scored-reference`,
      sources: [
        ...corpus.manifest.sources,
        {
          name: "Breviarium Gregorianum concordance",
          revision: "snapshot",
          license: "reference-only; score licenses are recorded per chant",
          url: "https://breviariumgregorianum.com/about.php",
          checksum: scoredSnapshotChecksum(scored, missing)
        },
        ...(curated.size > 0 ? [{
          name: "Curated 2026 source-gap promotions",
          revision: "easter-octave-and-martyrology-v1",
          license: "development assembly; payload licenses recorded per source",
          url: "Docs/MISSING_OFFICE_SOURCES.md",
          checksum: curatedPromotionChecksum()
        }] : [])
      ],
      coverage: {
        ...corpus.manifest.coverage,
        generatedOfficeCount: offices.length,
        authoritativeOfficeCount:
          offices.filter(office => office.format === "authoritativeOrdered").length,
        unresolvedScoreCount: counts.unresolved,
        ambiguousScoreCount: counts.ambiguous
      }
    },
    days,
    offices
  };
}

export function compileScoredDevelopmentSnapshots(options: {
  divinumSnapshots: string;
  scoredSnapshots: string;
  output: string;
  requireComplete?: boolean;
  allowBundledDevelopmentOutput?: boolean;
}): string[] {
  const bundledSuffix = ["HoursApp", "Resources", "base-office.sqlite"].join(sep);
  if (
    normalize(options.output).endsWith(bundledSuffix)
    && !options.allowBundledDevelopmentOutput
  ) {
    throw new Error(
      "The scored reference corpus includes GPL/reference material; pass "
      + "--allow-reference-bundle only for an explicitly development-only test bundle"
    );
  }
  const corpus = scoredDevelopmentCorpusFromSnapshots(options);
  return compileCorpus(corpus, options.output, true);
}
