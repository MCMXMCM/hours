import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { DatabaseSync } from "node:sqlite";
import {
  canonicalVisibleContentDigest,
  compileCorpus,
  compileScheduledCorpus,
  loadCorpus,
  validateCorpus
} from "../Sources/compiler.ts";
import { parseGABC } from "../Sources/gabc.ts";
import { parenthesizeLiturgicalDirections } from "../Sources/inlineRubrics.ts";
import { normalizeLatin, resolveChant } from "../Sources/chantResolver.ts";
import { loadSnapshotDirectory, parseDivinumOffice } from "../Sources/divinumImporter.ts";
import {
  scoredOfficeURL,
  type LoadedScoredOffice
} from "../Sources/breviariumGregorianum.ts";
import {
  officeSectionsFromScoredReference,
  parseScoredReference
} from "../Sources/scoredReference.ts";
import {
  parseOrderedReferenceOffice,
  parseReferenceObservance
} from "../Sources/orderedReference.ts";
import {
  authoritativeOfficesOnly,
  officesWithUnavailablePlaceholders,
  officeWithScoredReference
} from "../Sources/scoredDevelopmentCorpus.ts";
import {
  canonicalLiturgicalIdentity,
  requireSameLiturgicalIdentity
} from "../Sources/liturgicalIdentity.ts";
import {
  auditExpectedObservances,
  canonicalImportedOfficeDigest
} from "../Sources/observanceAudit.ts";
import { loadCompiledCorpus } from "../Sources/compiledCorpus.ts";
import { decodeContentPayload } from "../Sources/contentPayload.ts";
import {
  addingKnownGeneratedComplineReadings
} from "../Sources/generatedReadingCorpus.ts";
import {
  curatedOfficePromotions,
  curatedPromotionChecksum
} from "../Sources/curatedOfficePromotions.ts";
import { withResolvedEveningContexts } from "../Sources/eveningContext.ts";
import {
  exceptionalMartyrologyEnglish,
  exceptionalMartyrologyReview,
  requireApprovedExceptionalMartyrology
} from "../Sources/exceptionalMartyrology.ts";
import {
  officeConfigurationKey,
  perennialOrdoRange,
  uniqueOfficeConfigurations,
  type PerennialOrdoSchedule
} from "../Sources/perennialOrdo.ts";
import {
  englishPrimeMartyrologyProclamationToken,
  latinPrimeMartyrologyProclamationToken,
  normalizeDynamicOfficeText
} from "../Sources/dynamicOfficeText.ts";
import type {
  CorpusInput,
  OfficeDocument,
  OfficeHour,
  OfficeSection
} from "../Sources/types.ts";

const fixture = new URL("../Fixtures/evening-pilot.json", import.meta.url).pathname;
const bundledDatabase = new URL(
  "../../../HoursApp/Resources/base-office.sqlite",
  import.meta.url
).pathname;
const bundled2026Range = { from: "2026-01-01", to: "2026-12-31" };

test("rolling perennial window retains following-day concurrence context", () => {
  const schedule: PerennialOrdoSchedule = {
    sourceRevision: "fixture",
    rubrics: "Rubrics 1960 - 1960",
    from: "2025-12-31",
    to: "2026-01-02",
    days: [
      {
        date: "2025-12-31",
        titleLatin: "Die VII infra Octavam Nativitatis",
        rankLatin: "II. classis",
        occurrenceDetailLatin: "",
        concurrenceDetailLatin: "Vespera de sequenti",
        weekdayLatin: "Feria IV"
      },
      {
        date: "2026-01-01",
        titleLatin: "In Circumcisione Domini",
        rankLatin: "I. classis",
        occurrenceDetailLatin: "",
        concurrenceDetailLatin: "Vespera de sequenti",
        weekdayLatin: "Feria V"
      },
      {
        date: "2026-01-02",
        titleLatin: "Sanctissimi Nominis Jesu",
        rankLatin: "II. classis",
        occurrenceDetailLatin: "",
        concurrenceDetailLatin: "",
        weekdayLatin: "Feria VI"
      }
    ]
  };
  const range = perennialOrdoRange(schedule, {
    from: "2026-01-01",
    to: "2026-01-01"
  });
  const configurations = uniqueOfficeConfigurations(schedule, range);

  assert.equal(configurations.size, 8);
  assert.ok(configurations.has(
    officeConfigurationKey(schedule.days[1], "vespers", schedule.days[2])
  ));
  assert.throws(
    () => perennialOrdoRange(schedule, {
      from: "2024-01-01",
      to: "2026-01-01"
    }),
    /outside/
  );
});

test("Prime recipes store date-dependent lunar proclamations as tokens", () => {
  const office: OfficeDocument = {
    id: "2026-02-22-prime",
    date: { year: 2026, month: 2, day: 22 },
    hour: "prime",
    titleLatin: "Ad Primam",
    contextLabel: "Dominica",
    sourceVersion: "fixture",
    sections: [{
      id: "martyrology",
      kind: "reading",
      title: "Martyrologium",
      titleEnglish: "Martyrology",
      rubric: "anticipatur",
      rubricEnglish: "anticipated",
      latin: "Martyrologium {anticipatur}\n\nSéptimo Kaléndas Mártii Luna sexta Anno Dómini 2026\nSancti Petri\npercutit sibi pectus mea culpa",
      english: "Martyrology {anticipated}\n\nFebruary 23rd 2026, the 6th day of the Moon, were born into the better life"
    }]
  };

  const normalized = normalizeDynamicOfficeText(office);
  assert.match(normalized.sections[0].latin, new RegExp(latinPrimeMartyrologyProclamationToken));
  assert.match(normalized.sections[0].english ?? "", new RegExp(englishPrimeMartyrologyProclamationToken));
  assert.doesNotMatch(normalized.sections[0].latin, /2026/);
  assert.doesNotMatch(normalized.sections[0].latin, /^Martyrologium/);
  assert.doesNotMatch(normalized.sections[0].english ?? "", /^Martyrology/);
  assert.equal(normalized.sections[0].title, "Martyrologium");
  assert.equal(normalized.sections[0].rubric, "anticipatur");
  assert.match(normalized.sections[0].latin, /\(percutit sibi pectus\) mea culpa/);
});

function loadBundled2026Corpus(): CorpusInput {
  return loadCompiledCorpus(bundledDatabase, bundled2026Range);
}

const engravingFixtures = JSON.parse(
  readFileSync(
    new URL("../../../HoursTests/Fixtures/gabc-engraving-fixtures.json", import.meta.url),
    "utf8"
  )
) as Array<{ name: string; scoreID: string; gabc: string; eventCount: number }>;

function englishWordCount(value: string): number {
  return value.split(/\s+/).filter(Boolean).length;
}

test("fixture validates only through the explicit development gate", () => {
  const corpus = loadCorpus(fixture);
  assert.throws(() => validateCorpus(corpus), /Release corpus gate failed/);
  const warnings = validateCorpus(corpus, true);
  assert.match(warnings.join(" "), /Development sample/);
});

test("release gate requires a declared rolling reviewed window", () => {
  const corpus = structuredClone(loadCorpus(fixture));
  corpus.manifest.coverage.isSample = false;
  assert.throws(
    () => validateCorpus(corpus),
    /must record its reviewedCenterYear/
  );
  corpus.manifest.coverage.reviewedCenterYear = 2026;
  assert.throws(
    () => validateCorpus(corpus),
    /centered on 2026 must cover 2025-01-01 through 2036-12-31/
  );
});

test("compiler preserves prose that shares a heading with a chant", () => {
  const corpus = structuredClone(loadCorpus(fixture));
  const office = corpus.offices.find(candidate =>
    candidate.sections.some(section => section.chant)
  );
  assert.ok(office);
  const chant = office.sections.find(section => section.chant);
  assert.ok(chant);
  office.sections.push({
    id: "duplicate-plain-prayer",
    kind: chant.kind,
    title: chant.title.toLocaleUpperCase(),
    latin: chant.latin,
    chant: null
  });

  assert.doesNotThrow(() => validateCorpus(corpus, true));
});

test("GABC parsing produces stable phrase, syllable, and note IDs", () => {
  const first = parseGABC("name: test; %% Do(h.)-mi(ij)nus(k::)", "score");
  const second = parseGABC("name: test; %% Do(h.)-mi(ij)nus(k::)", "score");
  assert.deepEqual(first, second);
  assert.equal(first.events[0].id, "score-note-0");
  assert.ok(first.events[0].modifiers.includes("mora"));
  assert.ok(new Set(first.events.map(event => event.phraseID)).size >= 1);
});

test("GABC parsing counts uppercase inclinatum notes as native notation notes", () => {
  const timeline = parseGABC("name: test; %% Lau(hED)da(gGF)te(f::)", "score");
  assert.equal(timeline.events.length, 7);
  assert.deepEqual(
    timeline.events.map(event => event.syllableID),
    [
      "score-syllable-0",
      "score-syllable-0",
      "score-syllable-0",
      "score-syllable-1",
      "score-syllable-1",
      "score-syllable-1",
      "score-syllable-2"
    ]
  );
});

test("GABC parsing excludes bracket annotations from the musical timeline", () => {
  const timeline = parseGABC(
    "name: test; %% Mun(i_[uh:l]j)dum(i.) (::)",
    "score"
  );
  assert.equal(timeline.events.length, 3);
  assert.deepEqual(
    timeline.events.map(event => event.relativePitch),
    [1, 2, 1]
  );
});

test("GABC accidental declarations do not consume notes and govern matching pitches", () => {
  const timeline = parseGABC(
    "name: accidentals; %% (c4) Red(h)e(h)mí(ixhi)sti(i) (,) De(ixhi)us(i) (::)",
    "accidentals"
  );
  assert.deepEqual(
    timeline.events.map(event => [event.syllable, event.relativePitch]),
    [
      ["Red", 0], ["e", 0], ["mí", 0], ["mí", 1], ["sti", 1],
      ["De", 0], ["De", 1], ["us", 1]
    ]
  );
  assert.deepEqual(
    timeline.events.map(event => event.modifiers.includes("flat")),
    [false, false, false, true, true, false, true, true]
  );
});

test("GABC parsing removes psalm-tone pointing delimiters from lyrics", () => {
  const timeline = parseGABC(
    "name: Psalmus 86; %% ta(j)ber(j)ná(j)_cu_(h)_la_(j) *Ja*(k)cob.(j.) *(h) (::)",
    "score"
  );
  assert.deepEqual(
    timeline.events.map(event => event.syllable),
    ["ta", "ber", "ná", "cu", "la", "Ja", "cob.", "*"]
  );
});

test("GABC parsing ignores line comments instead of leaking percent signs into lyrics", () => {
  const timeline = parseGABC(
    "name: Invitatorium; %% (c3)\r\n%\r\nHó(h)% source note\r\ndie(i) (::)",
    "invitatory"
  );
  assert.deepEqual(
    timeline.events.map(event => event.syllable),
    ["Hó", "die"]
  );
});

test("GABC timeline records the active clef on every note, including mid-score changes", () => {
  const timeline = parseGABC(
    "name: Dec. 8 Matins; %% (c3) Ma(h)rí(i)a(j) (c2) grá(h)ti(i)a.(j::)",
    "december-8-clef-change"
  );
  assert.deepEqual(
    timeline.events.map(event => `${event.clef?.kind}${event.clef?.line}`),
    ["c3", "c3", "c3", "c2", "c2", "c2"]
  );
});

test("curated Easter promotion payloads are pinned and notation-valid", () => {
  assert.equal(curatedOfficePromotions([], []).size, 0);
  const sourceIDs = [
    "11971", "12689", "12153", "11828", "12261",
    "2314", "2148", "2023", "2150", "2917", "2230"
  ];
  for (const sourceID of sourceIDs) {
    const gabc = readFileSync(
      new URL(`../Fixtures/easter-octave-gabc/${sourceID}.gabc`, import.meta.url),
      "utf8"
    );
    assert.match(gabc, /Liber (?:antiphonarius|Usualis)/);
    assert.ok(parseGABC(gabc, `curated-${sourceID}`).events.length > 0);
  }
  assert.equal(
    curatedPromotionChecksum(),
    "1e61be4857d4fc90a74080b45e5a3efa6aeae88ecdbf777b385a62d72c8edc9a"
  );
});

test("compiler rejects unknown section and calendar enum values", () => {
  const corpus = structuredClone(loadCorpus(fixture));
  corpus.offices[0].sections[0].kind = "guessed-role" as never;
  assert.throws(() => validateCorpus(corpus, true), /unknown value/);

  const other = structuredClone(loadCorpus(fixture));
  other.days[0].color = "blue" as never;
  assert.throws(() => validateCorpus(other, true), /unknown value/);
});

test("compiler timeline parsing satisfies the native engraving fixture contract", () => {
  for (const fixture of engravingFixtures) {
    const timeline = parseGABC(fixture.gabc, fixture.scoreID);
    assert.equal(timeline.events.length, fixture.eventCount, fixture.name);
    assert.deepEqual(
      timeline.events.map(event => event.id),
      Array.from({ length: fixture.eventCount }, (_, index) => `${fixture.scoreID}-note-${index}`),
      fixture.name
    );
  }
});

test("compiler emits a queryable, indexed SQLite corpus", () => {
  const directory = mkdtempSync(join(tmpdir(), "hours-compiler-"));
  const output = join(directory, "base.sqlite");
  const corpus = loadCorpus(fixture);
  compileCorpus(corpus, output, true);

  const db = new DatabaseSync(output, { readOnly: true });
  const officeCount = db.prepare("SELECT COUNT(*) AS count FROM office_schedule").get() as { count: number };
  const dayCount = db.prepare("SELECT COUNT(*) AS count FROM days").get() as { count: number };
  const scoreCount = db.prepare("SELECT COUNT(*) AS count FROM scores").get() as { count: number };
  const textCount = db.prepare("SELECT COUNT(*) AS count FROM text_resources").get() as { count: number };
  const recipeCount = db.prepare("SELECT COUNT(*) AS count FROM recipes").get() as { count: number };
  const payload = db.prepare(`
    SELECT recipes.payload
    FROM office_schedule
    JOIN recipes ON recipes.id = office_schedule.recipe_id
    WHERE office_schedule.hour = 'vespers'
    LIMIT 1
  `).get() as { payload: Uint8Array };
  const searchCount = db.prepare(`
    SELECT COUNT(*) AS count
    FROM text_fts
    JOIN text_resources ON text_resources.rowid = text_fts.rowid
    WHERE text_fts MATCH '{title_latin latin} : "domine"'
  `).get() as { count: number };
  const manifest = JSON.parse(
    (db.prepare("SELECT value FROM meta WHERE key = 'manifest'").get() as { value: string }).value
  );
  const relations = db.prepare(`
    SELECT
      (SELECT COUNT(*) FROM text_scores) AS textScores,
      (SELECT COUNT(*) FROM text_recipes) AS textRecipes
  `).get() as { textScores: number; textRecipes: number };
  db.close();
  assert.equal(officeCount.count, 8);
  assert.equal(dayCount.count, 1);
  assert.equal(scoreCount.count, 8);
  assert.ok(textCount.count > 0);
  assert.ok(recipeCount.count > 0);
  assert.ok(searchCount.count > 0);
  assert.equal(manifest.schemaVersion, 3);
  assert.ok(relations.textScores > 0);
  assert.ok(relations.textRecipes > 0);
  assert.ok(typeof manifest.compilerRevision === "string" && manifest.compilerRevision.length > 0);
  assert.equal(manifest.normalizedCounts.scheduledOffices, 8);
  assert.deepEqual(manifest.notices, []);
  assert.doesNotMatch(new TextDecoder().decode(payload.payload), /timeline/);
});

test("scheduled compiler stores one recipe for many civil-date references", () => {
  const directory = mkdtempSync(join(tmpdir(), "hours-scheduled-"));
  const output = join(directory, "scheduled.sqlite");
  const corpus = loadCorpus(fixture);
  const sourceOffice = corpus.offices[0];
  const secondDate = { year: 2026, month: 1, day: 2 };
  const secondDay = {
    ...corpus.days[0],
    date: secondDate,
    observanceID: "test/second-day"
  };

  compileScheduledCorpus({
    manifest: {
      ...corpus.manifest,
      coverage: {
        ...corpus.manifest.coverage,
        endDate: secondDate,
        expectedOfficeCount: 2,
        generatedOfficeCount: 2,
        authoritativeOfficeCount:
          sourceOffice.format === "authoritativeOrdered" ? 2 : 0
      }
    },
    days: [corpus.days[0], secondDay],
    recipes: [{ key: "shared-office", office: sourceOffice }],
    schedule: [
      { date: sourceOffice.date, hour: sourceOffice.hour, recipeKey: "shared-office" },
      { date: secondDate, hour: sourceOffice.hour, recipeKey: "shared-office" }
    ]
  }, output, true);

  const db = new DatabaseSync(output, { readOnly: true });
  const recipeCount = db.prepare(
    "SELECT COUNT(*) AS count FROM recipes"
  ).get() as { count: number };
  const scheduleCount = db.prepare(
    "SELECT COUNT(*) AS count FROM office_schedule"
  ).get() as { count: number };
  db.close();
  assert.equal(recipeCount.count, 1);
  assert.equal(scheduleCount.count, 2);
});

test("compiler rejects GABC and stored-timeline syllable drift", () => {
  const corpus = structuredClone(loadCorpus(fixture));
  const section = corpus.offices[0].sections[0];
  section.chant = {
    id: "alignment-negative",
    incipit: "Dominus",
    gabc: "name: alignment; %% Do(h)-mi(i)nus(j::)",
    mode: "VIII",
    reviewStatus: "humanReviewed",
    provenance: {
      collection: "Test",
      sourceBook: "Test fixture",
      license: "CC0-1.0",
      snapshot: "fixture"
    },
    timeline: parseGABC(
      "name: alignment; %% Do(h)-mi(i)nus(j::)",
      "alignment-negative"
    )
  };
  section.chant.gabc = "name: alignment; %% Do(h)mi(i)nus(j::)";
  assert.throws(
    () => validateCorpus(corpus, true),
    /GABC\/timeline syllable or neume drift/
  );
});

test("compiled corpus can be losslessly rehydrated for deterministic enrichment", () => {
  const directory = mkdtempSync(join(tmpdir(), "hours-rehydrate-"));
  const output = join(directory, "base.sqlite");
  const input = loadCorpus(fixture);
  compileCorpus(input, output, true);

  const rehydrated = loadCompiledCorpus(output);
  assert.equal(rehydrated.days.length, input.days.length);
  assert.equal(rehydrated.offices.length, input.offices.length);
  assert.equal(
    rehydrated.offices.flatMap(office =>
      office.sections.filter(section => section.chant)
    ).length,
    input.offices.flatMap(office =>
      office.sections.filter(section => section.chant)
    ).length
  );
});

test("compiler omits undefined optional fields instead of emitting invalid JSON", () => {
  const corpus = structuredClone(loadCorpus(fixture));
  corpus.days[0].eveningContext = undefined;
  const directory = mkdtempSync(join(tmpdir(), "hours-undefined-json-"));
  const output = join(directory, "corpus.sqlite");

  compileCorpus(corpus, output, true);
  const rehydrated = loadCompiledCorpus(output);

  assert.equal(rehydrated.days[0].eveningContext, undefined);
});

test("known Compline frame tones are added once from the pinned formula output", () => {
  const input = structuredClone(loadCorpus(fixture));
  const office = input.offices[0];
  office.hour = "compline";
  office.sections = [{
    id: "compline-text",
    kind: "reading",
    title: "Lectio brevis",
    latin: `
      Benedictio. Noctem quiétam et finem perféctum concédat nobis Dóminus omnípotens.

      Tu autem in nobis es, Dómine, et nomen sanctum tuum invocátum est super nos: ne derelínquas nos, Dómine, Deus noster.
    `,
    chant: null
  }];
  const generatedInputs: string[] = [];
  const result = addingKnownGeneratedComplineReadings(
    input,
    (text, tone) => {
      generatedInputs.push(`${tone}:${text}`);
      return `name: ${tone}; %% ${text.replace(/\s+/g, " ")}(h.) (::)`;
    },
    "dff87490026adf21a97cac019a83b8611f0c2e71"
  );

  assert.equal(result.addedSections, 2);
  assert.equal(result.metadataNormalized, true);
  assert.match(result.corpus.manifest.corpusVersion, /-generated-readings$/);
  assert.doesNotMatch(
    result.corpus.manifest.corpusVersion,
    /-generated-readings-generated-readings/
  );
  assert.equal(result.corpus.offices[0].sections.filter(section => section.chant).length, 2);
  assert.match(generatedInputs[0], /Lesson Ordinary Tone:.* \+ /);
  assert.match(generatedInputs[1], /Chapter:.*†.*\*/);
  const repeated = addingKnownGeneratedComplineReadings(
      result.corpus,
      () => { throw new Error("must not regenerate covered tones"); },
      "dff87490026adf21a97cac019a83b8611f0c2e71"
  );
  assert.equal(repeated.addedSections, 0);
  assert.equal(repeated.metadataNormalized, false);
});

test("bundled 2026 corpus includes generated Compline tones and penitential prose", () => {
  const corpus = loadBundled2026Corpus();
  const compline = corpus.offices.find(office =>
    office.hour === "compline"
    && office.date.year === 2026
    && office.date.month === 7
    && office.date.day === 24
  );
  assert.ok(compline);
  const latin = compline.sections.map(section => section.latin).join("\n");
  assert.match(latin, /Pater noster/);
  assert.match(latin, /Confíteor/);
  assert.ok(compline.sections.some(section =>
    section.chant?.provenance.collection === "Chant Tools"
    && /Noctem quiétam/.test(section.latin)
  ));
  assert.ok(compline.sections.some(section =>
    section.chant?.provenance.collection === "Chant Tools"
    && /Tu autem in nobis es/.test(section.latin)
  ));
});

test("bundled August 25 Prime ends with the scored conclusion", () => {
  const corpus = loadBundled2026Corpus();
  const prime = corpus.offices.find(office => office.id === "2026-08-25-prime");
  assert.ok(prime);

  const conclusion = prime.sections.filter(section => section.title === "Conclusio");
  assert.equal(conclusion.length, 2);
  assert.ok(conclusion.every(section => section.chant));
  assert.doesNotMatch(
    conclusion.map(section => section.latin).join("\n"),
    /Adiutórium nostrum|Benedícite/
  );

  const database = new DatabaseSync(bundledDatabase, { readOnly: true });
  try {
    const scheduledPrimeTexts = database.prepare(`
      SELECT DISTINCT text_resources.payload
      FROM office_schedule
      JOIN recipe_sections
        ON recipe_sections.recipe_id = office_schedule.recipe_id
      JOIN text_resources
        ON text_resources.id = recipe_sections.text_id
      WHERE office_schedule.hour = 'prime'
    `).all() as Array<{ payload: Uint8Array }>;
    const legacyConclusions = scheduledPrimeTexts.flatMap(row => {
      const section = JSON.parse(
        decodeContentPayload(row.payload)
      ) as OfficeSection;
      return /Adiutórium nostrum/.test(section.latin)
          && /Benedícite/.test(section.latin)
          && /Dóminus nos benedícat/.test(section.latin)
        ? [section.latin]
        : [];
    });
    assert.deepEqual(legacyConclusions, []);
  } finally {
    database.close();
  }
});

test("bundled 2026 corpus distinguishes inline directions from spoken text", () => {
  const corpus = loadBundled2026Corpus();
  const compline = corpus.offices.find(office => office.id === "2026-08-19-compline");
  const confiteor = compline?.sections.find(section => /Confíteor Deo/.test(section.latin));

  assert.ok(confiteor);
  assert.match(confiteor.latin, /\(percutit sibi pectus\) mea culpa/);
  assert.match(confiteor.english ?? "", /\(strikes his breast\) through my fault/);

  for (const section of corpus.offices.flatMap(office => office.sections)) {
    assert.equal(section.latin, parenthesizeLiturgicalDirections(section.latin));
    if (section.english) {
      assert.equal(section.english, parenthesizeLiturgicalDirections(section.english));
    }
  }
});

test("bundled source-gap offices retain English and gate exceptional Martyrology wording", () => {
  const corpus = loadBundled2026Corpus();

  assert.ok(corpus.offices.every(office => office.titleEnglish?.trim()));
  assert.ok(corpus.offices.every(office => office.observance?.titleEnglish?.trim()));

  const exceptionalDates = ["2026-02-22", "2026-12-24"];
  for (const date of exceptionalDates) {
    const prime = corpus.offices.find(office => office.id === `${date}-prime`);
    assert.ok(prime);
    const martyrology = prime.sections.find(section => section.title === "Martyrologium");
    assert.ok(martyrology?.english?.trim());
    assert.ok(martyrology.english?.includes("And elsewhere many other holy martyrs"));
    assert.doesNotMatch(martyrology.english ?? "", /^\s*Martyrology\s*\{\s*anticipated\s*\}/i);
  }
  assert.equal(corpus.manifest.coverage.isSample, false);
  assert.equal(exceptionalMartyrologyReview().matrix.approval.status, "approved");

  for (const day of ["06", "07", "08", "09", "10"]) {
    for (const hour of ["lauds", "vespers"] as const) {
      const office = corpus.offices.find(candidate =>
        candidate.id === `2026-04-${day}-${hour}`
      );
      assert.ok(office);
      assert.ok(office.sections.some(section =>
        section.latin === "Orémus."
        && section.english === "Let us pray."
      ));
      const substantiveMissing = office.sections.filter(section =>
        !section.english?.trim()
        && section.latin.replace(/[^A-Za-zÀ-ž]/g, "").length >= 8
      );
      assert.deepEqual(substantiveMissing, []);
    }
  }

  const missingOutsideMartyrology = corpus.offices.flatMap(office =>
    office.sections.filter(section =>
      section.title !== "Martyrologium"
      && !section.english?.trim()
      && section.latin.replace(/[^A-Za-zÀ-ž]/g, "").length >= 8
    ).map(section => `${office.id}:${section.id}`)
  );
  assert.deepEqual(missingOutsideMartyrology, []);
});

test("exceptional Martyrology matrix pins public-domain sources and records release approval", () => {
  const review = exceptionalMartyrologyReview();
  assert.equal(
    review.matrix.englishBase.pdfSHA256,
    "688cfa7b85d8a686a4fde9877cfa133550fef8fce8cf46c6c433abf88983042d"
  );
  assert.equal(review.matrix.approval.status, "approved");
  assert.equal(review.matrix.approval.reviewedBy, "Matthew McCarty");
  assert.equal(review.matrix.approval.reviewedAt, "2026-08-20");
  assert.doesNotThrow(() => requireApprovedExceptionalMartyrology());
  assert.doesNotMatch(exceptionalMartyrologyEnglish["2026-02-22"], /Vigil of.*Matthias/i);
  assert.match(exceptionalMartyrologyEnglish["2026-12-24"], /fifth Kalends of February/);
  assert.ok(
    exceptionalMartyrologyEnglish["2026-12-24"].indexOf("Peter Nolasco")
      < exceptionalMartyrologyEnglish["2026-12-24"].indexOf("Saint Eugenia")
  );
});

test("bundled August 19 Sext carries complete English through every reported gap", () => {
  const corpus = loadBundled2026Corpus();
  const office = corpus.offices.find(candidate =>
    candidate.id === "2026-08-19-sext"
  );
  assert.ok(office);

  const incipit = office.sections.find(section => section.title === "Incipit");
  assert.match(incipit?.english ?? "", /O God,[\s\S]*come to my assistance/i);
  assert.match(incipit?.english ?? "", /world without end/i);
  assert.match(incipit?.english ?? "", /Alleluia/i);

  for (const psalm of ["Psalmus 55", "Psalmus 56", "Psalmus 57"]) {
    const section = office.sections.find(candidate =>
      candidate.title === psalm
      && englishWordCount(candidate.english ?? "") > 80
    );
    assert.ok(section, `${psalm} is absent`);
    assert.ok(
      englishWordCount(section.english ?? "") > 80,
      `${psalm} still has only a fragment of its English translation`
    );
  }
  const psalm57 = office.sections.find(section =>
    section.title === "Psalmus 57"
    && section.english?.includes("57:10")
  );
  assert.ok(psalm57);
  assert.ok(
    psalm57.english!.indexOf("57:9") < psalm57.english!.indexOf("57:10"),
    "Psalm 57 English verses are out of order"
  );

  const chapterEnglish = office.sections
    .filter(section => section.title === "Capitulum Responsorium Versus")
    .map(section => section.english ?? "")
    .join("\n");
  assert.match(chapterEnglish, /mouth of the righteous/i);
  assert.match(chapterEnglish, /law of his God is in his heart/i);
  assert.match(chapterEnglish, /None of his steps shall slide/i);

  const prayerEnglish = office.sections
    .filter(section => section.title === "Oratio")
    .map(section => section.english ?? "")
    .join("\n");
  assert.match(prayerEnglish, /O Lord, hear my prayer/i);
  assert.match(prayerEnglish, /wondrously inspire blessed John/i);
});

test("bundled August 19 None keeps nested chapter translations separate", () => {
  const corpus = loadBundled2026Corpus();
  const office = corpus.offices.find(candidate =>
    candidate.id === "2026-08-19-none"
  );
  assert.ok(office);

  const sections = office.sections.filter(section =>
    section.title === "Capitulum Responsorium Versus"
  );
  const chapter = sections.find(section =>
    section.chant?.gabc.includes("Ius(h)tum(h) de(h)dú(h)xit")
    && section.chant.gabc.includes("ho(h)nes(h)tá(h)vit")
  );
  const versicle = sections.find(section =>
    section.chant?.gabc.includes("Ju(h)stu(h)m de(h)dú(h)xi(h)t")
  );
  const response = sections.find(section =>
    section.chant?.gabc.includes("E(h)t o(h)sté(h)ndi(h)t")
  );

  assert.equal(
    chapter?.english,
    "She conducted the just, when he fled from his brother's wrath, through "
      + "the right ways, and showed him the kingdom of God, and gave him the "
      + "knowledge of the holy things, made him honourable in his labours, "
      + "and accomplished his labours."
  );
  assert.equal(
    versicle?.english,
    "℣. The Lord guided the just in right paths."
  );
  assert.equal(
    response?.english,
    "℟. And showed him the kingdom of God."
  );
});

test("bundled long scored psalms never collapse to one English verse", () => {
  const corpus = loadBundled2026Corpus();
  const longScoredPsalms = corpus.offices.flatMap(office =>
    office.sections.filter(section =>
      section.kind === "psalm"
      && /^Psalmus \d+/.test(section.title)
      && (section.chant?.gabc.length ?? 0) > 1_200
    )
  );

  assert.ok(longScoredPsalms.length > 100);
  for (const section of longScoredPsalms) {
    assert.ok(
      englishWordCount(section.english ?? "") > 30,
      `${section.id} (${section.title}) has truncated or missing English`
    );
  }
});

test("bundled chant text and timelines contain no leaked GABC percent comments", () => {
  const corpus = loadBundled2026Corpus();
  const chantSections = corpus.offices.flatMap(office =>
    office.sections.filter(section => section.chant)
  );

  assert.ok(chantSections.length > 0);
  for (const section of chantSections) {
    assert.ok(
      section.english?.trim(),
      `${section.id} (${section.title}) lacks its available English translation`
    );
    assert.doesNotMatch(section.latin, /^\s*%/);
    assert.doesNotMatch(section.latin, /Solesmes\s+1961,\s*100%/i);
    assert.doesNotMatch(section.chant!.incipit, /^\s*%/);
    const timeline = parseGABC(section.chant!.gabc, section.chant!.id);
    for (const event of timeline.events) {
      assert.doesNotMatch(event.syllable, /%/);
    }
  }
});

test("chant resolver normalizes Latin but refuses equally preferred ambiguity", () => {
  assert.equal(normalizeLatin("Dómine, cæli!"), "domine caeli");
  const query = {
    sectionID: "antiphon",
    latin: "Salva nos, Domine",
    incipit: "Salva nos",
    officePart: "antiphon",
    mode: "VIII",
    preferredSources: ["Liber 1961"]
  };
  const candidate = {
    id: "a",
    latin: "Salva nos Domine",
    incipit: "Salva nos",
    officePart: "antiphon",
    mode: "VIII",
    source: "Liber 1961"
  };
  assert.equal(resolveChant(query, [candidate], {}).status, "exact");
  assert.equal(resolveChant(query, [candidate, { ...candidate, id: "b" }], {}).status, "ambiguous");
  assert.equal(resolveChant(query, [candidate], { antiphon: "a" }).status, "override");
});

test("Divinum Officium XHTML importer preserves bilingual sections and upstream IDs", () => {
  const html = readFileSync(
    new URL("../Fixtures/divinum-office-fragment.html", import.meta.url),
    "utf8"
  );
  const office = parseDivinumOffice(html, {
    date: "2026-07-23",
    hour: "vespers",
    file: "fixture.html",
    sha256: "fixture"
  });
  assert.equal(office.observanceLatin, "S. Apollinaris Episcopi et Martyris");
  assert.equal(office.rankLatin, "III. classis");
  assert.equal(office.sections.length, 2);
  assert.equal(office.sections[0].upstreamID, "Vespera1");
  assert.match(office.sections[0].latin, /Deus in adiutórium/);
  assert.match(office.sections[0].english, /O God, come to my assistance/);
  assert.equal(office.sections[1].rubricLatin, "ex Psalterio");
});

test("Divinum Officium importer separates Matins blessings, readings, and responsories", () => {
  const html = `
    <p class="cen"><span class="x">Feria ~ III. classis<br></span></p><span class="s">Tempus</span>
    <TABLE><TR><TD ID="Matutinum9"><p><b>Benedictio</b><br>
      ℣. Iube, Dómine, benedícere.<br><br>Benedictio. Deus nos benedícat.<br><br>℟. Amen.<br><br>
      <b>Lectio 1</b><br><br>In princípio erat Verbum.<br><br>℣. Tu autem, Dómine.<br><br>
      ℟. Deo grátias.<br><br>℟. In princípio.<br><br>* Et Verbum erat apud Deum.</p></TD>
      <TD><p><b>Blessing</b><br>℣. Grant, Lord, a blessing.<br><br>May God bless us.<br><br>℟. Amen.<br><br>
      <b>Reading 1</b><br><br>In the beginning was the Word.<br><br>℣. But thou, O Lord.<br><br>
      ℟. Thanks be to God.<br><br>℟. In the beginning.<br><br>* And the Word was with God.</p></TD></TR></TABLE>`;
  const office = parseDivinumOffice(html, {
    date: "2026-01-01", hour: "matins", file: "fixture.html", sha256: "fixture"
  });
  assert.deepEqual(office.sections.map(section => section.kind), [
    "blessing", "reading", "responsory"
  ]);
  assert.equal(office.sections[1].titleLatin, "Lectio 1");
  assert.doesNotMatch(office.sections[1].latin, /In princípio\.\n\n\*/);
  assert.match(office.sections[2].latin, /^℟\. In princípio/);
});

test("Divinum Officium importer keeps inline directions distinct from prayer text", () => {
  const office = parseDivinumOffice(`
    <p class="cen"><span class="rd">Feria ~ IV. classis<br/></span></p>
    <TR><TD ID="Completorium1"><p><b>Preces</b><br/>
      Confíteor: <span class="w">(percutit sibi pectus)</span> mea culpa.<br/>
      <span class="w">110:9</span> Sanctum et terríbile nomen eius.
    </p></TD><TD><p><b>Prayers</b><br/>
      I confess: <span class="w">strikes his breast</span> through my fault.<br/>
      <span class="w">The first verse of the following hymn is said genuflecting.</span><br/>
      <span class="w">110:9</span> Holy and terrible is his name.
    </p></TD></TR>
  `, {
    date: "2026-08-19",
    hour: "compline",
    file: "inline-rubrics.html",
    sha256: "fixture"
  });

  assert.match(office.sections[0].latin, /\(percutit sibi pectus\) mea culpa/);
  assert.match(office.sections[0].english, /\(strikes his breast\) through my fault/);
  assert.match(
    office.sections[0].english,
    /\(The first verse of the following hymn is said genuflecting\.\)/
  );
  assert.doesNotMatch(office.sections[0].english, /\(genuflecting\)/);
  assert.match(office.sections[0].latin, /110:9 Sanctum/);
  assert.doesNotMatch(office.sections[0].latin, /\(110:9\)/);
});

test("Divinum Officium snapshot import rejects changed source files", () => {
  const directory = mkdtempSync(join(tmpdir(), "hours-snapshot-"));
  writeFileSync(join(directory, "office.html"), "<html>changed</html>");
  writeFileSync(join(directory, "snapshot-manifest.json"), JSON.stringify({
    revision: "pinned",
    rubrics: "Rubrics 1960 - 1960",
    records: [{
      date: "2026-07-23",
      hour: "matins",
      file: "office.html",
      sha256: "0".repeat(64)
    }]
  }));
  assert.throws(
    () => loadSnapshotDirectory(directory),
    /does not match its snapshot checksum/
  );
});

test("Divinum Officium snapshot import can restrict independent audits", () => {
  const directory = mkdtempSync(join(tmpdir(), "hours-snapshot-filter-"));
  const html = readFileSync(
    new URL("../Fixtures/divinum-office-fragment.html", import.meta.url),
    "utf8"
  );
  const digest = createHash("sha256").update(html).digest("hex");
  writeFileSync(join(directory, "lauds.html"), html);
  writeFileSync(join(directory, "vespers.html"), html);
  writeFileSync(join(directory, "snapshot-manifest.json"), JSON.stringify({
    revision: "pinned",
    rubrics: "Rubrics 1960 - 1960",
    records: [{
      date: "2026-04-06",
      hour: "lauds",
      file: "lauds.html",
      sha256: digest
    }, {
      date: "2026-04-06",
      hour: "vespers",
      file: "vespers.html",
      sha256: digest
    }]
  }));

  const imported = loadSnapshotDirectory(
    directory,
    record => record.hour === "lauds"
  );
  assert.equal(imported.offices.length, 1);
  assert.equal(imported.offices[0].hour, "lauds");
});

test("scored reference identifies Gregobase, Nocturnale, and generated GABC", () => {
  const html = `
    <h3>Hymnus</h3>
    <a href="https://gregobase.selapa.net/chant.php?id=16878">
      <div class="chant" title="Deus tuórum" data-mode="8"></div>
    </a>
    <script>var gabc = "(c4) De(f)us(g) (::)";</script>
    <h4>Psalmus 61</h4>
    <a href="https://nocturnale.marteo.fr/chant/F5N1A1/">
      <div class="chant" title="In Deo" data-mode="4e"></div>
    </a>
    <script>var gabc = \`(c4) In(f) De(e)o.(d.) (::)\`;</script>
    <div data-psalm="1"></div>
    <script>var gabc = "(c4) Non(h)ne(g) (::)";</script>
  `;
  const scores = parseScoredReference(html);
  assert.equal(scores.length, 3);
  assert.deepEqual(scores.map(score => score.source), [
    "Gregobase",
    "Nocturnale Romanum",
    "Chant Tools"
  ]);
  assert.deepEqual(scores.map(score => score.sourceID), ["16878", "F5N1A1", undefined]);

  const sections = officeSectionsFromScoredReference(scores);
  assert.deepEqual(sections.map(section => section.rubric), [null, null, null]);
  assert.deepEqual(
    sections.map(section => section.chant?.provenance.collection),
    ["Gregobase", "Nocturnale Romanum", "Chant Tools"]
  );
});

test("scored reference binds metadata to the container used by each script", () => {
  const html = `
    <div class="section">
      <h3>Lectio brevis</h3>
      <a href="https://gregobase.selapa.net/chant.php?id=100">
        <div id="jube" class="chant" title="Iube Dómine" data-mode="6"></div>
      </a>
      <div id="blessing"></div>
      <script>
        var gabc = "(c3) Noc(h)tem(h) qui(h)é(h)tam.(g.) (::)";
        document.getElementById("blessing").dataset.rendered = "true";
      </script>
    </div>
  `;

  const [score] = parseScoredReference(html);
  assert.equal(score.heading, "Lectio brevis");
  assert.equal(score.incipit, "");
  assert.equal(score.mode, undefined);
  assert.equal(score.source, "Chant Tools");
  assert.equal(score.sourceURL, undefined);
});

test("scored reference requires and records generated reading tones", () => {
  const html = `
    <div class="section">
      <h3>Lectio brevis</h3>
      <iframe src="/tones-api/lesson_ordinary_tone/readings.html?text=Noctem+quietam"></iframe>
    </div>
  `;
  assert.throws(
    () => parseScoredReference(html),
    /generated reading tones/
  );

  const scores = parseScoredReference(html, {
    generateReadingTone(text, tone) {
      assert.equal(text, "Noctem quietam");
      assert.equal(tone, "Lesson Ordinary Tone");
      return "centering-scheme: latin; %% (c3) Noc(h)tem(h) qui(g)e(f)tam.(h.) (::)";
    }
  });
  assert.equal(scores.length, 1);
  assert.equal(scores[0].source, "Chant Tools");
  assert.equal(scores[0].heading, "Lectio brevis");
});

test("generated GABC headers preserve heading letters", () => {
  const [section] = officeSectionsFromScoredReference([{
    id: "reading",
    heading: "Lectio brevis",
    incipit: "Noctem quietam",
    gabc: "(c3) Noc(h)tem(h) qui(g)e(f)tam.(h.) (::)",
    source: "Chant Tools"
  }]);
  assert.match(section.chant?.gabc ?? "", /^name: Lectio brevis;/);
});

test("scored reference uses detailed mode for complete psalm notation", () => {
  const url = new URL(scoredOfficeURL("2026-07-24", "terce"));
  assert.equal(url.searchParams.get("compact"), "");
  assert.equal(url.searchParams.get("office"), "tertia");
});

test("scored reference preserves a repeated antiphon in source order", () => {
  const html = `
    <h4>Psalmus 79</h4>
    <div class="chant" title="Éxcita Dómine"></div>
    <script>var gabc = "(c4) Ex(f)ci(g)ta.(h.) (::)";</script>
    <div data-psalm="1"></div>
    <script>var gabc = "(c4) Qui(f) re(g)gis.(h.) (::)";</script>
    <div class="chant" title="Éxcita Dómine"></div>
    <script>var gabc = "(c4) Ex(f)ci(g)ta.(h.) (::)";</script>
  `;

  const scores = parseScoredReference(html);

  assert.equal(scores.length, 3);
  assert.equal(scores[0].gabc, scores[2].gabc);
  assert.notEqual(scores[0].gabc, scores[1].gabc);
});

test("ordered reference anchors scores to their visible containers instead of late scripts", () => {
  const html = readFileSync(
    new URL(
      "../Fixtures/breviarium-ordered-compline-fragment.html",
      import.meta.url
    ),
    "utf8"
  );
  const office = parseOrderedReferenceOffice(html, {
    generateReadingTone(text, tone) {
      assert.match(text, /Noctem quiétam/);
      assert.equal(tone, "Lesson Ordinary Tone");
      return "name: Benedictio; %% (c3) Noc(h)tem(h) qui(g)é(f)tam.(h.) (::)";
    }
  });

  assert.equal(office.sourceSectionCount, 3);
  assert.equal(office.scoreCount, 5);
  assert.deepEqual(
    office.sections.map(section => [
      section.sourceRole,
      section.title,
      section.latin
    ]),
    [
      ["chant", "Lectio brevis", "Iube Dómine benedícere"],
      ["rubric", "Lectio brevis", "Benedictio:"],
      ["chant", "Lectio brevis", "Noctem quiétam"],
      [
        "rubric",
        "Prex poenitentialis",
        "Examen conscientiæ vel Pater Noster totum secreto."
      ],
      ["prose", "Prex poenitentialis", "Pater noster, qui es in cælis."],
      ["prose", "Prex poenitentialis", "Confíteor Deo omnipoténti."],
      ["chant", "Canticum: Nunc dimittis", "Salva nos, Dómine"],
      ["chant", "Canticum: Nunc dimittis", "Nunc dimíttis servum tuum"],
      [
        "prose",
        "Canticum: Nunc dimittis",
        "2. Quia vidérunt óculi mei * salutáre tuum,"
      ],
      [
        "prose",
        "Canticum: Nunc dimittis",
        "3. Quod parásti * ante fáciem ómnium populórum,"
      ],
      ["chant", "Canticum: Nunc dimittis", "Salva nos, Dómine"]
    ]
  );

  const canticle = office.sections.filter(section =>
    section.title === "Canticum: Nunc dimittis"
  );
  assert.ok(canticle[1].sourceOffset < canticle[2].sourceOffset);
  assert.equal(canticle[0].chant?.id, canticle[4].chant?.id);
  assert.notEqual(canticle[0].id, canticle[4].id);
  assert.match(canticle[0].english ?? "", /Protect us/);
  assert.match(canticle[1].english ?? "", /Now thou dost dismiss/);
});

test("ordered reference refuses uncompiled frames and unfamiliar visible blocks", () => {
  const uncompiledFrame = `
    <div class="section">
      <h3>Lectio brevis</h3>
      <iframe src="/unknown/remote-prayer.html"></iframe>
    </div>
  `;
  assert.throws(
    () => parseOrderedReferenceOffice(uncompiledFrame),
    /web content cannot enter the native corpus/
  );

  const unknownVisibleBlock = `
    <div class="section">
      <h3>Lectio brevis</h3>
      <aside>This new source structure must be reviewed.</aside>
    </div>
  `;
  assert.throws(
    () => parseOrderedReferenceOffice(unknownVisibleBlock),
    /Unsupported visible <aside>/
  );
});

test("ordered reference preserves mixed Matins prayer wrappers", () => {
  const html = `
    <div class="section">
      <h3>Absolutio</h3>
      <div class="reading_text">
        <p>Pater noster, qui es in cælis.</p><br>
        <span class="red">℣.</span> Et ne nos indúcas in tentatiónem:<br>
        <span class="red">℟.</span> Sed líbera nos a malo.<br>
        <span class="rubrics">Absolutio.</span>
        Exáudi, Dómine Iesu Christe, preces servórum tuórum.<br>
        <span class="red">℟.</span> Amen.
      </div>
    </div>
  `;

  const office = parseOrderedReferenceOffice(html);
  assert.deepEqual(
    office.sections.map(section => section.latin),
    [
      "Pater noster, qui es in cælis.",
      "℣. Et ne nos indúcas in tentatiónem:",
      "℟. Sed líbera nos a malo.",
      "Absolutio. Exáudi, Dómine Iesu Christe, preces servórum tuórum.",
      "℟. Amen."
    ]
  );
});

test("ordered reference pairs a direct-text hymn with its following translation", () => {
  const ordered = parseOrderedReferenceOffice(`
    <html><body>
      <div class="section">
        <h3>Hymnus</h3>
        <span class="rubrics">Hymn.</span>
        Vírginis Proles, Opiféxque Matris.<br>
        Accipe votum.
        <p class="tr">Son of a virgin, maker of thy mother. Hear our devotion.</p>
      </div>
    </body></html>
  `);
  assert.equal(ordered.sections.length, 2);
  assert.equal(ordered.sections[0].sourceRole, "rubric");
  assert.equal(ordered.sections[1].sourceRole, "prose");
  assert.match(ordered.sections[1].latin, /Vírginis Proles/);
  assert.match(ordered.sections[1].english ?? "", /Son of a virgin/);
});

test("ordered reference consumes chant anchors nested in reading-text wrappers", () => {
  const ordered = parseOrderedReferenceOffice(`
    <html><body>
      <div class="section">
        <h3>Oratio</h3>
        <div class="reading_text">
          <p>Pater noster, qui es in cælis.</p>
          <div id="response"></div>
          <script>
            var gabc = "(c4) V/.() Dó(g)mi(h)ne.(g.) (::)";
            document.getElementById("response");
          </script>
        </div>
      </div>
    </body></html>
  `);
  assert.equal(ordered.scoreCount, 1);
  assert.equal(ordered.sections.filter(section => section.sourceRole === "chant").length, 1);
});

test("ordered snapshots replace the two-stream fuzzy merge", () => {
  const html = readFileSync(
    new URL(
      "../Fixtures/breviarium-ordered-compline-fragment.html",
      import.meta.url
    ),
    "utf8"
  );
  const ordered = parseOrderedReferenceOffice(html, {
    generateReadingTone() {
      return "name: Benedictio; %% (c3) Noc(h)tem(h) qui(g)é(f)tam.(h.) (::)";
    }
  });
  const office: OfficeDocument = {
    id: "2026-07-25-compline",
    date: { year: 2026, month: 7, day: 25 },
    hour: "compline",
    titleLatin: "Ad Completorium",
    titleEnglish: "Compline",
    contextLabel: "Feria",
    sourceVersion: "Rubrics 1960 - 1960",
    observance: {
      observanceID: "divinum-officium/2026-07-25/feria",
      titleLatin: "Feria",
      rank: "fourthClass",
      commemorations: []
    },
    sections: [{
      id: "legacy-flat-text",
      kind: "canticle",
      title: "Canticum Simeonis",
      latin: "This legacy stream would require string matching.",
      chant: null
    }, {
      id: "bilingual-source",
      kind: "prayer",
      title: "Prex poenitentialis",
      titleEnglish: "Penitential prayer",
      rubric: "secreto",
      rubricEnglish: "silently",
      latin: "Pater noster, qui es in cælis.",
      english: "Our Father, who art in heaven.",
      chant: null
    }]
  };
  const source: LoadedScoredOffice = {
    date: "2026-07-25",
    hour: "compline",
    file: "2026-07-25-compline.html",
    sha256: "snapshot",
    sourceURL: "https://breviariumgregorianum.com/",
    scoreCount: ordered.scoreCount,
    scores: [],
    observance: {
      titleLatin: "Feria",
      rank: "fourthClass",
      commemorations: []
    },
    orderedSections: ordered.sections,
    visibleContentDigest: canonicalVisibleContentDigest(ordered.sections)
  };

  const result = officeWithScoredReference(office, source);
  assert.equal(result.format, "authoritativeOrdered");
  assert.equal(
    result.visibleContentDigest,
    canonicalVisibleContentDigest(result.sections)
  );
  assert.equal(
    result.sections.some(section => section.id === "legacy-flat-text"),
    false
  );
  assert.equal(result.sections.some(section => /Pater noster/.test(section.latin)), true);
  assert.ok(
    result.sections.findIndex(section => /Nunc dimíttis/.test(section.latin))
    < result.sections.findIndex(section => /^2\. Quia vidérunt/.test(section.latin))
  );
  assert.equal(
    new Set(result.sections.map(section => section.id)).size,
    result.sections.length
  );
  const enriched = result.sections.find(
    section => section.latin === "Pater noster, qui es in cælis."
  );
  assert.equal(enriched?.english, "Our Father, who art in heaven.");
  assert.equal(enriched?.titleEnglish, "Penitential prayer");
  assert.equal(
    result.sections.find(section => section.latin === "Benedictio:")?.english,
    "Blessing:"
  );
});

test("scored lyric alignment preserves complete opening and psalm translations", () => {
  const chant = (id: string, incipit: string, gabc: string) => ({
    id,
    incipit,
    gabc,
    mode: null,
    reviewStatus: "generatedFormula" as const,
    provenance: {
      collection: "Chant Tools",
      sourceBook: "fixture",
      sourceURL: null,
      license: "Unlicense",
      snapshot: id
    },
    timeline: { events: [] }
  });
  const office: OfficeDocument = {
    id: "2026-08-19-sext",
    date: { year: 2026, month: 8, day: 19 },
    hour: "sext",
    titleLatin: "Ad Sextam",
    titleEnglish: "Sext",
    contextLabel: "S. Joannis Eudes Confessoris",
    sourceVersion: "fixture",
    observance: {
      observanceID: "fixture/john-eudes",
      titleLatin: "S. Joannis Eudes Confessoris",
      rank: "thirdClass",
      commemorations: []
    },
    sections: [{
      id: "opening-source",
      kind: "opening",
      title: "Incipit",
      latin: "Incipit\n\n℣. Deus in adiutórium meum inténde.\n\n℟. Dómine, ad adiuvándum me festína.\n\nGlória Patri.\n\nSicut erat in princípio et in sǽcula sæculórum.\n\nAllelúia.",
      english: "Start\n\n℣. O God, come to my assistance.\n\n℟. O Lord, make haste to help me.\n\nGlory be to the Father.\n\nAs it was in the beginning, world without end.\n\nAlleluia.",
      chant: null
    }, {
      id: "psalm-source",
      kind: "psalm",
      title: "Psalmi",
      latin: "Psalmus 56\n\n56:2 Miserére mei, Deus.\n\n56:3 Clamábo ad Deum altíssimum.",
      english: "Psalm 56\n\n56:2 Have mercy on me, O God.\n\n56:3 I will cry to God the most High.",
      chant: null
    }, {
      id: "pater-source",
      kind: "prayer",
      title: "Pater",
      latin: "Pater noster.\n\nAllelúia.",
      english: "Our Father.\n\nAlleluia.",
      chant: null
    }, {
      id: "responsory-source",
      kind: "reading",
      title: "Lectio 3",
      latin: "℟. Benedíctus qui venit in nómine Dómini, Deus Dóminus, et illúxit nobis.\n\n℟. Allelúia.\n\n℣. Hæc dies quam fecit Dóminus, exsultémus et lætémur in ea.",
      english: "℟. Blessed be he that cometh in the name of the Lord; God is the Lord who hath showed us light.\n\n℟. Alleluia.\n\n℣. This is the day which the Lord hath made; let us rejoice and be glad in it.",
      chant: null
    }]
  };
  const orderedSections = [{
    id: "opening-score",
    kind: "opening" as const,
    title: "Incipit",
    latin: "V/",
    english: null,
    rubric: null,
    chant: chant("opening-score", "V/", "(c3) V/.() De(h)us(h) in(h) ad(h)ju(h)tó(h)ri(h)um(h) me(h)um(h) in(h)tén(h)de.(h.) (::) R/.() Dó(h)mi(h)ne(h) ad(h) ad(h)ju(h)ván(h)dum(h) me(h) fe(h)stí(h)na.(h.) (::) Gló(h)ri(h)a(h) Pa(h)tri.(h.) (::) Sic(h)ut(h) e(h)rat(h) in(h) prin(h)cí(h)pi(h)o(h) et(h) in(h) sae(h)cu(h)la(h) sae(h)cu(h)ló(h)rum.(h.) (::) Al(h)le(h)lú(h){ia}.(h.) (::)"),
    sourceOffset: 1,
    sourceRole: "chant" as const
  }, {
    id: "psalm-score",
    kind: "psalm" as const,
    title: "Psalmus 56",
    latin: "Miserére mei, Deus",
    english: "Have mercy on me, O God.",
    rubric: null,
    chant: chant("psalm-score", "Miserére mei, Deus", "(c4) 1. Mi(f)se(g)ré(h)re(h) me(h)i,(h) De(h)us.(h.) 2.(::) Cla(h)má(h)bo(h) ad(h) De(h)um(h) al(h)tís(h)si(h)mum.(h.) (::)"),
    sourceOffset: 2,
    sourceRole: "chant" as const
  }, {
    id: "mislabeled-responsory-score",
    kind: "prayer" as const,
    title: "Pater",
    latin: "Benedíctus qui venit in nómine Dómini",
    english: null,
    rubric: null,
    chant: chant("mislabeled-responsory-score", "Benedíctus qui venit", "(c3) Be(h)ne(h)díc(h)tus(h) qui(h) ve(h)nit(h) in(h) nó(h)mi(h)ne(h) Dó(h)mi(h)ni,(h) De(h)us(h) Dó(h)mi(h)nus,(h) et(h) il(h)lú(h)xit(h) no(h)bis.(h) (::) Al(h)le(h)lú(h)ia.(h) (::) Hæc(h) di(h)es(h) quam(h) fe(h)cit(h) Dó(h)mi(h)nus,(h) ex(h)sul(h)té(h)mus(h) et(h) læ(h)té(h)mur(h) in(h) e(h)a.(h) (::)"),
    sourceOffset: 3,
    sourceRole: "chant" as const
  }];
  const source: LoadedScoredOffice = {
    date: "2026-08-19",
    hour: "sext",
    file: "fixture.html",
    sha256: "fixture",
    sourceURL: "https://example.invalid",
    scoreCount: 3,
    scores: [],
    observance: {
      titleLatin: office.contextLabel,
      rank: "thirdClass",
      commemorations: []
    },
    orderedSections,
    visibleContentDigest: canonicalVisibleContentDigest(orderedSections)
  };

  const result = officeWithScoredReference(office, source);
  assert.match(result.sections[0].english ?? "", /O God, come to my assistance/);
  assert.match(result.sections[0].english ?? "", /Glory be to the Father/);
  assert.match(result.sections[0].english ?? "", /world without end/);
  assert.match(result.sections[0].english ?? "", /Alleluia/);
  assert.match(result.sections[1].english ?? "", /I will cry to God the most High/);
  assert.match(result.sections[2].english ?? "", /Blessed be he that cometh/);
  assert.match(result.sections[2].english ?? "", /This is the day which the Lord hath made/);
});

test("legacy ordered snapshots remove leaked GABC comments from chant text", () => {
  const office: OfficeDocument = {
    id: "2026-07-28-matins",
    date: { year: 2026, month: 7, day: 28 },
    hour: "matins",
    titleLatin: "Ad Matutinum",
    contextLabel: "SS. Nazarii et Celsi Martyrum",
    sourceVersion: "Rubrics 1960 - 1960",
    observance: {
      observanceID: "divinum-officium/2026-07-28/nazarii-et-celsi",
      titleLatin: "SS. Nazarii et Celsi Martyrum",
      rank: "thirdClass",
      commemorations: []
    },
    sections: []
  };
  const orderedSections = [{
    id: "ordered-reference-0",
    kind: "psalm" as const,
    title: "Psalmus 94",
    latin: "% Hódie, si vocem ejus audiéritis",
    english: null,
    rubric: null,
    chant: {
      id: "invitatory",
      incipit: "% Hódie, si vocem ejus audiéritis",
      gabc: "name: Invitatorium; %% (c3)\r\n%\r\nHó(h)die(i) (::)",
      mode: "3b",
      reviewStatus: "generatedFormula" as const,
      provenance: {
        collection: "Chant Tools",
        sourceBook: "Breviarium Gregorianum source concordance",
        sourceURL: null,
        license: "Unlicense",
        snapshot: "snapshot"
      },
      timeline: { events: [] }
    },
    sourceOffset: 100,
    sourceRole: "chant" as const
  }];
  const result = officeWithScoredReference(office, {
    date: "2026-07-28",
    hour: "matins",
    file: "2026-07-28-matins.html",
    sha256: "snapshot",
    sourceURL: "https://breviariumgregorianum.com/",
    scoreCount: 1,
    scores: [],
    observance: {
      titleLatin: "SS. Nazarii et Celsi Martyrum",
      rank: "thirdClass",
      commemorations: []
    },
    orderedSections,
    visibleContentDigest: canonicalVisibleContentDigest(orderedSections)
  });

  assert.equal(result.sections[0].latin, "Hódie, si vocem ejus audiéritis");
  assert.equal(
    result.sections[0].chant?.incipit,
    "Hódie, si vocem ejus audiéritis"
  );
  assert.equal(
    result.visibleContentDigest,
    canonicalVisibleContentDigest(result.sections)
  );
});

test("calendar concordance uses an exact stable identity rather than word overlap", () => {
  assert.equal(
    canonicalLiturgicalIdentity("In Conceptione Immaculáta B. Mariæ Virginis"),
    "in conceptione immaculata b mariae virginis"
  );
  assert.equal(
    requireSameLiturgicalIdentity(
      "In Conceptione Immaculáta B. Mariæ Virginis",
      "In Conceptione Immaculata B. Mariae Virginis",
      "calendar"
    ),
    "in-conceptione-immaculata-b-mariae-virginis"
  );
  assert.equal(
    requireSameLiturgicalIdentity(
      "SS. Soteris et Caii Summorum Pontificum et Martyrum",
      "SS. Soteris et Caji Summorum Pontificum et Martyrum",
      "calendar"
    ),
    "ss-soteris-et-caii-summorum-pontificum-et-martyrum"
  );
  assert.throws(
    () => requireSameLiturgicalIdentity(
      "S. Joannis Apostoli et Evangelistae",
      "S. Joannis Baptistae",
      "calendar"
    ),
    /differs exactly/
  );
});

test("reference header metadata preserves first Vespers and all commemorations", () => {
  const metadata = parseReferenceObservance(`
    <html>
      <head>
        <title>Vespers of the Most Holy Name of Jesus - Breviarium Gregorianum</title>
      </head>
      <body>
        <p class="classis">II. classis</p>
        <h1>Sanctissimi Nominis Jesu</h1>
        <p class="subtitle">Vespera de sequenti.</p>
        <div class="section"><h4>Commemoratio S. Telesphori Papæ et Martyris</h4></div>
      </body>
    </html>
  `, "vespers");

  assert.deepEqual(metadata, {
    titleLatin: "Sanctissimi Nominis Jesu",
    titleEnglish: "the Most Holy Name of Jesus",
    rank: "secondClass",
    eveningContext: "firstVespers",
    commemorations: [{
      titleLatin: "S. Telesphori Papæ et Martyris",
      titleEnglish: null
    }]
  });
});

test("reference header metadata recognizes ligatured second Vespers", () => {
  const metadata = parseReferenceObservance(`
    <html>
      <body>
        <p class="classis">I. classis</p>
        <h1>In Dedicatione S. Michaëlis Archangelis</h1>
        <p class="subtitle">Vespera de præcedenti.</p>
      </body>
    </html>
  `, "vespers");

  assert.equal(metadata.eveningContext, "secondVespers");
});

test("reference header metadata accepts observance-only English page titles", () => {
  const metadata = parseReferenceObservance(`
    <html>
      <head>
        <title>Tuesday of the Twelfth Week after Pentecost - Breviarium Gregorianum</title>
      </head>
      <body>
        <h1>Feria tertia infra Hebdomadam XII post Pentecosten</h1>
      </body>
    </html>
  `, "lauds");

  assert.equal(
    metadata.titleEnglish,
    "Tuesday of the Twelfth Week after Pentecost"
  );
});

test("evening resolution distinguishes first, second, and ordinary Vespers", () => {
  const localDay = (date: string) => {
    const [year, month, day] = date.split("-").map(Number);
    return { year, month, day };
  };
  const day = (
    date: string,
    titleLatin: string,
    rank: "firstClass" | "thirdClass"
  ) => ({
    date: localDay(date),
    observanceID: titleLatin,
    titleLatin,
    rank,
    color: null,
    season: "Test",
    eveningContext: null,
    commemorations: [],
    sourceVersion: "test"
  });
  const office = (
    date: string,
    hour: OfficeHour,
    titleLatin: string,
    rank: "firstClass" | "thirdClass"
  ): OfficeDocument => ({
    id: `${date}-${hour}`,
    date: localDay(date),
    hour,
    titleLatin: `Ad ${hour}`,
    contextLabel: titleLatin,
    sourceVersion: "test",
    observance: {
      observanceID: titleLatin,
      titleLatin,
      rank,
      color: null,
      season: "Test",
      eveningContext: null,
      commemorations: []
    },
    sections: [{
      id: `${date}-${hour}-section`,
      kind: "prayer",
      title: "Oratio",
      latin: "Orémus."
    }]
  });
  const wenceslaus = "S. Wenceslai Ducis et Martyris";
  const michaelmas = "In Dedicatione S. Michaëlis Archangelis";
  const jerome = "S. Hieronymi Presbyteri";
  const days = [
    day("2026-09-28", wenceslaus, "thirdClass"),
    day("2026-09-29", michaelmas, "firstClass"),
    day("2026-09-30", jerome, "thirdClass")
  ];
  const offices = [
    office("2026-09-28", "matins", wenceslaus, "thirdClass"),
    office("2026-09-28", "vespers", michaelmas, "firstClass"),
    office("2026-09-28", "compline", michaelmas, "firstClass"),
    office("2026-09-29", "matins", michaelmas, "firstClass"),
    office("2026-09-29", "vespers", michaelmas, "firstClass"),
    office("2026-09-29", "compline", michaelmas, "firstClass"),
    office("2026-09-30", "matins", jerome, "thirdClass"),
    office("2026-09-30", "vespers", jerome, "thirdClass"),
    office("2026-09-30", "compline", jerome, "thirdClass")
  ];
  const input: CorpusInput = {
    manifest: {
      schemaVersion: 1,
      corpusVersion: "test",
      minimumAppVersion: "0.1.0",
      createdAt: "2026-01-01T00:00:00Z",
      rubrics: "Rubrics 1960 - 1960",
      sources: [],
      coverage: {
        startDate: localDay("2026-09-28"),
        endDate: localDay("2026-09-30"),
        expectedOfficeCount: offices.length,
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

  const resolved = withResolvedEveningContexts(input);
  assert.deepEqual(
    resolved.days.map(value => value.eveningContext),
    ["firstVespers", "secondVespers", "ferialVespers"]
  );
  assert.deepEqual(
    resolved.offices
      .filter(value => value.hour === "vespers")
      .map(value => value.observance?.eveningContext),
    ["firstVespers", "secondVespers", "ferialVespers"]
  );
  assert.deepEqual(
    resolved.offices
      .filter(value => value.hour === "compline")
      .map(value => value.observance?.eveningContext),
    ["firstVespers", "secondVespers", "ferialVespers"]
  );
});

test("scored compilation rejects legacy snapshots without ordered sidecars", () => {
  const office: OfficeDocument = {
    id: "2026-12-08-matins",
    date: { year: 2026, month: 12, day: 8 },
    hour: "matins",
    titleLatin: "Ad Matutinum",
    contextLabel: "In Conceptione Immaculata",
    sourceVersion: "test",
    sections: [{
      id: "legacy",
      kind: "opening",
      title: "Incipit",
      latin: "Dómine, lábia mea apéries."
    }]
  };
  assert.throws(
    () => officeWithScoredReference(office, {
      date: "2026-12-08",
      hour: "matins",
      file: "legacy.html",
      sha256: "snapshot",
      sourceURL: "https://breviariumgregorianum.com/",
      scoreCount: 1,
      scores: [],
      observance: {
        titleLatin: "In Conceptione Immaculata",
        rank: "firstClass",
        commemorations: []
      }
    }),
    /no ordered sidecar/
  );
});

test("incomplete scored audits omit gaps instead of restoring legacy offices", () => {
  const corpus = structuredClone(loadCorpus(fixture));
  const authoritative = {
    ...corpus.offices[0],
    format: "authoritativeOrdered" as const,
    visibleContentDigest: canonicalVisibleContentDigest(corpus.offices[0].sections)
  };
  const key = [
    String(authoritative.date.year).padStart(4, "0"),
    String(authoritative.date.month).padStart(2, "0"),
    String(authoritative.date.day).padStart(2, "0")
  ].join("-") + `:${authoritative.hour}`;

  const selected = authoritativeOfficesOnly(
    corpus.offices,
    new Map([[key, authoritative]])
  );

  assert.deepEqual(selected, [authoritative]);
  assert.ok(selected.every(office => office.format === "authoritativeOrdered"));
});

test("shipping corpus uses metadata-only placeholders for reference gaps", () => {
  const corpus = structuredClone(loadCorpus(fixture));
  const source = corpus.offices[0];
  const key = [
    String(source.date.year).padStart(4, "0"),
    String(source.date.month).padStart(2, "0"),
    String(source.date.day).padStart(2, "0")
  ].join("-") + `:${source.hour}`;
  const authoritative = {
    ...source,
    format: "authoritativeOrdered" as const,
    visibleContentDigest: canonicalVisibleContentDigest(source.sections),
    observance: {
      observanceID: "fixture/authoritative",
      titleLatin: source.contextLabel,
      commemorations: []
    }
  };
  const offices = officesWithUnavailablePlaceholders(
    corpus.offices,
    new Map([[key, authoritative]])
  );

  assert.equal(offices.length, corpus.offices.length);
  assert.equal(offices[0].format, "authoritativeOrdered");
  for (const placeholder of offices.slice(1)) {
    assert.equal(placeholder.format, "contentUnavailable");
    assert.equal(placeholder.visibleContentDigest, null);
    assert.deepEqual(placeholder.sections, []);
    assert.ok(placeholder.observance?.titleLatin);
  }

  const classifiedOffices = offices.map(office => {
    if (
      (office.hour === "vespers" || office.hour === "compline")
      && office.observance
    ) {
      return {
        ...office,
        observance: {
          ...office.observance,
          eveningContext: "ferialVespers" as const
        }
      };
    }
    return office;
  });

  const shippable = {
    ...corpus,
    manifest: {
      ...corpus.manifest,
      coverage: {
        ...corpus.manifest.coverage,
        generatedOfficeCount: offices.length,
        authoritativeOfficeCount: 1
      }
    },
    offices: classifiedOffices
  };
  assert.doesNotThrow(() => validateCorpus(shippable, true));
  assert.throws(
    () => validateCorpus({
      ...shippable,
      offices: classifiedOffices.map((office, index) => index === 1
        ? { ...office, sections: source.sections }
        : office)
    }, true),
    /must not contain prayer text/
  );
});

test("high-risk observance audit pins metadata and explicit source gaps", () => {
  const record: LoadedScoredOffice = {
    date: "2026-12-07",
    hour: "vespers",
    file: "office.html",
    sha256: "snapshot",
    sourceURL: "https://example.invalid",
    scoreCount: 1,
    scores: [],
    observance: {
      titleLatin: "In Conceptione Immaculata Beatæ Mariæ Virginis",
      titleEnglish: "the Immaculate Conception of the Blessed Virgin Mary",
      rank: "firstClass",
      eveningContext: "firstVespers",
      commemorations: [{
        titleLatin: "Feria II infra Hebdomadam II Adventus",
        titleEnglish: null
      }]
    }
  };
  const expectations = [{
    date: record.date,
    hour: record.hour,
    available: true,
    titleLatin: record.observance.titleLatin,
    titleEnglish: record.observance.titleEnglish,
    rank: record.observance.rank,
    eveningContext: record.observance.eveningContext,
    commemorations: record.observance.commemorations.map(item => item.titleLatin)
  }, {
    date: "2026-04-06",
    hour: "lauds" as const,
    available: false,
    reason: "Pinned reference returned HTTP 500."
  }];

  assert.doesNotThrow(() => auditExpectedObservances([record], expectations));
  assert.throws(
    () => auditExpectedObservances([{
      ...record,
      observance: { ...record.observance, eveningContext: null }
    }], expectations),
    /metadata changed/
  );
});

test("high-risk gaps pin their independent special-office text", () => {
  const independentOffice = {
    date: "2026-04-06",
    hour: "lauds" as const,
    observanceLatin: "Die II infra octavam Paschæ",
    rankLatin: "Dies Octavæ I. classis",
    seasonLatin: "",
    sections: [{
      upstreamID: "Laudes8",
      titleLatin: "Canticum: Benedictus",
      titleEnglish: "Canticle: Benedictus",
      rubricLatin: "Antiphona ex Proprio de Tempore",
      rubricEnglish: "Antiphon from the Proper of the season",
      latin: "Ant. Iesus iunxit se * discípulis suis in via.",
      english: "Ant. Jesus drew near * to his disciples on the way."
    }, {
      upstreamID: "Laudes9",
      titleLatin: "Oratio",
      titleEnglish: "Prayer",
      rubricLatin: "ex Proprio de Tempore",
      rubricEnglish: "from the Proper of the season",
      latin: "Orémus. Deus, qui solemnitate paschali.",
      english: "Let us pray. O God, who by the paschal solemnity."
    }],
    sourceFile: "2026-04-06-lauds.html",
    sourceSHA256: "fixture"
  };
  const expectations = [{
    date: independentOffice.date,
    hour: independentOffice.hour,
    available: false,
    reason: "Pinned reference returned HTTP 500.",
    independentSource: {
      observanceLatin: independentOffice.observanceLatin,
      visibleContentDigest: canonicalImportedOfficeDigest(independentOffice),
      requiredLatinIncipits: [
        "Iesus iunxit se",
        "Deus, qui solemnitate paschali"
      ]
    }
  }];

  assert.doesNotThrow(
    () => auditExpectedObservances([], expectations, [independentOffice])
  );
  assert.throws(
    () => auditExpectedObservances([], expectations, [{
      ...independentOffice,
      sections: independentOffice.sections.slice(1)
    }]),
    /independent visible content changed/
  );
  assert.throws(
    () => auditExpectedObservances([], expectations),
    /missing its independent Divinum Officium validation/
  );
});

test("scored reference decodes browser-compatible identity escapes", () => {
  const html = String.raw`
    <h3>Lectio brevis</h3>
    <div data-psalm="reading"></div>
    <script>var gabc = " (f3) \p() V/. Qui(e) ven(fh)tú(h)rus(h) est.(g.) (::)";</script>
  `;
  const [score] = parseScoredReference(html);
  assert.equal(score.source, "Chant Tools");
  assert.match(score.gabc, /p\(\) V\/\./);
});
