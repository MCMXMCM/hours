import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { parenthesizeLiturgicalDirections } from "./inlineRubrics.ts";
import type { OfficeHour, OfficeSectionKind } from "./types.ts";

export interface ImportedSectionCandidate {
  upstreamID: string;
  titleLatin: string;
  titleEnglish: string;
  rubricLatin?: string;
  rubricEnglish?: string;
  latin: string;
  english: string;
  kind?: OfficeSectionKind;
}

function normalizedHeading(value: string): string {
  return value.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase();
}

export function classifyImportedSection(
  section: ImportedSectionCandidate
): OfficeSectionKind {
  if (section.kind) return section.kind;
  const value = normalizedHeading(
    `${section.titleLatin} ${section.titleEnglish} ${section.upstreamID} ${section.latin.slice(0, 180)}`
  );
  if (/antiphona finalis/.test(value)) return "marianAntiphon";
  if (/invitator/.test(value)) return "invitatory";
  if (/lectio|reading|lesson|homilia/.test(value)) return "reading";
  if (/absolut/.test(value)) return "absolution";
  if (/benedict|blessing/.test(value)) return "blessing";
  if (/psalm/.test(value)) return "psalm";
  if (/antiphon/.test(value)) return "antiphon";
  if (/capitulum|chapter/.test(value)) return "chapter";
  if (/responsor/.test(value)) return "responsory";
  if (/hymn/.test(value)) return "hymn";
  if (/versus|versicul/.test(value)) return "versicle";
  if (/cantic/.test(value)) return "canticle";
  if (/oratio|collect/.test(value)) return "collect";
  if (/preces/.test(value)) return "preces";
  if (/conclus|benedicamus/.test(value)) return "conclusion";
  return "opening";
}

interface SplitText {
  blessing: string;
  reading: string;
  responsory: string;
  ordinal: string;
}

function splitMatinsText(value: string): SplitText | null {
  const reading = value.match(/(?:^|\n\n)(Lectio|Reading|Lesson)\s+(\d+)\b/i);
  if (!reading || reading.index === undefined) return null;
  const readingStart = reading.index + (reading[0].startsWith("\n\n") ? 2 : 0);
  const thanks = value.slice(readingStart).match(
    /\n\n℟\.\s*(?:Deo\s+gr[aá]tias|Thanks\s+be\s+to\s+God)\.?(?:\n\n|$)/i
  );
  if (!thanks || thanks.index === undefined) return null;
  const readingEnd = readingStart + thanks.index + thanks[0].length;
  const responsory = value.slice(readingEnd).trim();
  if (!/^℟\./.test(responsory)) return null;
  return {
    blessing: value.slice(0, readingStart).trim(),
    reading: value.slice(readingStart, readingEnd).trim(),
    responsory,
    ordinal: reading[2]
  };
}

function normalizedSections(
  section: ImportedSectionCandidate,
  hour: OfficeHour
): ImportedSectionCandidate[] {
  if (hour !== "matins") return [{ ...section, kind: classifyImportedSection(section) }];
  const latin = splitMatinsText(section.latin);
  const english = splitMatinsText(section.english);
  if (!latin || !english || latin.ordinal !== english.ordinal) {
    return [{ ...section, kind: classifyImportedSection(section) }];
  }
  const shared = {
    rubricLatin: section.rubricLatin,
    rubricEnglish: section.rubricEnglish
  };
  return [{
    ...shared,
    upstreamID: `${section.upstreamID}-blessing`,
    titleLatin: "Benedictio",
    titleEnglish: "Blessing",
    latin: latin.blessing,
    english: english.blessing,
    kind: "blessing"
  }, {
    upstreamID: `${section.upstreamID}-reading`,
    titleLatin: `Lectio ${latin.ordinal}`,
    titleEnglish: `Reading ${english.ordinal}`,
    latin: latin.reading,
    english: english.reading,
    kind: "reading"
  }, {
    upstreamID: `${section.upstreamID}-responsory`,
    titleLatin: `Responsorium ${latin.ordinal}`,
    titleEnglish: `Responsory ${english.ordinal}`,
    latin: latin.responsory,
    english: english.responsory,
    kind: "responsory"
  }];
}

export function normalizeImportedOfficeCandidate(
  candidate: ImportedOfficeCandidate
): ImportedOfficeCandidate {
  return {
    ...candidate,
    sections: candidate.sections.flatMap(section => normalizedSections(section, candidate.hour))
  };
}

export interface ImportedOfficeCandidate {
  date: string;
  hour: OfficeHour;
  observanceLatin: string;
  rankLatin: string;
  seasonLatin: string;
  sections: ImportedSectionCandidate[];
  sourceFile: string;
  sourceSHA256: string;
}

export interface DivinumSnapshotRecord {
  date: string;
  hour: OfficeHour;
  file: string;
  sha256: string;
}

interface SnapshotManifest {
  revision: string;
  rubrics: string;
  records: DivinumSnapshotRecord[];
}

const namedEntities: Record<string, string> = {
  amp: "&",
  apos: "'",
  gt: ">",
  lt: "<",
  nbsp: " ",
  ensp: " ",
  quot: "\"",
  darr: "↓",
  uarr: "↑"
};

function decodeEntities(value: string): string {
  return value.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (match, entity: string) => {
    if (entity.startsWith("#x")) return String.fromCodePoint(Number.parseInt(entity.slice(2), 16));
    if (entity.startsWith("#")) return String.fromCodePoint(Number.parseInt(entity.slice(1), 10));
    return namedEntities[entity.toLowerCase()] ?? match;
  });
}

function textFromHTML(value: string): string {
  return parenthesizeLiturgicalDirections(decodeEntities(
    value
      .replace(/<br\s*\/?>/gi, "\n")
      .replace(/<\/p>/gi, "\n")
      .replace(/<[^>]+>/g, "")
  ))
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n[ \t]+/g, "\n")
    .replace(/[ \t]{2,}/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function firstTagText(html: string, tag: "b" | "em"): string {
  const match = html.match(new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`, "i"));
  return match ? textFromHTML(match[1]).replace(/^\{|\}$/g, "") : "";
}

export function parseDivinumOffice(
  html: string,
  source: { date: string; hour: OfficeHour; file: string; sha256: string }
): ImportedOfficeCandidate {
  const observanceLine = html.match(
    /<p class=["']cen["']>\s*<span class=["'][^"']*["']>([\s\S]*?)<br\s*\/?>/i
  );
  if (!observanceLine) throw new Error(`${source.file} is missing the observance header`);
  const observanceAndRank = textFromHTML(observanceLine[1]);
  const rankSeparator = observanceAndRank.lastIndexOf(" ~ ");
  const observanceLatin = rankSeparator >= 0
    ? observanceAndRank.slice(0, rankSeparator).trim()
    : observanceAndRank;
  const rankLatin = rankSeparator >= 0 ? observanceAndRank.slice(rankSeparator + 3).trim() : "";
  const seasonLine = html.match(/<span class="s">([\s\S]*?)<\/span>/i);
  const seasonLatin = seasonLine ? textFromHTML(seasonLine[1]) : "";

  const pairPattern =
    /<TR><TD[^>]*ID=['"]([^'"]+)['"][^>]*><p>([\s\S]*?)<\/p><\/TD>\s*<TD[^>]*><p>([\s\S]*?)<\/p><\/TD>\s*<\/TR>/gi;
  const sections: ImportedSectionCandidate[] = [];
  let match: RegExpExecArray | null;
  while ((match = pairPattern.exec(html)) !== null) {
    const latinHTML = match[2];
    const englishHTML = match[3];
    const titleLatin = firstTagText(latinHTML, "b");
    const titleEnglish = firstTagText(englishHTML, "b");
    sections.push({
      upstreamID: match[1],
      titleLatin: titleLatin || `Section ${sections.length + 1}`,
      titleEnglish: titleEnglish || `Section ${sections.length + 1}`,
      rubricLatin: firstTagText(latinHTML, "em") || undefined,
      rubricEnglish: firstTagText(englishHTML, "em") || undefined,
      latin: textFromHTML(latinHTML),
      english: textFromHTML(englishHTML)
    });
  }
  if (sections.length === 0) throw new Error(`${source.file} contains no bilingual office sections`);
  return normalizeImportedOfficeCandidate({
    date: source.date,
    hour: source.hour,
    observanceLatin,
    rankLatin,
    seasonLatin,
    sections,
    sourceFile: source.file,
    sourceSHA256: source.sha256
  });
}

export function loadSnapshotDirectory(
  inputRoot: string,
  include: (record: DivinumSnapshotRecord) => boolean = () => true
): {
  revision: string;
  offices: ImportedOfficeCandidate[];
} {
  const root = resolve(inputRoot);
  const manifest = JSON.parse(
    readFileSync(join(root, "snapshot-manifest.json"), "utf8")
  ) as SnapshotManifest;
  if (manifest.rubrics !== "Rubrics 1960 - 1960") {
    throw new Error("Snapshot rubrics do not match Rubrics 1960 - 1960");
  }
  const offices = manifest.records.filter(include).map(record => {
    const html = readFileSync(join(root, record.file), "utf8");
    const actualSHA256 = createHash("sha256").update(html).digest("hex");
    if (actualSHA256 !== record.sha256) {
      throw new Error(`${record.file} does not match its snapshot checksum`);
    }
    return parseDivinumOffice(html, record);
  });
  return { revision: manifest.revision, offices };
}

export function importSnapshotDirectory(inputRoot: string, outputPath: string): ImportedOfficeCandidate[] {
  const imported = loadSnapshotDirectory(inputRoot);
  writeFileSync(resolve(outputPath), `${JSON.stringify({
    sourceRevision: imported.revision,
    rubrics: "Rubrics 1960 - 1960",
    reviewStatus: "requires-semantic-normalization-and-human-review",
    offices: imported.offices
  }, null, 2)}\n`);
  return imported.offices;
}
