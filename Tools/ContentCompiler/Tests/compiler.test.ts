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
  loadCorpus,
  validateCorpus
} from "../Sources/compiler.ts";
import { parseGABC } from "../Sources/gabc.ts";
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
import {
  addingKnownGeneratedComplineReadings
} from "../Sources/generatedReadingCorpus.ts";
import {
  curatedOfficePromotions,
  curatedPromotionChecksum
} from "../Sources/curatedOfficePromotions.ts";
import type { OfficeDocument, OfficeSection } from "../Sources/types.ts";

const fixture = new URL("../Fixtures/evening-pilot.json", import.meta.url).pathname;
const engravingFixtures = JSON.parse(
  readFileSync(
    new URL("../../../HoursTests/Fixtures/gabc-engraving-fixtures.json", import.meta.url),
    "utf8"
  )
) as Array<{ name: string; scoreID: string; gabc: string; eventCount: number }>;

test("fixture validates only through the explicit development gate", () => {
  const corpus = loadCorpus(fixture);
  assert.throws(() => validateCorpus(corpus), /Release corpus gate failed/);
  const warnings = validateCorpus(corpus, true);
  assert.match(warnings.join(" "), /Development sample/);
});

test("release gate requires the complete 1962 through 2100 civil range", () => {
  const corpus = structuredClone(loadCorpus(fixture));
  corpus.manifest.coverage.isSample = false;
  assert.throws(
    () => validateCorpus(corpus),
    /Release corpus must cover 1962-01-01 through 2100-12-31/
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
    "1716a90339f7d4535abaada2e2b744860810f04754cb7c9711a8b3f34be4981c"
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
  const officeCount = db.prepare("SELECT COUNT(*) AS count FROM office_index").get() as { count: number };
  const dayCount = db.prepare("SELECT COUNT(*) AS count FROM days").get() as { count: number };
  const scoreCount = db.prepare("SELECT COUNT(*) AS count FROM scores").get() as { count: number };
  const payload = db.prepare(`
    SELECT documents.payload
    FROM office_index
    JOIN documents ON documents.id = office_index.document_id
    WHERE office_index.hour = 'vespers'
    LIMIT 1
  `).get() as { payload: Uint8Array };
  db.close();
  assert.equal(officeCount.count, 8);
  assert.equal(dayCount.count, 1);
  assert.equal(scoreCount.count, 8);
  assert.doesNotMatch(new TextDecoder().decode(payload.payload), /timeline/);
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
  const database = new URL(
    "../../../HoursApp/Resources/base-office.sqlite",
    import.meta.url
  ).pathname;
  const corpus = loadCompiledCorpus(database);
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

test("bundled chant text and timelines contain no leaked GABC percent comments", () => {
  const database = new URL(
    "../../../HoursApp/Resources/base-office.sqlite",
    import.meta.url
  ).pathname;
  const corpus = loadCompiledCorpus(database);
  const chantSections = corpus.offices.flatMap(office =>
    office.sections.filter(section => section.chant)
  );

  assert.ok(chantSections.length > 0);
  for (const section of chantSections) {
    assert.doesNotMatch(section.latin, /^\s*%/);
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
    offices
  };
  assert.doesNotThrow(() => validateCorpus(shippable, true));
  assert.throws(
    () => validateCorpus({
      ...shippable,
      offices: offices.map((office, index) => index === 1
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
