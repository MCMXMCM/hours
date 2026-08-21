import { DatabaseSync } from "node:sqlite";
import { decodeContentPayload } from "./contentPayload.ts";
import type {
  ChantScore,
  CorpusInput,
  LiturgicalDay,
  Manifest,
  OfficeDocument,
  OfficeHour,
  OfficeSection
} from "./types.ts";

function decodedJSON<T>(value: string | Uint8Array): T {
  return JSON.parse(decodeContentPayload(value)) as T;
}

function localDay(value: string): { year: number; month: number; day: number } {
  const [year, month, day] = value.split("-").map(Number);
  return { year, month, day };
}

function decodedScore(value: string | Uint8Array): ChantScore {
  const score = decodedJSON<ChantScore>(value);
  score.timeline.events = score.timeline.events.map(event => {
    const compact = event as unknown as Record<string, unknown>;
    if (!("i" in compact)) return event;
    const clef = compact.c as { k: "c" | "f"; l: 1 | 2 | 3 | 4; b: boolean } | null;
    return {
      id: compact.i as string,
      phraseID: compact.p as string,
      syllableID: compact.y as string,
      syllable: compact.s as string,
      relativePitch: compact.n as number,
      durationWeight: compact.d as number,
      modifiers: compact.m as ChantScore["timeline"]["events"][number]["modifiers"],
      clef: clef ? { kind: clef.k, line: clef.l, flattensB: clef.b } : null
    };
  });
  return score;
}

interface StoredSection extends OfficeSection {
  scoreID?: string | null;
}

interface StoredDocument extends Omit<OfficeDocument, "sections"> {
  sections: StoredSection[];
}

interface StoredRecipeHeader extends Omit<OfficeDocument, "id" | "date" | "sections"> {}

export interface CompiledCorpusRange {
  from: string;
  to: string;
}

function rangeSQL(range: CompiledCorpusRange | undefined, column: string): {
  clause: string;
  bindings: string[];
} {
  return range
    ? { clause: `WHERE ${column} BETWEEN ? AND ?`, bindings: [range.from, range.to] }
    : { clause: "", bindings: [] };
}

function loadV2Corpus(
  database: DatabaseSync,
  manifest: Manifest,
  days: LiturgicalDay[],
  range?: CompiledCorpusRange
): CorpusInput {
  const scheduleRange = rangeSQL(range, "office_schedule.date");
  const officeRows = database.prepare(`
    SELECT office_schedule.date, office_schedule.hour,
           office_schedule.recipe_id, recipes.payload
    FROM office_schedule
    JOIN recipes ON recipes.id = office_schedule.recipe_id
    ${scheduleRange.clause}
    ORDER BY office_schedule.date, office_schedule.hour
  `).all(...scheduleRange.bindings) as Array<{
    date: string;
    hour: OfficeHour;
    recipe_id: number;
    payload: Uint8Array;
  }>;
  const sectionRows = database.prepare(`
    SELECT DISTINCT recipe_sections.recipe_id, recipe_sections.position,
           recipe_sections.text_id, recipe_sections.score_id
    FROM recipe_sections
    JOIN office_schedule ON office_schedule.recipe_id = recipe_sections.recipe_id
    ${scheduleRange.clause}
    ORDER BY recipe_sections.recipe_id, recipe_sections.position
  `).all(...scheduleRange.bindings) as Array<{
    recipe_id: number;
    position: number;
    text_id: number;
    score_id: number | null;
  }>;
  const sectionsByRecipe = Map.groupBy(sectionRows, row => row.recipe_id);
  const textRows = database.prepare(`
    SELECT DISTINCT text_resources.id, text_resources.payload
    FROM text_resources
    JOIN recipe_sections ON recipe_sections.text_id = text_resources.id
    JOIN office_schedule ON office_schedule.recipe_id = recipe_sections.recipe_id
    ${scheduleRange.clause}
  `).all(...scheduleRange.bindings) as Array<{
    id: number;
    payload: Uint8Array;
  }>;
  const texts = new Map(textRows.map(row => [
    row.id,
    decodedJSON<Omit<OfficeSection, "id" | "chant">>(row.payload)
  ]));
  const scoreRows = database.prepare(`
    SELECT DISTINCT scores.id, scores.payload
    FROM scores
    JOIN recipe_sections ON recipe_sections.score_id = scores.id
    JOIN office_schedule ON office_schedule.recipe_id = recipe_sections.recipe_id
    ${scheduleRange.clause}
  `).all(...scheduleRange.bindings) as Array<{ id: number; payload: Uint8Array }>;
  const scores = new Map(
    scoreRows.map(row => [row.id, decodedScore(row.payload)])
  );
  const offices = officeRows.map(row => {
    const header = decodedJSON<StoredRecipeHeader>(row.payload);
    const sections = (sectionsByRecipe.get(row.recipe_id) ?? []).map(reference => {
      const resource = texts.get(reference.text_id);
      if (!resource) {
        throw new Error(`Recipe ${row.recipe_id} references missing text ${reference.text_id}`);
      }
      const chant = reference.score_id ? scores.get(reference.score_id) : null;
      if (reference.score_id && !chant) {
        throw new Error(`Recipe ${row.recipe_id} references missing score ${reference.score_id}`);
      }
      return {
        id: `${row.date}-${row.hour}-section-${reference.position}`,
        kind: resource.kind,
        title: resource.title,
        titleEnglish: resource.titleEnglish,
        rubric: resource.rubric,
        rubricEnglish: resource.rubricEnglish,
        latin: resource.latin,
        english: resource.english,
        chant
      };
    });
    return {
      ...header,
      id: `${row.date}-${row.hour}`,
      date: localDay(row.date),
      hour: row.hour,
      sections
    };
  });
  return { manifest, days, offices };
}

export function loadCompiledCorpus(
  path: string,
  range?: CompiledCorpusRange
): CorpusInput {
  const database = new DatabaseSync(path, { readOnly: true });
  try {
    const manifestRow = database.prepare(
      "SELECT value FROM meta WHERE key = ?"
    ).get("manifest") as { value: string };
    const manifest = decodedJSON<Manifest>(manifestRow.value);
    const dayRange = rangeSQL(range, "date");
    const dayRows = database.prepare(`
      SELECT payload FROM days
      ${dayRange.clause}
      ORDER BY date
    `).all(...dayRange.bindings) as Array<{ payload: Uint8Array }>;
    const days = dayRows.map(row => decodedJSON<LiturgicalDay>(row.payload));
    if (manifest.schemaVersion >= 2) {
      return loadV2Corpus(database, manifest, days, range);
    }
    const scoreRows = database.prepare(
      "SELECT id, payload FROM scores"
    ).all() as Array<{ id: string; payload: Uint8Array }>;
    const scores = new Map(
      scoreRows.map(row => [row.id, decodedScore(row.payload)])
    );
    const officeRows = database.prepare(`
      SELECT office_index.date, office_index.hour, documents.payload
      FROM office_index
      JOIN documents ON documents.id = office_index.document_id
      ${rangeSQL(range, "office_index.date").clause}
      ORDER BY office_index.date, office_index.hour
    `).all(...rangeSQL(range, "office_index.date").bindings) as Array<{
      date: string;
      hour: OfficeHour;
      payload: Uint8Array;
    }>;

    const offices = officeRows.map(row => {
      const stored = decodedJSON<StoredDocument>(row.payload);
      return {
        ...stored,
        id: `${row.date}-${row.hour}`,
        date: localDay(row.date),
        hour: row.hour,
        sections: stored.sections.map(section => {
          const { scoreID, ...plain } = section;
          if (scoreID && !scores.has(scoreID)) {
            throw new Error(
              `Compiled section ${section.id} references missing score ${scoreID}`
            );
          }
          return {
            ...plain,
            chant: scoreID ? scores.get(scoreID)! : null
          };
        })
      };
    });

    return {
      manifest,
      days,
      offices
    };
  } finally {
    database.close();
  }
}
