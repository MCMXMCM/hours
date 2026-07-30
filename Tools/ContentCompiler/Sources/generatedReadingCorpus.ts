import { createHash } from "node:crypto";
import { copyFileSync } from "node:fs";
import { resolve } from "node:path";
import { compileCorpus, validateCorpus } from "./compiler.ts";
import { loadCompiledCorpus } from "./compiledCorpus.ts";
import type { ReadingToneGenerator } from "./chantTools.ts";
import type {
  ChantScore,
  CorpusInput,
  OfficeSection
} from "./types.ts";

const complineBlessing =
  "Noctem quiétam et finem perféctum concédat nobis Dóminus omnípotens.";
const complineBlessingPointed =
  "Noctem quiétam et finem perféctum  + concédat nobis Dóminus omnípotens.";
const complineChapter =
  "Tu autem in nobis es, Dómine, et nomen sanctum tuum invocátum est "
  + "super nos: ne derelínquas nos, Dómine, Deus noster.";
const complineChapterPointed =
  "Tu autem in nobis es, Dómine, † et nomen sanctum tuum invocátum est "
  + "super nos: * ne derelínquas nos, Dómine, Deus noster.";

function normalizedWords(value: string): string[] {
  return value
    .replace(/\([^)]*\)/g, "")
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase()
    .replace(/j/g, "i")
    .replace(/v/g, "u")
    .match(/[\p{Letter}\p{Number}]+/gu)
    ?.filter(word => word.length > 1) ?? [];
}

function longestSharedRun(left: string[], right: string[]): number {
  let longest = 0;
  for (let leftIndex = 0; leftIndex < left.length; leftIndex += 1) {
    for (let rightIndex = 0; rightIndex < right.length; rightIndex += 1) {
      let length = 0;
      while (
        left[leftIndex + length] !== undefined
        && left[leftIndex + length] === right[rightIndex + length]
      ) {
        length += 1;
      }
      longest = Math.max(longest, length);
    }
  }
  return longest;
}

function scoreCovers(score: ChantScore, latin: string): boolean {
  const body = score.gabc.includes("%%")
    ? score.gabc.split("%%").slice(1).join("%%")
    : score.gabc;
  const latinWords = normalizedWords(latin);
  const run = longestSharedRun(normalizedWords(body), latinWords);
  return latinWords.length > 0 && run / latinWords.length >= 0.7;
}

function generatedSection(
  source: OfficeSection,
  latin: string,
  gabc: string,
  suffix: string
): OfficeSection {
  const snapshot = createHash("sha256").update(gabc).digest("hex");
  return {
    id: `${source.id}-generated-${suffix}`,
    kind: source.kind,
    title: source.title,
    latin,
    english: null,
    rubric: null,
    chant: {
      id: `chant-tools-${snapshot.slice(0, 24)}`,
      incipit: latin.split(/[.:;]/, 1)[0],
      gabc,
      mode: null,
      reviewStatus: "generatedFormula",
      provenance: {
        collection: "Chant Tools",
        sourceBook: "Pinned jgabc reading-tone formula",
        sourceURL: "https://github.com/bbloomf/jgabc",
        license: "Unlicense",
        snapshot
      },
      timeline: { events: [] }
    }
  };
}

export function addingKnownGeneratedComplineReadings(
  corpus: CorpusInput,
  generateReadingTone: ReadingToneGenerator,
  revision: string
): {
  corpus: CorpusInput;
  addedSections: number;
  normalizedSections: number;
  metadataNormalized: boolean;
} {
  let addedSections = 0;
  let normalizedSections = 0;
  const offices = corpus.offices.map(office => {
    const normalizedSource = office.sections.map(section => {
      const score = section.chant;
      if (!score) {
        return section;
      }
      const name = section.title.replace(/[;\r\n]+/g, " ");
      const gabc = score.gabc.replace(/^name:[^;]*;/m, `name: ${name};`);
      const isLegacyFormula =
        score.provenance.sourceURL?.includes("chant.php?id=10000000") == true;
      if (!isLegacyFormula && gabc === score.gabc) {
        return section;
      }
      let incipit = score.incipit;
      let latin = section.latin;
      let reviewStatus = score.reviewStatus;
      let provenance = score.provenance;
      if (isLegacyFormula) {
        const body = gabc.includes("%%")
          ? gabc.split("%%").slice(1).join("%%")
          : gabc;
        const plain = body
          .replace(/\([^)]*\)/g, "")
          .replace(/[{}*_]/g, " ")
          .replace(/^[\s\d.]*[VR]\/\.\s*/i, "")
          .replace(/^\s*\d+\.\s*/, "")
          .replace(/\s+/g, " ")
          .trim();
        incipit = plain.split(/[.:;]/, 1)[0].slice(0, 120).trim()
          || score.incipit;
        latin = incipit;
        reviewStatus = "generatedFormula";
        const snapshot = createHash("sha256").update(gabc).digest("hex");
        provenance = {
          collection: "Chant Tools",
          sourceBook: "Pinned jgabc formula",
          sourceURL: "https://github.com/bbloomf/jgabc",
          license: "Unlicense",
          snapshot
        };
      } else if (gabc !== score.gabc) {
        provenance = {
          ...score.provenance,
          snapshot: createHash("sha256").update(gabc).digest("hex")
        };
      }
      normalizedSections += 1;
      return {
        ...section,
        latin,
        chant: {
          ...score,
          incipit,
          gabc,
          reviewStatus,
          provenance
        }
      };
    });
    if (office.hour !== "compline") {
      return { ...office, sections: normalizedSource };
    }
    const existingScores = normalizedSource.flatMap(section =>
      section.chant ? [section.chant] : []
    );
    const sections: OfficeSection[] = [];

    for (const section of normalizedSource) {
      if (
        section.latin.includes(complineBlessing)
        && !existingScores.some(score => scoreCovers(score, complineBlessing))
      ) {
        sections.push(generatedSection(
          section,
          complineBlessing,
          generateReadingTone(
            complineBlessingPointed,
            "Lesson Ordinary Tone"
          ),
          "ordinary-blessing"
        ));
        addedSections += 1;
      }
      if (
        section.latin.includes(complineChapter)
        && !existingScores.some(score => scoreCovers(score, complineChapter))
      ) {
        sections.push(generatedSection(
          section,
          complineChapter,
          generateReadingTone(complineChapterPointed, "Chapter"),
          "chapter"
        ));
        addedSections += 1;
      }
      sections.push(section);
    }
    return { ...office, sections };
  });

  const jgabcSource = {
    name: "jgabc generated reading tones",
    revision,
    license: "Unlicense",
    url: "https://github.com/bbloomf/jgabc",
    checksum: createHash("sha256").update(revision).digest("hex")
  };
  const corpusVersion = `${
    corpus.manifest.corpusVersion.replace(/(?:-generated-readings)+$/, "")
  }-generated-readings`;
  const existingJGABCSource = corpus.manifest.sources.find(source =>
    source.name === jgabcSource.name
  );
  const sourceMetadataNormalized =
    !existingJGABCSource
    || existingJGABCSource.revision !== jgabcSource.revision
    || existingJGABCSource.license !== jgabcSource.license
    || existingJGABCSource.url !== jgabcSource.url
    || existingJGABCSource.checksum !== jgabcSource.checksum;
  return {
    addedSections,
    normalizedSections,
    metadataNormalized:
      corpusVersion !== corpus.manifest.corpusVersion
      || sourceMetadataNormalized,
    corpus: {
      ...corpus,
      manifest: {
        ...corpus.manifest,
        corpusVersion,
        sources: [
          ...corpus.manifest.sources.filter(source =>
            source.name !== jgabcSource.name
          ),
          jgabcSource
        ]
      },
      offices
    }
  };
}

export function compileKnownGeneratedComplineReadings(options: {
  input: string;
  output: string;
  generateReadingTone: ReadingToneGenerator;
  revision: string;
}): { warnings: string[]; addedSections: number; normalizedSections: number } {
  const result = addingKnownGeneratedComplineReadings(
    loadCompiledCorpus(options.input),
    options.generateReadingTone,
    options.revision
  );
  if (
    result.addedSections === 0
    && result.normalizedSections === 0
    && !result.metadataNormalized
  ) {
    if (resolve(options.input) !== resolve(options.output)) {
      copyFileSync(options.input, options.output);
    }
    return {
      warnings: [
        ...validateCorpus(result.corpus, true),
        "No known Compline reading tones were missing"
      ],
      addedSections: 0,
      normalizedSections: 0
    };
  }
  const warnings = compileCorpus(result.corpus, options.output, true);
  return {
    warnings,
    addedSections: result.addedSections,
    normalizedSections: result.normalizedSections
  };
}
