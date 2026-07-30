import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { normalize, sep } from "node:path";
import { compileCorpus } from "./compiler.ts";
import {
  officeHours,
  type CorpusInput,
  type LocalDay,
  type OfficeHour,
  type OfficeSection
} from "./types.ts";
import type {
  ReadingToneGenerator,
  ReadingToneName
} from "./chantTools.ts";
import { gabcBody } from "./gabc.ts";

export interface ScoredReference {
  id: string;
  heading: string;
  incipit: string;
  gabc: string;
  mode?: string;
  source: "Gregobase" | "Nocturnale Romanum" | "Chant Tools" | "Unknown";
  sourceURL?: string;
  sourceID?: string;
}

function decodeEntities(value: string): string {
  const named: Record<string, string> = {
    amp: "&",
    apos: "'",
    gt: ">",
    lt: "<",
    nbsp: " ",
    quot: "\""
  };
  return value.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (match, entity: string) => {
    if (entity.startsWith("#x")) return String.fromCodePoint(Number.parseInt(entity.slice(2), 16));
    if (entity.startsWith("#")) return String.fromCodePoint(Number.parseInt(entity.slice(1), 10));
    return named[entity.toLowerCase()] ?? match;
  });
}

function textFromHTML(value: string): string {
  return decodeEntities(value.replace(/<[^>]+>/g, " "))
    .replace(/\s+/g, " ")
    .trim();
}

function decodeJavaScriptString(literal: string): string {
  const quote = literal[0];
  const body = literal.slice(1, -1);
  if (quote === "`" && body.includes("${")) {
    throw new Error("Scored reference contains an interpolated GABC template");
  }
  let result = "";
  for (let index = 0; index < body.length; index += 1) {
    const character = body[index];
    if (character !== "\\") {
      result += character;
      continue;
    }
    const escaped = body[index + 1];
    if (escaped === undefined) {
      result += "\\";
      continue;
    }
    index += 1;
    switch (escaped) {
    case "b": result += "\b"; break;
    case "f": result += "\f"; break;
    case "n": result += "\n"; break;
    case "r": result += "\r"; break;
    case "t": result += "\t"; break;
    case "v": result += "\v"; break;
    case "\n": break;
    case "\r":
      if (body[index + 1] === "\n") index += 1;
      break;
    case "x": {
      const digits = body.slice(index + 1, index + 3);
      if (/^[0-9a-f]{2}$/i.test(digits)) {
        result += String.fromCodePoint(Number.parseInt(digits, 16));
        index += 2;
      } else {
        result += "x";
      }
      break;
    }
    case "u": {
      const braced = body.slice(index + 1).match(/^\{([0-9a-f]+)\}/i);
      if (braced) {
        result += String.fromCodePoint(Number.parseInt(braced[1], 16));
        index += braced[0].length;
        break;
      }
      const digits = body.slice(index + 1, index + 5);
      if (/^[0-9a-f]{4}$/i.test(digits)) {
        result += String.fromCodePoint(Number.parseInt(digits, 16));
        index += 4;
      } else {
        result += "u";
      }
      break;
    }
    default:
      // JavaScript's non-strict string grammar accepts identity escapes such
      // as "\p"; the browser evaluates that sequence as "p".
      result += escaped;
    }
  }
  return result;
}

function lastMatch(pattern: RegExp, value: string): RegExpMatchArray | undefined {
  return [...value.matchAll(pattern)].at(-1);
}

function escapedRegularExpression(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function sourceFromURL(url: string | undefined): Pick<ScoredReference, "source" | "sourceID"> {
  if (!url) return { source: "Chant Tools" };
  const gregobase = url.match(/gregobase\.selapa\.net\/chant\.php\?id=(\d+)/i);
  if (gregobase) return { source: "Gregobase", sourceID: gregobase[1] };
  const nocturnale = url.match(/nocturnale\.marteo\.fr\/chant\/([^/]+)\/?/i);
  if (nocturnale) return { source: "Nocturnale Romanum", sourceID: nocturnale[1] };
  return { source: "Unknown" };
}

interface ReferenceContext {
  heading: string;
  incipit: string;
  mode?: string;
  sourceURL?: string;
  anchorPosition: number;
}

function referenceContext(
  html: string,
  position: number,
  explicitOpeningTag?: { start: number; value: string }
): ReferenceContext {
  const prefix = html.slice(0, position);
  const scriptEnd = html.indexOf("</script>", position);
  const script = scriptEnd >= 0 ? html.slice(position, scriptEnd) : "";
  const containerID = script.match(
    /getElementById\(\s*["']([^"']+)["']\s*\)/
  )?.[1];
  let container = explicitOpeningTag;

  if (!container && containerID) {
    const pattern = new RegExp(
      `<[a-z][\\w:-]*\\b[^>]*\\bid=["']${escapedRegularExpression(containerID)}["'][^>]*>`,
      "gi"
    );
    const match = lastMatch(pattern, prefix);
    if (match?.index !== undefined) {
      container = { start: match.index, value: match[0] };
    }
  }

  if (!container) {
    const attributeStart = Math.max(
      prefix.lastIndexOf("class=\"chant\""),
      prefix.lastIndexOf("class='chant'"),
      prefix.lastIndexOf("data-psalm=")
    );
    const tagStart = prefix.lastIndexOf("<", attributeStart);
    const tagEnd = prefix.indexOf(">", tagStart);
    if (tagStart >= 0 && tagEnd >= tagStart) {
      container = {
        start: tagStart,
        value: prefix.slice(tagStart, tagEnd + 1)
      };
    }
  }

  const containerStart = container?.start ?? position;
  const sectionMatch = lastMatch(
    /<(?:div|section)\b[^>]*class=["'][^"']*\bsection\b[^"']*["'][^>]*>/gi,
    html.slice(0, containerStart)
  );
  const headingPrefix = html.slice(sectionMatch?.index ?? 0, containerStart);
  const headingMatch = lastMatch(
    /<h[2-4][^>]*>([\s\S]*?)<\/h[2-4]>/gi,
    headingPrefix
  );
  const titleMatch = container?.value.match(/\btitle=["']([^"']*)["']/i);
  const modeMatch = container?.value.match(/\bdata-mode=["']([^"']+)["']/i);
  const anchorStart = html.lastIndexOf("<a", containerStart);
  const anchorClose = html.lastIndexOf("</a>", containerStart);
  const anchorTagEnd = anchorStart >= 0 ? html.indexOf(">", anchorStart) : -1;
  const anchorTag = anchorStart > anchorClose && anchorTagEnd >= anchorStart
    ? html.slice(anchorStart, anchorTagEnd + 1)
    : "";
  const linkMatch = anchorTag.match(/\bhref=["']([^"']+)["']/i);

  return {
    heading: headingMatch ? textFromHTML(headingMatch[1]) : "Chant",
    incipit: titleMatch
      ? decodeEntities(titleMatch[1]).replace(/\s+/g, " ").trim()
      : "",
    mode: modeMatch?.[1],
    sourceURL: linkMatch ? decodeEntities(linkMatch[1]) : undefined,
    anchorPosition: containerStart
  };
}

export interface ParseScoredReferenceOptions {
  generateReadingTone?: ReadingToneGenerator;
}

export interface PositionedScoredReference {
  anchorPosition: number;
  sourcePosition: number;
  score: ScoredReference;
}

export function parsePositionedScoredReference(
  html: string,
  options: ParseScoredReferenceOptions = {}
): PositionedScoredReference[] {
  const assignments =
    /var\s+gabc\s*=\s*("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`[\s\S]*?`)\s*;/g;
  const positionedScores: PositionedScoredReference[] = [];

  for (const match of html.matchAll(assignments)) {
    const context = referenceContext(html, match.index);
    const source = sourceFromURL(context.sourceURL);
    const gabc = decodeJavaScriptString(match[1]).trim();
    const key = createHash("sha256").update(gabc).digest("hex");
    // Repeated antiphons are distinct liturgical occurrences even when their
    // GABC is byte-for-byte identical. Keep the source sequence intact; the
    // content store can still deduplicate the shared ChantScore payload by ID.
    if (!gabc) continue;
    positionedScores.push({
      anchorPosition: context.anchorPosition,
      sourcePosition: match.index,
      score: {
        id: `reference-${key.slice(0, 16)}`,
        heading: context.heading,
        incipit: context.incipit,
        gabc,
        mode: context.mode,
        sourceURL: context.sourceURL,
        ...source
      }
    });
  }

  const iframePattern = /<iframe\b[^>]*\bsrc=["']([^"']+)["'][^>]*>/gi;
  for (const match of html.matchAll(iframePattern)) {
    const source = decodeEntities(match[1]);
    let url: URL;
    try {
      url = new URL(source, "https://breviariumgregorianum.com/");
    } catch {
      continue;
    }
    const isOrdinaryLesson = /\/lesson_ordinary_tone\/readings\.html$/i.test(url.pathname);
    const isChapter = /\/tones-api\/readings\/readings\.html$/i.test(url.pathname);
    if (!isOrdinaryLesson && !isChapter) continue;
    if (!options.generateReadingTone) {
      throw new Error(
        "Scored reference contains generated reading tones; "
        + "capture them with the pinned Chant Tools generator"
      );
    }
    const text = url.searchParams.get("text")?.trim();
    if (!text) throw new Error("Generated reading-tone frame is missing its Latin text");
    const tone: ReadingToneName = isOrdinaryLesson
      ? "Lesson Ordinary Tone"
      : "Chapter";
    const gabc = options.generateReadingTone(text, tone).trim();
    if (!gabc) throw new Error(`Chant Tools generated empty GABC for ${tone}`);
    const context = referenceContext(
      html,
      match.index,
      { start: match.index, value: match[0] }
    );
    const key = createHash("sha256").update(gabc).digest("hex");
    positionedScores.push({
      anchorPosition: context.anchorPosition,
      sourcePosition: match.index,
      score: {
        id: `reference-${key.slice(0, 16)}`,
        heading: context.heading,
        incipit: "",
        gabc,
        mode: context.mode,
        source: "Chant Tools"
      }
    });
  }

  return positionedScores
    .sort((left, right) =>
      left.anchorPosition - right.anchorPosition
      || left.sourcePosition - right.sourcePosition
    );
}

export function parseScoredReference(
  html: string,
  options: ParseScoredReferenceOptions = {}
): ScoredReference[] {
  return parsePositionedScoredReference(html, options)
    .map(value => value.score);
}

export function loadScoredReference(path: string): ScoredReference[] {
  return parseScoredReference(readFileSync(path, "utf8"));
}

function localDay(value: string): LocalDay {
  const [year, month, day] = value.split("-").map(Number);
  if (!year || !month || !day) throw new Error(`Invalid reference date ${value}`);
  return { year, month, day };
}

function plainIncipit(score: ScoredReference): string {
  if (score.incipit) return score.incipit.split(/[.:;]/, 1)[0].trim();
  const text = gabcBody(score.gabc)
    .replace(/\([^)]*\)/g, "")
    .replace(/[{}*_]/g, "")
    .replace(/\s+/g, " ")
    .trim();
  return text
    .replace(/^\d+\.\s*/, "")
    .split(/[.:;]/, 1)[0]
    .slice(0, 120);
}

function kindForHeading(heading: string): string {
  const value = heading.toLowerCase();
  if (/psalm/.test(value)) return "psalm";
  if (/hymn/.test(value)) return "hymn";
  if (/cant/.test(value)) return "canticle";
  if (/responsor/.test(value)) return "responsory";
  if (/antiphon|invitator/.test(value)) return "antiphon";
  if (/capit|lectio/.test(value)) return "reading";
  return "opening";
}

function licenseForSource(source: ScoredReference["source"]): string {
  switch (source) {
  case "Gregobase": return "CC0-1.0";
  case "Nocturnale Romanum": return "GPL-3.0-only";
  case "Chant Tools": return "Unlicense";
  case "Unknown": return "reference-only";
  }
}

export function officeSectionsFromScoredReference(
  scores: ScoredReference[],
  idPrefix = "reference"
): OfficeSection[] {
  return scores.map((score, index) => {
    const incipit = plainIncipit(score) || "Chant";
    const gabc = score.gabc.includes("%%")
      ? score.gabc
      : `name: ${score.heading.replace(/[;\r\n]+/g, " ")}; %% ${score.gabc}`;
    return {
      id: `${idPrefix}-${index}`,
      kind: kindForHeading(score.heading),
      title: score.heading,
      latin: incipit,
      english: null,
      rubric: null,
      chant: {
        id: score.id,
        incipit,
        gabc,
        mode: score.mode ?? null,
        reviewStatus: score.source === "Chant Tools"
          ? "generatedFormula"
          : score.source === "Unknown" ? "ambiguous" : "exactMatch",
        provenance: {
          collection: score.source,
          sourceBook: "Breviarium Gregorianum source concordance",
          sourceURL: score.sourceURL ?? null,
          license: licenseForSource(score.source),
          snapshot: createHash("sha256").update(score.gabc).digest("hex")
        },
        timeline: { events: [] }
      }
    };
  });
}

export function compileScoredReference(options: {
  input: string;
  output: string;
  date: string;
  hour: OfficeHour;
}): string[] {
  if (!officeHours.includes(options.hour)) throw new Error(`Invalid office hour ${options.hour}`);
  const bundledSuffix = ["HoursApp", "Resources", "base-office.sqlite"].join(sep);
  if (normalize(options.output).endsWith(bundledSuffix)) {
    throw new Error("A scored reference fixture cannot replace the bundled corpus");
  }
  const date = localDay(options.date);
  const scores = loadScoredReference(options.input);
  const sections = officeSectionsFromScoredReference(scores, "reference-section");
  const input: CorpusInput = {
    manifest: {
      schemaVersion: 1,
      corpusVersion: "scored-reference-fixture",
      minimumAppVersion: "0.1.0",
      createdAt: "2026-07-24T00:00:00Z",
      rubrics: "Rubrics 1960 - 1960",
      sources: [],
      coverage: {
        startDate: date,
        endDate: date,
        expectedOfficeCount: officeHours.length,
        generatedOfficeCount: officeHours.length,
        unresolvedScoreCount: 0,
        ambiguousScoreCount: 0,
        isSample: true
      },
      packSHA256: "",
      signature: ""
    },
    days: [{
      date,
      observanceID: `scored-reference/${options.date}`,
      titleLatin: "Scored reference",
      titleEnglish: null,
      rank: "thirdClass",
      color: "red",
      season: "Development reference",
      eveningContext: "ferialVespers",
      commemorations: [],
      sourceVersion: "Rubrics 1960 - 1960"
    }],
    offices: officeHours.map(hour => ({
      id: `${options.date}-${hour}`,
      date,
      hour,
      titleLatin: "Scored reference",
      titleEnglish: null,
      contextLabel: "Renderer compatibility fixture",
      sourceVersion: "development scored reference",
      sections: hour === options.hour ? sections : [{
        id: `${hour}-reference-placeholder`,
        kind: "opening",
        title: "Reference placeholder",
        latin: "No scored reference loaded for this hour.",
        english: null,
        rubric: null,
        chant: null
      }]
    }))
  };
  return compileCorpus(input, options.output, true);
}
