import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import type { LoadedScoredOffice } from "./breviariumGregorianum.ts";
import { canonicalVisibleContentDigest } from "./compiler.ts";
import type {
  ChantScore,
  OfficeDocument,
  OfficeHour,
  OfficeSection
} from "./types.ts";

interface EasterProper {
  date: string;
  collectIncipit: string;
  lauds: { sourceID: string; mode: string; incipit: string };
  vespers: { sourceID: string; mode: string; incipit: string };
}

const easterPropers: EasterProper[] = [{
  date: "2026-04-06",
  collectIncipit: "Deus, qui solemnitáte pascháli",
  lauds: { sourceID: "11971", mode: "8g", incipit: "Iesus iunxit se" },
  vespers: { sourceID: "2314", mode: "8g", incipit: "Qui sunt hi sermónes" }
}, {
  date: "2026-04-07",
  collectIncipit: "Deus, qui Ecclésiam tuam novo semper fœtu",
  lauds: { sourceID: "12689", mode: "8g", incipit: "Stetit Iesus" },
  vespers: { sourceID: "2148", mode: "8g", incipit: "Vidéte manus meas" }
}, {
  date: "2026-04-08",
  collectIncipit: "Deus, qui nos resurrectiónis Domínicæ ánnua solemnitáte",
  lauds: { sourceID: "12153", mode: "7c", incipit: "Míttite in déxteram" },
  vespers: { sourceID: "2023", mode: "8g", incipit: "Dixit Iesus" }
}, {
  date: "2026-04-09",
  collectIncipit: "Deus, qui diversitátem géntium",
  lauds: { sourceID: "11828", mode: "7a", incipit: "María stabat" },
  vespers: { sourceID: "2150", mode: "7b", incipit: "Tulérunt Dóminum meum" }
}, {
  date: "2026-04-10",
  collectIncipit: "Omnípotens sempitérne Deus, qui paschále sacraméntum",
  lauds: { sourceID: "12261", mode: "7c", incipit: "Undecim discípuli" },
  vespers: { sourceID: "2917", mode: "8g", incipit: "Data est mihi" }
}];

const curatedPrimeRequirements: Record<string, {
  orderedIncipits: string[];
  forbidden?: string[];
}> = {
  "2026-02-22:prime": {
    orderedIncipits: [
      "Séptimo Kaléndas Mártii Luna sexta Anno Dómini 2026",
      "Sancti Petri Damiáni",
      "Smyrnæ natális sancti Polycárpi",
      "℣. Et álibi",
      "℟. Deo grátias."
    ],
    forbidden: ["Vigilia sancti Matthiae Apostoli"]
  },
  "2026-12-24:prime": {
    orderedIncipits: [
      "Octavo Kalendas Ianuarii Luna sexta décima Anno Dómini 2026",
      "Anno a creatióne mundi",
      "Hic vox elevatur, et omnes genua flectunt",
      "Natívitas Dómini nostri Iesu Christi secúndum carnem",
      "Quod sequitur, legitur in tono Lectionis consueto; et surgunt omnes",
      "Eódem die natális sanctæ Anastásiæ",
      "Barcinóne, in Hispánia, item natális sancti Petri Nolásci",
      "Romæ, in cœmetério Aproniáni, sanctæ Eugéniæ",
      "Nicomedíæ pássio multórum míllium Mártyrum",
      "℣. Et álibi",
      "℟. Deo grátias."
    ]
  }
};

function officeKey(value: { date: string; hour: string }): string {
  return `${value.date}:${value.hour}`;
}

function localDateKey(office: OfficeDocument): string {
  return `${String(office.date.year).padStart(4, "0")}-`
    + `${String(office.date.month).padStart(2, "0")}-`
    + String(office.date.day).padStart(2, "0");
}

function sourceGABC(sourceID: string): string {
  const path = fileURLToPath(new URL(
    `../Fixtures/easter-octave-gabc/${sourceID}.gabc`,
    import.meta.url
  ));
  const gabc = readFileSync(path, "utf8").trim();
  if (!gabc.includes("%%")) {
    throw new Error(`Curated Gregobase ${sourceID} is malformed`);
  }
  return gabc;
}

function exactChant(sourceID: string, mode: string, incipit: string): ChantScore {
  const gabc = sourceGABC(sourceID);
  const snapshot = createHash("sha256").update(gabc).digest("hex");
  return {
    id: `curated-gregobase-${sourceID}-${snapshot.slice(0, 16)}`,
    incipit,
    gabc,
    mode,
    reviewStatus: "humanReviewed",
    provenance: {
      collection: "Gregobase",
      sourceBook: "Liber antiphonarius, 1960",
      sourceURL: `https://gregobase.selapa.net/chant.php?id=${sourceID}`,
      license: "CC0-1.0",
      snapshot
    },
    timeline: { events: [] }
  };
}

function cleanOrderedSections(source: LoadedScoredOffice): OfficeSection[] {
  if (!source.orderedSections) {
    throw new Error(`${officeKey(source)} has no ordered scaffold`);
  }
  return source.orderedSections.map((ordered, index) => {
    const {
      sourceOffset: _sourceOffset,
      sourceRole: _sourceRole,
      ...section
    } = structuredClone(ordered);
    return {
      ...section,
      id: `curated-${source.hour}-${index}`,
      english: null
    };
  });
}

function properAntiphon(office: OfficeDocument): string {
  const title = office.hour === "lauds"
    ? "Canticum: Benedictus"
    : "Canticum: Magnificat";
  const source = office.sections.find(section => section.title === title)?.latin;
  const match = source?.match(/\n\nAnt\. ([\s\S]+?)\n\nCanticum /);
  if (!match) {
    throw new Error(`${localDateKey(office)}:${office.hour} lacks its proper antiphon`);
  }
  return match[1].trim();
}

function properCollect(office: OfficeDocument): string {
  const source = office.sections.find(section => section.title === "Oratio")?.latin;
  const match = source?.match(/\n\nOrémus\.\n\n([\s\S]+?)\n\n℟\. Amen\.\s*$/);
  if (!match) {
    throw new Error(`${localDateKey(office)}:${office.hour} lacks its proper collect`);
  }
  return match[1].replace(/\n\n/g, "\n").trim();
}

function octaveVerse(office: OfficeDocument): string {
  const source = office.sections.find(
    section => section.title === "Versus (In loco Capituli)"
  )?.latin;
  const match = source?.match(/\n\n(Ant\. [\s\S]+)$/);
  if (!match) {
    throw new Error(`${localDateKey(office)}:${office.hour} lacks Hæc dies`);
  }
  return match[1].trim();
}

function generatedCanticleTemplate(
  scored: LoadedScoredOffice[],
  hour: OfficeHour,
  mode: string
): ChantScore {
  const templateKeys: Record<string, string> = {
    "lauds:8g": "2026-04-05:lauds",
    "lauds:7c": "2026-12-10:lauds",
    "lauds:7a": "2026-02-23:lauds",
    "vespers:8g": "2026-01-03:vespers",
    "vespers:7b": "2026-07-05:vespers"
  };
  const templateKey = templateKeys[`${hour}:${mode}`];
  if (!templateKey) {
    throw new Error(`No reviewed canticle template is pinned for ${hour} tone ${mode}`);
  }
  const canticleName = hour === "lauds"
    ? "Canticum Zachariæ"
    : "Canticum B. Mariæ Virginis";
  const matches = scored
    .filter(record => officeKey(record) === templateKey)
    .flatMap(record =>
    (record.orderedSections ?? []).flatMap(section => {
      const chant = section.chant;
      return section.title.includes(canticleName)
        && chant?.reviewStatus === "generatedFormula"
        && chant.mode === mode
        ? [chant]
        : [];
    })
  );
  if (matches.length === 0) {
    throw new Error(`No pinned ${canticleName} template exists for tone ${mode}`);
  }
  if (matches.length !== 1) {
    throw new Error(`${templateKey} has ${matches.length} generated ${canticleName} scores`);
  }
  return structuredClone(matches[0]);
}

function replaceEasterPropers(
  sections: OfficeSection[],
  office: OfficeDocument,
  sourceID: string,
  mode: string,
  scored: LoadedScoredOffice[]
): OfficeSection[] {
  const hour = office.hour;
  const verseIndex = 16;
  const antiphonIndex = 17;
  const canticleIndex = 18;
  const repeatedAntiphonIndex = 19;
  const collectIndex = 22;
  const antiphon = properAntiphon(office);
  const chant = exactChant(sourceID, mode, antiphon);

  sections[verseIndex] = {
    ...sections[verseIndex],
    kind: "versicle",
    title: "Versus (In loco Capituli)",
    latin: octaveVerse(office),
    chant: exactChant("2230", "2", "Hæc dies")
  };
  sections[antiphonIndex] = {
    ...sections[antiphonIndex],
    latin: antiphon,
    chant
  };
  sections[canticleIndex] = {
    ...sections[canticleIndex],
    chant: generatedCanticleTemplate(scored, hour, mode)
  };
  sections[repeatedAntiphonIndex] = {
    ...sections[repeatedAntiphonIndex],
    latin: antiphon.replace(/\s+\*\s+/, " "),
    chant
  };
  sections[collectIndex] = {
    ...sections[collectIndex],
    latin: properCollect(office)
  };
  return sections;
}

function easterOffice(
  office: OfficeDocument,
  proper: { sourceID: string; mode: string; incipit: string },
  collectIncipit: string,
  scaffold: LoadedScoredOffice,
  scored: LoadedScoredOffice[]
): OfficeDocument {
  const scaffoldSections = cleanOrderedSections(scaffold);
  const sections = office.hour === "lauds"
    ? scaffoldSections.slice(2)
    : scaffoldSections;
  replaceEasterPropers(sections, office, proper.sourceID, proper.mode, scored);
  const visibleLatin = sections.map(section => section.latin).join("\n");
  if (
    !visibleLatin.includes(proper.incipit)
    || !visibleLatin.includes(collectIncipit)
  ) {
    throw new Error(
      `${localDateKey(office)}:${office.hour} failed its pinned proper incipit check`
    );
  }
  const visibleContentDigest = canonicalVisibleContentDigest(sections);
  return {
    ...office,
    sourceVersion: `${office.sourceVersion}+curated-easter-octave`,
    format: "authoritativeOrdered",
    visibleContentDigest,
    sections,
    observance: office.observance ?? {
      observanceID: `curated/${localDateKey(office)}`,
      titleLatin: office.contextLabel,
      commemorations: []
    }
  };
}

function primeOffice(office: OfficeDocument): OfficeDocument {
  const key = `${localDateKey(office)}:prime`;
  const requirements = curatedPrimeRequirements[key];
  if (!requirements) throw new Error(`No curated Prime requirements exist for ${key}`);
  const sections = office.sections.map((section, index) => ({
    ...structuredClone(section),
    id: `curated-prime-${index}`,
    english: null,
    chant: null
  }));
  const martyrology = sections.find(section => section.title === "Martyrologium");
  if (!martyrology) {
    throw new Error(`${localDateKey(office)}:prime has an incomplete Martyrology`);
  }
  let previous = -1;
  for (const incipit of requirements.orderedIncipits) {
    const index = martyrology.latin.indexOf(incipit);
    if (index <= previous) {
      throw new Error(`${key} is missing or reorders Martyrology text "${incipit}"`);
    }
    previous = index;
  }
  for (const forbidden of requirements.forbidden ?? []) {
    if (martyrology.latin.includes(forbidden)) {
      throw new Error(`${key} contains suppressed Martyrology text "${forbidden}"`);
    }
  }
  return {
    ...office,
    sourceVersion: `${office.sourceVersion}+curated-martyrology-1960`,
    format: "authoritativeOrdered",
    visibleContentDigest: canonicalVisibleContentDigest(sections),
    sections,
    observance: office.observance ?? {
      observanceID: `curated/${localDateKey(office)}`,
      titleLatin: office.contextLabel,
      commemorations: []
    }
  };
}

export function curatedOfficePromotions(
  offices: OfficeDocument[],
  scored: LoadedScoredOffice[]
): ReadonlyMap<string, OfficeDocument> {
  const officesByKey = new Map(
    offices.map(office => [`${localDateKey(office)}:${office.hour}`, office])
  );
  const scoredByKey = new Map(scored.map(record => [officeKey(record), record]));
  const promoted = new Map<string, OfficeDocument>();
  const includedEasterPropers = easterPropers.filter(proper =>
    officesByKey.has(`${proper.date}:lauds`)
    || officesByKey.has(`${proper.date}:vespers`)
  );
  const laudsScaffold = scoredByKey.get("2026-04-05:lauds");
  const vespersScaffold = scoredByKey.get("2026-04-05:vespers");
  if (includedEasterPropers.length > 0 && (!laudsScaffold || !vespersScaffold)) {
    throw new Error("Pinned Easter Sunday scaffolds are unavailable");
  }
  for (const proper of includedEasterPropers) {
    for (const hour of ["lauds", "vespers"] as const) {
      const key = `${proper.date}:${hour}`;
      const office = officesByKey.get(key);
      if (!office) continue;
      promoted.set(
        key,
        easterOffice(
          office,
          proper[hour],
          proper.collectIncipit,
          hour === "lauds" ? laudsScaffold! : vespersScaffold!,
          scored
        )
      );
    }
  }
  for (const key of Object.keys(curatedPrimeRequirements)) {
    const office = officesByKey.get(key);
    if (!office) continue;
    promoted.set(key, primeOffice(office));
  }
  return promoted;
}

export function curatedPromotionChecksum(): string {
  const hash = createHash("sha256");
  for (const proper of easterPropers) {
    hash.update(JSON.stringify(proper));
    hash.update(sourceGABC(proper.lauds.sourceID));
    hash.update(sourceGABC(proper.vespers.sourceID));
  }
  hash.update(sourceGABC("2230"));
  hash.update(JSON.stringify(curatedPrimeRequirements));
  return hash.digest("hex");
}
